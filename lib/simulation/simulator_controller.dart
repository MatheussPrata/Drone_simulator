import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:drone_simulator/simulation/flight_physics.dart';
import 'package:drone_simulator/simulation/quadrotor_physics_6dof.dart';

export 'package:drone_simulator/models/drone_state.dart' show CameraViewMode;
export 'package:drone_simulator/simulation/quadrotor_physics_6dof.dart'
    show FlightControlMode, Vec3, PhysicsSnapshot, PilotStickInput;

/// Status operacional do simulador de voo.
enum SimulatorStatus {
  disarmed,
  takingOff,
  hovering,
  flying,
  rth,
  landing,
  landed,
  crashed,
}

/// Controlador central de simulação desacoplado da interface gráfica.
///
/// A cinemática vem do [QuadrotorPhysicsEngine] 6-DOF (240 Hz de sub-stepping),
/// inclusive nos modos automáticos, que geram entradas de stick sintéticas via
/// controlador de posição. O [FlightPhysics] legado permanece como fonte de
/// mapa/perfil e validação de geofence.
class SimulatorController extends ChangeNotifier {
  static const double fixedDt = 0.016; // 60 FPS (~16.6ms)
  static const double targetTakeoffAltitude = 10.0;
  static const double climbSpeed = 2.5;
  static const double descentSpeed = 2.0;
  static const double rthSpeed = 8.0;
  static const double rthAltitude = 15.0;

  /// Raio de colisão do corpo do drone (m).
  static const double droneRadiusMeters = 0.6;

  /// Impacto acima disso (m/s ≈ 40 km/h) derruba o drone.
  static const double crashImpactSpeedMs = 11.0;

  final FlightPhysics physics;
  final QuadrotorPhysicsEngine sixDof;

  Timer? _timer;

  SimulatorStatus _status = SimulatorStatus.landed;
  double _x = 0.0;
  double _y = 0.0;
  double _z = 0.0;
  double _yaw = 0.0;
  double _battery = 100.0;
  double _speedKmh = 0.0;
  bool _isArmed = false;
  CameraViewMode _cameraMode = CameraViewMode.fpv;
  bool _isMapPrimaryView = false;
  bool _isSatellite = true;
  FlightControlMode _flightMode = FlightControlMode.stabilized;

  double _manualThrottle = 0.0;
  double _manualYaw = 0.0;
  double _manualPitch = 0.0;
  double _manualRoll = 0.0;

  double _impactShake = 0.0;
  double _windSpeedMps = 0.0;
  double _benchPitchDeg = 0.0;
  double _benchRollDeg = 0.0;
  PhysicsSnapshot? _lastSnapshot;

  SimulatorController({
    FlightPhysics? physics,
    QuadrotorPhysicsEngine? sixDof,
  })  : physics = physics ?? FlightPhysics(),
        sixDof = sixDof ?? QuadrotorPhysicsEngine() {
    _applyMapWind(physics?.activeMap ?? this.physics.activeMap);
  }

  // ── Getters de estado ──
  SimulatorStatus get status => _status;
  double get x => _x;
  double get y => _y;
  double get z => _z;
  double get yaw => _yaw;
  double get battery => _battery;
  double get speedKmh => _speedKmh;
  double get gimbalPitch => physics.gimbalPitch;
  double get visualPitch => !_isArmed
      ? _benchPitchDeg
      : (_lastSnapshot != null
          ? _lastSnapshot!.pitchRad * 180.0 / pi
          : physics.visualPitch);
  double get visualRoll => !_isArmed
      ? _benchRollDeg
      : (_lastSnapshot != null
          ? _lastSnapshot!.rollRad * 180.0 / pi
          : physics.visualRoll);
  CameraViewMode get cameraMode => _cameraMode;
  bool get isMapPrimaryView => _isMapPrimaryView;
  bool get isSatellite => _isSatellite;
  FlightMap get activeMap => physics.activeMap;
  bool get isArmed => _isArmed;
  bool get isLanded => _status == SimulatorStatus.landed;
  bool get isHovering => _status == SimulatorStatus.hovering;
  bool get isTakingOff => _status == SimulatorStatus.takingOff;
  bool get isRTH => _status == SimulatorStatus.rth;
  bool get isLanding => _status == SimulatorStatus.landing;
  bool get isCrashed => _status == SimulatorStatus.crashed;
  bool get isRunning => _timer != null;
  double get impactShake => _impactShake;

  FlightControlMode get flightMode => _flightMode;
  String get flightModeLabel {
    switch (_flightMode) {
      case FlightControlMode.stabilized:
        return 'NORMAL';
      case FlightControlMode.sport:
        return 'SPORT';
      case FlightControlMode.acro:
        return 'ACRO';
    }
  }

  /// Inclinação real (radianos) vinda do motor 6-DOF.
  double get pitchRad => _lastSnapshot?.pitchRad ?? 0.0;
  double get rollRad => _lastSnapshot?.rollRad ?? 0.0;
  double get yawRad => _lastSnapshot?.yawRad ?? 0.0;

  /// Rotação normalizada dos 4 motores [FR, RL, FL, RR].
  List<double> get motorNormalizedRpm =>
      _lastSnapshot?.motorNormalizedRpm ?? const [0.0, 0.0, 0.0, 0.0];

  double get windSpeedMps => _windSpeedMps;
  bool get inVortexRingState => _lastSnapshot?.inVortexRingState ?? false;
  double get groundEffectFactor => _lastSnapshot?.groundEffectFactor ?? 1.0;

  DroneState get state {
    final snapshot = _lastSnapshot;
    return physics.state.copyWith(
      position: physics.state.position,
      altitude: _z,
      speedKmh: _speedKmh,
      verticalSpeedMs: snapshot?.verticalSpeedMps ?? 0.0,
      velocityEastMs: snapshot?.velocity.x ?? 0.0,
      velocityNorthMs: snapshot?.velocity.y ?? 0.0,
      pitch: _lastSnapshot?.pitchRad ?? physics.state.pitch,
      roll: _lastSnapshot?.rollRad ?? physics.state.roll,
      batteryPercent: _battery,
      isCrashed: _status == SimulatorStatus.crashed,
      impactShake: _impactShake,
    );
  }

  /// Alterna entre NORMAL → SPORT → ACRO.
  void cycleFlightMode() {
    switch (_flightMode) {
      case FlightControlMode.stabilized:
        _flightMode = FlightControlMode.sport;
        break;
      case FlightControlMode.sport:
        _flightMode = FlightControlMode.acro;
        break;
      case FlightControlMode.acro:
        _flightMode = FlightControlMode.stabilized;
        break;
    }
    notifyListeners();
  }

  void setFlightMode(FlightControlMode mode) {
    if (_flightMode != mode) {
      _flightMode = mode;
      notifyListeners();
    }
  }

  /// Alterna o modo de câmera entre 1ª Pessoa (FPV) e 3ª Pessoa.
  void toggleCameraMode() {
    _cameraMode = _cameraMode == CameraViewMode.fpv
        ? CameraViewMode.thirdPerson
        : CameraViewMode.fpv;
    notifyListeners();
  }

  void setCameraMode(CameraViewMode mode) {
    if (_cameraMode != mode) {
      _cameraMode = mode;
      notifyListeners();
    }
  }

  void togglePrimaryView() {
    _isMapPrimaryView = !_isMapPrimaryView;
    notifyListeners();
  }

  void setMapPrimaryView(bool isPrimary) {
    if (_isMapPrimaryView != isPrimary) {
      _isMapPrimaryView = isPrimary;
      notifyListeners();
    }
  }

  void toggleTileLayer() {
    _isSatellite = !_isSatellite;
    notifyListeners();
  }

  void setSatellite(bool value) {
    if (_isSatellite != value) {
      _isSatellite = value;
      notifyListeners();
    }
  }

  /// Seleciona um cenário de decolagem, redefine o Home e reseta o voo.
  void selectTakeoffLocation(FlightMap map) {
    physics.selectMap(map);
    _applyMapWind(map);
    reset();
  }

  /// Configura vento e turbulência específicos de cada cenário.
  void _applyMapWind(FlightMap map) {
    switch (WorldGenerator.scenarioFor(map)) {
      case WorldScenario.urban:
        sixDof.baseWindWorld = const Vec3(2.0, -1.0, 0.0);
        sixDof.turbulenceIntensity = 1.1;
        break;
      case WorldScenario.forest:
        sixDof.baseWindWorld = const Vec3(1.2, 0.6, 0.0);
        sixDof.turbulenceIntensity = 0.7;
        break;
      case WorldScenario.canyon:
        sixDof.baseWindWorld = const Vec3(4.2, -1.8, 0.2);
        sixDof.turbulenceIntensity = 1.5;
        break;
    }
    _windSpeedMps = sixDof.baseWindWorld.length;
  }

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      update(fixedDt);
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    stop();
    physics.dispose();
    super.dispose();
  }

  /// Arma os motores e sobe automaticamente até 10 m (física real).
  void armAndTakeoff() {
    if (_status == SimulatorStatus.crashed) {
      reset();
    }
    _isArmed = true;
    _status = SimulatorStatus.takingOff;
    sixDof.reset(
      position: Vec3(_x, _y, max(_z, 0.03)),
      yawRad: -_yaw * pi / 180.0,
      batteryPercent: _battery,
    );
    sixDof.setArmed(true);
    notifyListeners();
  }

  /// Inicia a descida até o solo.
  void land() {
    if (_status == SimulatorStatus.landed ||
        _status == SimulatorStatus.disarmed ||
        _status == SimulatorStatus.crashed) {
      return;
    }
    _status = SimulatorStatus.landing;
    notifyListeners();
  }

  /// Retorna ao Home com piloto automático e pousa.
  void triggerRTH() {
    if (_status == SimulatorStatus.landed ||
        _status == SimulatorStatus.landing ||
        _status == SimulatorStatus.crashed) {
      return;
    }
    _status = SimulatorStatus.rth;
    notifyListeners();
  }

  /// Reseta o simulador, a física 6-DOF e a bateria.
  void reset() {
    _status = SimulatorStatus.landed;
    _x = 0.0;
    _y = 0.0;
    _z = 0.0;
    _yaw = 0.0;
    _speedKmh = 0.0;
    _manualThrottle = 0.0;
    _manualYaw = 0.0;
    _manualPitch = 0.0;
    _manualRoll = 0.0;
    _battery = 100.0;
    _isArmed = false;
    _cameraMode = CameraViewMode.fpv;
    _isMapPrimaryView = false;
    _impactShake = 0.0;
    _flightMode = FlightControlMode.stabilized;
    physics.resetBattery();
    physics.selectMap(physics.activeMap);
    sixDof.reset(
      position: Vec3.zero,
      yawRad: 0.0,
      batteryPercent: 100.0,
    );
    sixDof.setArmed(false);
    _lastSnapshot = sixDof.snapshot;
    _applyMapWind(physics.activeMap);
    notifyListeners();
  }

  /// Define entradas manuais analógicas (Modo 2).
  void setManualInput({
    double throttle = 0.0,
    double yaw = 0.0,
    double pitch = 0.0,
    double roll = 0.0,
  }) {
    _manualThrottle = throttle.clamp(-1.0, 1.0);
    _manualYaw = yaw.clamp(-1.0, 1.0);
    _manualPitch = pitch.clamp(-1.0, 1.0);
    _manualRoll = roll.clamp(-1.0, 1.0);
    physics.setManualInput(_manualThrottle, _manualYaw, _manualPitch, _manualRoll);

    if ((_status == SimulatorStatus.hovering ||
            _status == SimulatorStatus.takingOff) &&
        (_manualThrottle.abs() > 0.05 ||
            _manualYaw.abs() > 0.05 ||
            _manualPitch.abs() > 0.05 ||
            _manualRoll.abs() > 0.05)) {
      _status = SimulatorStatus.flying;
    }
  }

  /// Posiciona o drone (usado por testes e teleporte).
  void setPosition(double newX, double newY, [double? newZ]) {
    _x = newX;
    _y = newY;
    if (newZ != null) _z = newZ;
    _syncSixDofPosition();
    notifyListeners();
  }

  void setYaw(double newYaw) {
    _yaw = (newYaw % 360.0 + 360.0) % 360.0;
    _syncSixDofPosition();
    notifyListeners();
  }

  void _syncSixDofPosition() {
    if (_isArmed) {
      sixDof.applyExternalCollisionCorrection(
        correctedPosition: Vec3(_x, _y, _z),
        correctedVelocity: const Vec3(0, 0, 0),
      );
      _lastSnapshot = sixDof.snapshot;
    }
  }

  void setBattery(double percent) {
    _battery = percent.clamp(0.0, 100.0);
    _checkBatteryFailSafe();
    notifyListeners();
  }

  void setGimbalPitch(double degrees) {
    physics.setGimbalPitch(degrees);
    notifyListeners();
  }

  void adjustGimbalPitch(double deltaDegrees) {
    physics.adjustGimbalPitch(deltaDegrees);
    notifyListeners();
  }

  void _checkBatteryFailSafe() {
    if (_battery < 15.0 &&
        _status != SimulatorStatus.rth &&
        _status != SimulatorStatus.landing &&
        _status != SimulatorStatus.landed &&
        _isArmed) {
      triggerRTH();
    }
  }

  // ────────────────────────────────────────────────────────────
  // Loop principal
  // ────────────────────────────────────────────────────────────

  /// Avança a simulação 6-DOF com delta time fixo (0.016s).
  void update([double dt = fixedDt]) {
    if (_isArmed && _status != SimulatorStatus.landed) {
      _checkBatteryFailSafe();
    }

    // Em solo/desarmado a atitude é apenas visual (bancada), como antes.
    if (!_isArmed) {
      final lerpFactor = (dt * 10.0).clamp(0.0, 1.0);
      _benchPitchDeg += ((_manualPitch * -25.0) - _benchPitchDeg) * lerpFactor;
      _benchRollDeg += ((_manualRoll * 25.0) - _benchRollDeg) * lerpFactor;
      if (_manualPitch == 0.0 && _benchPitchDeg.abs() < 0.05) {
        _benchPitchDeg = 0.0;
      }
      if (_manualRoll == 0.0 && _benchRollDeg.abs() < 0.05) {
        _benchRollDeg = 0.0;
      }
    } else {
      _benchPitchDeg = 0.0;
      _benchRollDeg = 0.0;
    }

    final input = _buildStickInput();
    final snapshot = sixDof.step(
      input: input,
      dt: dt,
      mode: _flightMode,
      groundHeightM: 0.0,
    );

    _applySnapshot(snapshot);
    _resolveWorldCollisions(snapshot);
    _advanceStatusMachine();

    _impactShake = max(0.0, _impactShake - dt * 1.5);
    notifyListeners();
  }

  void _applySnapshot(PhysicsSnapshot snapshot) {
    _lastSnapshot = snapshot;
    _x = snapshot.position.x;
    _y = snapshot.position.y;
    _z = snapshot.position.z;
    _yaw = ((-snapshot.yawRad * 180.0 / pi) % 360.0 + 360.0) % 360.0;
    _speedKmh = snapshot.speedKmh;
    _battery = snapshot.batteryPercent;
    _windSpeedMps = snapshot.windVelocityWorld.length;
  }

  /// Gera sticks sintéticos para modos automáticos (decolagem, RTH, pouso).
  PilotStickInput _buildStickInput() {
    switch (_status) {
      case SimulatorStatus.takingOff:
        final throttle = ((targetTakeoffAltitude - _z) * 0.6).clamp(-0.3, 1.0);
        return PilotStickInput(throttle: throttle);

      case SimulatorStatus.rth:
        // Navega para o Home com controlador de velocidade em malha fechada.
        final dx = -_x;
        final dy = -_y;
        final yawRadNow = _lastSnapshot?.yawRad ?? 0.0;
        final forwardX = -sin(yawRadNow);
        final forwardY = cos(yawRadNow);
        final rightX = cos(yawRadNow);
        final rightY = sin(yawRadNow);

        final vx = _lastSnapshot?.velocity.x ?? 0.0;
        final vy = _lastSnapshot?.velocity.y ?? 0.0;

        // Velocidade desejada proporcional à distância restante (com teto).
        final desiredVx = (dx * 1.2).clamp(-8.0, 8.0);
        final desiredVy = (dy * 1.2).clamp(-8.0, 8.0);
        final errVx = desiredVx - vx;
        final errVy = desiredVy - vy;

        final forwardError = errVx * forwardX + errVy * forwardY;
        final rightError = errVx * rightX + errVy * rightY;

        return PilotStickInput(
          throttle: ((rthAltitude - _z) * 0.4).clamp(-0.5, 1.0),
          pitch: (forwardError * 0.16).clamp(-0.6, 0.6),
          roll: (rightError * 0.16).clamp(-0.6, 0.6),
        );

      case SimulatorStatus.landing:
        // Desce mantendo correção horizontal suave em direção ao Home.
        final yawRadNow = _lastSnapshot?.yawRad ?? 0.0;
        final forwardX = -sin(yawRadNow);
        final forwardY = cos(yawRadNow);
        final rightX = cos(yawRadNow);
        final rightY = sin(yawRadNow);
        final vx = _lastSnapshot?.velocity.x ?? 0.0;
        final vy = _lastSnapshot?.velocity.y ?? 0.0;

        final errVx = (-_x * 0.9).clamp(-3.0, 3.0) - vx;
        final errVy = (-_y * 0.9).clamp(-3.0, 3.0) - vy;

        return PilotStickInput(
          throttle: -1.0,
          pitch: ((errVx * forwardX + errVy * forwardY) * 0.12)
              .clamp(-0.4, 0.4),
          roll: ((errVx * rightX + errVy * rightY) * 0.12)
              .clamp(-0.4, 0.4),
        );

      case SimulatorStatus.hovering:
      case SimulatorStatus.flying:
        return PilotStickInput(
          throttle: _manualThrottle,
          pitch: _manualPitch,
          roll: _manualRoll,
          yaw: _manualYaw,
        );

      case SimulatorStatus.disarmed:
      case SimulatorStatus.landed:
      case SimulatorStatus.crashed:
        return PilotStickInput.neutral;
    }
  }

  void _advanceStatusMachine() {
    switch (_status) {
      case SimulatorStatus.takingOff:
        if (_z >= targetTakeoffAltitude - 0.15) {
          _status = SimulatorStatus.hovering;
        }
        break;

      case SimulatorStatus.rth:
        if (sqrt(_x * _x + _y * _y) < 1.5) {
          // Alinhado ao Home: encaixa o ponto de pouso e inicia a descida.
          _x = 0.0;
          _y = 0.0;
          _status = SimulatorStatus.landing;
        }
        break;

      case SimulatorStatus.landing:
        if (_z <= 0.08) {
          _z = 0.0;
          // Pouso automático: encaixa no Home se já estiver próximo.
          if (sqrt(_x * _x + _y * _y) <= 2.5) {
            _x = 0.0;
            _y = 0.0;
          }
          _status = SimulatorStatus.landed;
          _isArmed = false;
          sixDof.setArmed(false);
        }
        break;

      case SimulatorStatus.crashed:
        if (_z <= 0.02) {
          _z = 0.0;
          _status = SimulatorStatus.landed;
          _isArmed = false;
        }
        break;

      case SimulatorStatus.hovering:
      case SimulatorStatus.flying:
      case SimulatorStatus.disarmed:
      case SimulatorStatus.landed:
        break;
    }
  }

  // ────────────────────────────────────────────────────────────
  // Colisão com obstáculos 3D
  // ────────────────────────────────────────────────────────────

  void _resolveWorldCollisions(PhysicsSnapshot snapshot) {
    if (!_isArmed || _status == SimulatorStatus.crashed) return;

    final obstacles = WorldGenerator.generateFor(activeMap);
    if (obstacles.isEmpty) return;

    var east = snapshot.position.x;
    var north = snapshot.position.y;
    var altitude = snapshot.position.z;
    var velocity = snapshot.velocity;

    double velocityEast = velocity.x;
    double velocityNorth = velocity.y;

    bool collided = false;
    double impactSpeed = 0.0;
    double normalX = 0.0;
    double normalY = 0.0;

    for (final WorldObstacle obstacle in obstacles) {
      if (altitude >= obstacle.height) continue;
      if (!obstacle.collidesAt(east, north, droneRadiusMeters)) continue;

      final resolved = obstacle.resolve(east, north, droneRadiusMeters);
      east = resolved.x;
      north = resolved.y;

      final incoming =
          sqrt(velocityEast * velocityEast + velocityNorth * velocityNorth);
      impactSpeed = max(impactSpeed, incoming);

      normalX = resolved.normalX;
      normalY = resolved.normalY;
      collided = true;
    }

    if (!collided) return;

    final correctedVelocity = Vec3(
      velocityEast * 0.75 + normalX * impactSpeed * 0.25,
      velocityNorth * 0.75 + normalY * impactSpeed * 0.25,
      velocity.z,
    );

    sixDof.applyExternalCollisionCorrection(
      correctedPosition: Vec3(east, north, altitude),
      correctedVelocity: correctedVelocity,
      angularImpulseBody: Vec3(
        normalY * impactSpeed * 0.08,
        -normalX * impactSpeed * 0.08,
        (impactSpeed * 0.02).clamp(-0.4, 0.4),
      ),
    );

    _impactShake = max(_impactShake, (impactSpeed / 12.0).clamp(0.15, 1.0));

    if (impactSpeed > crashImpactSpeedMs) {
      _status = SimulatorStatus.crashed;
      _isArmed = false;
      sixDof.setArmed(false);
    }

    _x = east;
    _y = north;
    _lastSnapshot = sixDof.snapshot;
  }
}
