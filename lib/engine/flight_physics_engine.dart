import 'dart:async';
import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'package:drone_simulator/core/utils/geo_math.dart';
import 'package:drone_simulator/models/drone_state.dart';
import 'package:drone_simulator/models/drone_profile.dart';
import 'package:drone_simulator/models/flight_map.dart';
import 'package:drone_simulator/models/waypoint.dart';
import 'package:drone_simulator/simulation/geofence_validator.dart';

class FlightPhysicsEngine {
  Timer? _timer;
  DroneState _state;
  FlightMap _activeMap;
  List<Waypoint> _waypoints = [];
  int _currentWaypointIndex = 0;
  double _hoverTimer = 0.0;
  double _manualThrottle = 0.0;
  double _manualYaw = 0.0;
  double _manualPitch = 0.0;
  double _manualRoll = 0.0;
  double _velocityX = 0.0; // m/s East-West
  double _velocityY = 0.0; // m/s North-South
  double _verticalVelocity = 0.0; // m/s Up-Down
  double _visualPitch = 0.0;
  double _visualRoll = 0.0;
  double _gimbalPitch = 0.0;

  /// Aceleração da gravidade (m/s²).
  static const double gravity = 9.81;

  /// Ângulo de inclinação real (atitudo) aplicado ao modelo de forças.
  double _attitudePitch = 0.0;
  double _attitudeRoll = 0.0;

  /// Altitude que o piloto automático tenta manter no ponto neutro do throttle.
  double _hoverAnchorAltitude = 0.0;
  double _hoverPhase = 0.0;

  /// Velocidade informada por modos automáticos (RTH/pouso). -1 = calcular.
  double _externalSpeedKmh = -1.0;

  final Random _random = Random();

  Function(DroneState)? onStateChanged;

  DroneState get state => _state;
  FlightMap get activeMap => _activeMap;
  double get visualPitch => _visualPitch;
  double get visualRoll => _visualRoll;
  double get gimbalPitch => _gimbalPitch;

  /// Deslocamento em metros a leste do ponto Home.
  double get eastMeters => GeoMath.offsetToMeters(_state.position, _state.homePosition).$1;

  /// Deslocamento em metros ao norte do ponto Home.
  double get northMeters => GeoMath.offsetToMeters(_state.position, _state.homePosition).$2;

  /// Sincroniza a cinemática da engine com um modo automático controlado
  /// externamente (decolagem, RTH, pouso), mantendo HUD, minimapa e cena 3D
  /// exatamente na mesma coordenada.
  void syncExternal({
    required double east,
    required double north,
    required double altitude,
    required double heading,
    double? speedKmh,
  }) {
    final position = GeoMath.offsetByMeters(_state.homePosition, east, north);
    _velocityX = 0.0;
    _velocityY = 0.0;
    _verticalVelocity = 0.0;
    _hoverAnchorAltitude = altitude;
    _externalSpeedKmh = speedKmh ?? -1.0;
    _state = _state.copyWith(
      position: position,
      altitude: altitude,
      heading: (heading % 360.0 + 360.0) % 360.0,
      speedKmh: speedKmh ?? 0.0,
      verticalSpeedMs: 0.0,
      velocityEastMs: 0.0,
      velocityNorthMs: 0.0,
    );
  }

  FlightPhysicsEngine({FlightMap? initialMap})
      : _activeMap = initialMap ?? FlightMap.dronePark,
        _state = DroneState(
          position: (initialMap ?? FlightMap.dronePark).homePosition,
          homePosition: (initialMap ?? FlightMap.dronePark).homePosition,
          activeProfile: DroneProfile.mini249g,
          activeMap: initialMap ?? FlightMap.dronePark,
        );

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 50), _tick);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
  }

  /// Avança a simulação física por um intervalo de tempo [dt] segundos.
  /// Padrão 60 FPS: 0.016s.
  void update([double dt = 0.016]) {
    _step(dt);
  }

  /// Avança a simulação física por um intervalo de tempo [dt] segundos.
  /// Pode ser chamado manualmente em testes unitários determinísticos.
  void tick([double dt = 0.05]) {
    _step(dt);
  }

  void _tick(Timer t) => tick(0.05);

  void _step(double dt) {
    final profile = _state.activeProfile;

    if (_state.flightMode == FlightMode.disarmed) {
      // Interpolação suave (lerp) e auto-nivelamento para visualPitch e visualRoll mesmo em solo/bancada
      final double targetPitch = (_manualPitch * -25.0).clamp(-30.0, 30.0);
      final double targetRoll = (_manualRoll * 25.0).clamp(-30.0, 30.0);
      final double lerpFactor = (dt * 10.0).clamp(0.0, 1.0);
      _visualPitch += (targetPitch - _visualPitch) * lerpFactor;
      _visualRoll += (targetRoll - _visualRoll) * lerpFactor;
      if (_manualPitch == 0.0 && _visualPitch.abs() < 0.01) {
        _visualPitch = 0.0;
      }
      if (_manualRoll == 0.0 && _visualRoll.abs() < 0.01) {
        _visualRoll = 0.0;
      }
      _state = _state.copyWith(
        pitch: _visualPitch,
        roll: _visualRoll,
        visualPitch: _visualPitch,
        visualRoll: _visualRoll,
        gimbalPitch: _gimbalPitch,
      );
      onStateChanged?.call(_state);
      return;
    }

    // ── Wind simulation ──
    final windRadians = _state.windDirectionDeg * pi / 180.0;
    final windSpeedMs = _state.windSpeedKmh / 3.6;
    final windForceX = windSpeedMs * sin(windRadians) * profile.windSensitivity;
    final windForceY = windSpeedMs * cos(windRadians) * profile.windSensitivity;

    double newBattery = _state.batteryPercent;
    double baseDrain = profile.baseDrainPerSecond * dt;

    // ── Mode-specific logic ──
    switch (_state.flightMode) {
      case FlightMode.hover:
      case FlightMode.manual:
        _processManualFlight(dt, profile, windForceX, windForceY);
        break;
      case FlightMode.autoMission:
        _processAutoMission(dt, profile, windForceX, windForceY);
        break;
      case FlightMode.rtl:
        _processRTL(dt, profile, windForceX, windForceY);
        break;
      case FlightMode.landing:
        _processLanding(dt, windForceX, windForceY);
        break;
      case FlightMode.disarmed:
        break;
    }

    // ── Wind drift (ATTI mode) or GPS compensation ──
    if (!_state.gpsLocked) {
      _velocityX += windForceX * dt;
      _velocityY += windForceY * dt;
    } else {
      // GPS compensates but costs more battery
      baseDrain += baseDrain * (windSpeedMs / 10.0).clamp(0.0, 1.5);
    }

    // ── Position update ──
    final candidatePosition = GeoMath.offsetByMeters(
      _state.position,
      _velocityX * dt,
      _velocityY * dt,
    );

    // ── Altitude update (com teto máximo do mapa modelado) ──
    double newAltitude = (_state.altitude + _verticalVelocity * dt).clamp(0.0, _activeMap.maxAltitudeMeters);
    bool altitudeBreach = false;
    if (newAltitude >= _activeMap.maxAltitudeMeters) {
      _verticalVelocity = min(0.0, _verticalVelocity);
      altitudeBreach = true;
    }

    // ── Geofence & No-Fly Zone validation via GeofenceValidator ──
    final validation = GeofenceValidator.validate(
      position: candidatePosition,
      map: _activeMap,
      velocityX: _velocityX,
      velocityY: _velocityY,
      altitude: newAltitude,
    );

    final LatLng newPosition = validation.position;
    _velocityX = validation.velocityX;
    _velocityY = validation.velocityY;
    final double distFromCenter = validation.distanceFromCenter;
    final bool breach = validation.isGeofenceBreach || altitudeBreach;
    final bool isWarning = validation.isGeofenceWarning;
    final bool inNfz = validation.inNoFlyZone;
    final bool isNfWarning = validation.isNoFlyWarning;
    final String? nfzName = validation.currentNfzName;

    // ── Speed calculation (magnitude 3D real, em km/h) ──
    final horizontalSpeed = sqrt(_velocityX * _velocityX + _velocityY * _velocityY);
    double speedKmh = sqrt(horizontalSpeed * horizontalSpeed +
            _verticalVelocity * _verticalVelocity) *
        3.6;
    if (_externalSpeedKmh >= 0) {
      speedKmh = _externalSpeedKmh;
    }
    _externalSpeedKmh = -1.0;

    // ── Battery drain ──
    if (_verticalVelocity > 0) {
      baseDrain += baseDrain * 0.5; // climbing costs more
    }
    baseDrain += baseDrain * (speedKmh / profile.maxSpeedKmh) * 0.3;
    newBattery = (newBattery - baseDrain).clamp(0.0, 100.0);
    final newVoltage = 9.9 + (newBattery / 100.0) * 2.7;

    // ── Visual pitch/roll: nos modos manuais reflete a atitude real do
    // modelo de forças; nos modos automáticos segue o perfil de voo ──
    double targetPitch;
    double targetRoll;

    if (_state.flightMode == FlightMode.autoMission ||
        _state.flightMode == FlightMode.rtl) {
      targetPitch =
          (-(horizontalSpeed / (profile.maxSpeedKmh / 3.6)) * 15.0).clamp(-25.0, 25.0);
      targetRoll = 0.0;
    } else if (_state.flightMode == FlightMode.landing) {
      targetPitch = 0.0;
      targetRoll = 0.0;
    } else {
      targetPitch = _attitudePitch;
      targetRoll = _attitudeRoll;
    }

    final double lerpFactor = (dt * 10.0).clamp(0.0, 1.0);
    _visualPitch += (targetPitch - _visualPitch) * lerpFactor;
    _visualRoll += (targetRoll - _visualRoll) * lerpFactor;

    if (_manualPitch == 0.0 && _visualPitch.abs() < 0.05) {
      _visualPitch = 0.0;
    }
    if (_manualRoll == 0.0 && _visualRoll.abs() < 0.05) {
      _visualRoll = 0.0;
    }

    // ── Fail-safe: RTL at 15% battery ──
    FlightMode newMode = _state.flightMode;
    if (newBattery <= 15.0 &&
        newMode != FlightMode.rtl &&
        newMode != FlightMode.landing &&
        newMode != FlightMode.disarmed) {
      newMode = FlightMode.rtl;
    }

    // ── Landing complete ──
    if (newMode == FlightMode.landing && newAltitude <= 0.1) {
      newAltitude = 0.0;
      _velocityX = 0.0;
      _velocityY = 0.0;
      _verticalVelocity = 0.0;
      newMode = FlightMode.disarmed;
      _visualPitch = 0.0;
      _visualRoll = 0.0;
    }

    _state = _state.copyWith(
      position: newPosition,
      altitude: newAltitude,
      speedKmh: speedKmh,
      verticalSpeedMs: _verticalVelocity,
      velocityEastMs: _velocityX,
      velocityNorthMs: _velocityY,
      heading: _state.heading,
      pitch: _visualPitch,
      roll: _visualRoll,
      visualPitch: _visualPitch,
      visualRoll: _visualRoll,
      gimbalPitch: _gimbalPitch,
      batteryPercent: newBattery,
      voltage: newVoltage,
      flightMode: newMode,
      distanceFromCenter: distFromCenter,
      isGeofenceWarning: isWarning,
      isGeofenceBreach: breach,
      inNoFlyZone: inNfz,
      isNoFlyWarning: isNfWarning,
      currentNfzName: nfzName,
    );

    onStateChanged?.call(_state);
  }

  void _processManualFlight(
      double dt, DroneProfile profile, double windForceX, double windForceY) {
    // ── Yaw ──
    const double yawRate = 120.0; // deg/sec
    double newHeading = (_state.heading + _manualYaw * yawRate * dt) % 360.0;
    if (newHeading < 0) newHeading += 360.0;

    // ── Atitude alvo (pitch/roll até ±30°) com suavização (lerp) ──
    final double targetPitch = (_manualPitch * -30.0).clamp(-30.0, 30.0);
    final double targetRoll = (_manualRoll * 30.0).clamp(-30.0, 30.0);
    final double attitudeLerp = (dt * 8.0).clamp(0.0, 1.0);
    _attitudePitch += (targetPitch - _attitudePitch) * attitudeLerp;
    _attitudeRoll += (targetRoll - _attitudeRoll) * attitudeLerp;

    // Auto-nivelamento: sem entrada manual, a atitude volta a zero.
    if (!_hasManualTiltInput) {
      if (_attitudePitch.abs() < 0.05) _attitudePitch = 0.0;
      if (_attitudeRoll.abs() < 0.05) _attitudeRoll = 0.0;
    }

    // ── Eixo vertical: empuxo x gravidade ──
    if (_manualThrottle.abs() <= 0.06) {
      // Ponto neutro do stick = hover: a sustentação compensa a gravidade,
      // com micro-oscilação senoidal de ±0.05 m para parecer vivo no ar.
      _hoverPhase += dt;
      final double targetAltitude =
          _hoverAnchorAltitude + sin(_hoverPhase * 2.1) * 0.05;
      final double error = targetAltitude - _state.altitude;
      final double hoverAccel =
          (error * 2.6 - _verticalVelocity * 1.9).clamp(-4.0, 4.0);
      _verticalVelocity += hoverAccel * dt;
    } else {
      // Empuxo além do necessário para vencer a gravidade: a subida ganha
      // inércia e, ao soltar o stick, o arrasto freia a descida/subida.
      _hoverAnchorAltitude = _state.altitude;
      final double thrustAccel = _manualThrottle > 0
          ? _manualThrottle * profile.maxAscentMs * 1.6
          : _manualThrottle * profile.maxDescentMs * 1.6;
      _verticalVelocity += thrustAccel * dt;
    }

    // Arrasto vertical proporcional à velocidade.
    _verticalVelocity -=
        _verticalVelocity * _verticalVelocity.abs() * 0.02 * dt;
    _verticalVelocity = _verticalVelocity.clamp(
      -profile.maxDescentMs,
      profile.maxAscentMs,
    );

    // ── Eixo horizontal: projeção da inclinação (quanto mais inclinado,
    // mais rápido acelera) ──
    final double pitchRad = _attitudePitch * pi / 180.0;
    final double rollRad = _attitudeRoll * pi / 180.0;

    // Pitch negativo (nariz para baixo) gera aceleração para frente.
    final double accelForward = -tan(pitchRad) * gravity;
    final double accelRight = tan(rollRad) * gravity;

    final double headingRad = newHeading * pi / 180.0;
    final double forwardX = sin(headingRad);
    final double forwardY = cos(headingRad);
    final double rightX = cos(headingRad);
    final double rightY = -sin(headingRad);

    _velocityX += (forwardX * accelForward + rightX * accelRight) * dt;
    _velocityY += (forwardY * accelForward + rightY * accelRight) * dt;

    // ── Arrasto aerodinâmico (quadrático + linear): ao soltar o stick o
    // drone desliza, inclinando levemente para frear, até parar ──
    final double horizontalSpeed =
        sqrt(_velocityX * _velocityX + _velocityY * _velocityY);
    if (horizontalSpeed > 0.0001) {
      final double dragAccel =
          0.55 * horizontalSpeed + 0.012 * horizontalSpeed * horizontalSpeed;
      final double scale =
          (1.0 - (dragAccel * dt) / horizontalSpeed).clamp(0.0, 1.0);
      _velocityX *= scale;
      _velocityY *= scale;
      if (!_hasManualTiltInput && horizontalSpeed < 0.08) {
        _velocityX = 0.0;
        _velocityY = 0.0;
      }
    }

    // ── Turbulência leve acima de 1 m de altitude ──
    if (_state.altitude > 1.0) {
      _velocityX += (_random.nextDouble() * 2.0 - 1.0) * 0.12 * dt;
      _velocityY += (_random.nextDouble() * 2.0 - 1.0) * 0.12 * dt;
    }

    // ── Influência do vento configurado ──
    _velocityX += windForceX * 0.05 * dt;
    _velocityY += windForceY * 0.05 * dt;

    // ── Clamp horizontal no máximo do perfil ──
    final double maxSpeedMs = profile.maxSpeedKmh / 3.6;
    final double currentSpeed =
        sqrt(_velocityX * _velocityX + _velocityY * _velocityY);
    if (currentSpeed > maxSpeedMs) {
      final double scale = maxSpeedMs / currentSpeed;
      _velocityX *= scale;
      _velocityY *= scale;
    }

    _state = _state.copyWith(heading: newHeading);
  }

  bool get _hasManualTiltInput =>
      _manualPitch.abs() > 0.05 || _manualRoll.abs() > 0.05;

  void _processAutoMission(
      double dt, DroneProfile profile, double windForceX, double windForceY) {
    if (_waypoints.isEmpty || _currentWaypointIndex >= _waypoints.length) {
      _state = _state.copyWith(flightMode: FlightMode.hover);
      return;
    }

    final target = _waypoints[_currentWaypointIndex];
    final distance = GeoMath.distanceMeters(_state.position, target.position);
    final targetBearing = GeoMath.bearing(_state.position, target.position);

    // Smooth heading rotation toward waypoint
    double headingDiff = targetBearing - _state.heading;
    if (headingDiff > 180) headingDiff -= 360;
    if (headingDiff < -180) headingDiff += 360;
    const rotationRate = 90.0; // degrees per second
    final maxRotation = rotationRate * dt;
    final rotation = headingDiff.clamp(-maxRotation, maxRotation);
    double newHeading = (_state.heading + rotation + 360.0) % 360.0;

    // Altitude adjustment
    final altDiff = target.targetAltitude - _state.altitude;
    if (altDiff.abs() > 0.5) {
      _verticalVelocity = altDiff > 0
          ? profile.maxAscentMs.clamp(0.0, altDiff.abs())
          : -profile.maxDescentMs.clamp(0.0, altDiff.abs());
    } else {
      _verticalVelocity *= 0.9;
    }

    if (distance > 3.0) {
      // Navigate toward waypoint
      _hoverTimer = 0.0;
      final headingRad = newHeading * pi / 180.0;
      final cruiseSpeed = (profile.maxSpeedKmh * 0.6) / 3.6; // 60% max speed
      final targetSpeed = (distance > 20)
          ? cruiseSpeed
          : cruiseSpeed * (distance / 20.0).clamp(0.3, 1.0);

      final currentSpeed = sqrt(_velocityX * _velocityX + _velocityY * _velocityY);
      if (currentSpeed < targetSpeed) {
        _velocityX += sin(headingRad) * profile.accelerationMs2 * dt;
        _velocityY += cos(headingRad) * profile.accelerationMs2 * dt;
      }

      // Clamp speed
      final speed = sqrt(_velocityX * _velocityX + _velocityY * _velocityY);
      if (speed > targetSpeed) {
        final scale = targetSpeed / speed;
        _velocityX *= scale;
        _velocityY *= scale;
      }
    } else {
      // Near waypoint - decelerate and hover
      _velocityX *= 0.85;
      _velocityY *= 0.85;
      _hoverTimer += dt;

      if (_hoverTimer >= target.hoverSeconds) {
        _currentWaypointIndex++;
        _hoverTimer = 0.0;
        if (_currentWaypointIndex >= _waypoints.length) {
          _state = _state.copyWith(flightMode: FlightMode.hover);
        }
      }
    }

    _state = _state.copyWith(heading: newHeading);
  }

  void _processRTL(
      double dt, DroneProfile profile, double windForceX, double windForceY) {
    // Phase 1: Climb to 30m safety altitude
    if (_state.altitude < 30.0) {
      _verticalVelocity = profile.maxAscentMs * 0.8;
      _velocityX *= 0.95;
      _velocityY *= 0.95;
      return;
    }

    // Phase 2: Navigate to home
    final distance = GeoMath.distanceMeters(_state.position, _state.homePosition);
    final targetBearing = GeoMath.bearing(_state.position, _state.homePosition);

    // Smooth heading rotation
    double headingDiff = targetBearing - _state.heading;
    if (headingDiff > 180) headingDiff -= 360;
    if (headingDiff < -180) headingDiff += 360;
    final maxRotation = 90.0 * dt;
    final rotation = headingDiff.clamp(-maxRotation, maxRotation);
    double newHeading = (_state.heading + rotation + 360.0) % 360.0;

    _verticalVelocity *= 0.95; // maintain altitude

    if (distance > 3.0) {
      final headingRad = newHeading * pi / 180.0;
      final rtlSpeed = (profile.maxSpeedKmh * 0.5) / 3.6;
      _velocityX += sin(headingRad) * profile.accelerationMs2 * dt;
      _velocityY += cos(headingRad) * profile.accelerationMs2 * dt;

      final speed = sqrt(_velocityX * _velocityX + _velocityY * _velocityY);
      if (speed > rtlSpeed) {
        final scale = rtlSpeed / speed;
        _velocityX *= scale;
        _velocityY *= scale;
      }
    } else {
      // Arrived home - begin landing
      _velocityX *= 0.8;
      _velocityY *= 0.8;
      _state = _state.copyWith(flightMode: FlightMode.landing);
    }

    _state = _state.copyWith(heading: newHeading);
  }

  void _processLanding(double dt, double windForceX, double windForceY) {
    _verticalVelocity = -1.5; // descend at 1.5 m/s
    _velocityX *= 0.95;
    _velocityY *= 0.95;
  }

  // ── Public API ──

  void selectMap(FlightMap newMap) {
    _activeMap = newMap;
    if (_state.flightMode == FlightMode.disarmed) {
      _visualPitch = 0.0;
      _visualRoll = 0.0;
      _gimbalPitch = 0.0;
      _state = _state.copyWith(
        activeMap: newMap,
        position: newMap.homePosition,
        homePosition: newMap.homePosition,
        altitude: 0.0,
        pitch: 0.0,
        roll: 0.0,
        visualPitch: 0.0,
        visualRoll: 0.0,
        gimbalPitch: 0.0,
      );
    } else {
      _state = _state.copyWith(activeMap: newMap);
    }
    onStateChanged?.call(_state);
  }

  void setManualInput(double throttle, double yaw, double pitch, double roll) {
    _manualThrottle = throttle.clamp(-1.0, 1.0);
    _manualYaw = yaw.clamp(-1.0, 1.0);
    _manualPitch = pitch.clamp(-1.0, 1.0);
    _manualRoll = roll.clamp(-1.0, 1.0);
  }

  /// Define o ângulo de inclinação do gimbal da câmera (pitch).
  /// Clamped entre -90.0° (olhando para o solo) e 0.0° (olhando para o horizonte).
  void setGimbalPitch(double degrees) {
    _gimbalPitch = degrees.clamp(-90.0, 0.0);
    _state = _state.copyWith(gimbalPitch: _gimbalPitch);
    onStateChanged?.call(_state);
  }

  /// Ajusta incrementalmente o pitch do gimbal por [deltaDegrees].
  void adjustGimbalPitch(double deltaDegrees) {
    setGimbalPitch(_gimbalPitch + deltaDegrees);
  }

  void takeoff() {
    if (_state.flightMode == FlightMode.disarmed) {
      _state = _state.copyWith(
        flightMode: FlightMode.hover,
        altitude: 2.0,
        homePosition: _state.position,
      );
      _verticalVelocity = 0.0;
      _velocityX = 0.0;
      _velocityY = 0.0;
      _attitudePitch = 0.0;
      _attitudeRoll = 0.0;
      _hoverAnchorAltitude = 2.0;
      _hoverPhase = 0.0;
    }
  }

  void land() {
    if (_state.flightMode != FlightMode.disarmed) {
      _state = _state.copyWith(flightMode: FlightMode.landing);
    }
  }

  void startMission(List<Waypoint> waypoints) {
    if (waypoints.isEmpty) return;
    if (_state.flightMode == FlightMode.disarmed) {
      takeoff();
    }
    _waypoints = List.from(waypoints);
    _currentWaypointIndex = 0;
    _hoverTimer = 0.0;
    _state = _state.copyWith(flightMode: FlightMode.autoMission);
  }

  void triggerRTL() {
    if (_state.flightMode != FlightMode.disarmed) {
      _state = _state.copyWith(flightMode: FlightMode.rtl);
    }
  }

  void setWindSpeed(double kmh) {
    final direction = _random.nextDouble() * 360.0;
    _state = _state.copyWith(
      windSpeedKmh: kmh.clamp(0.0, 50.0),
      windDirectionDeg: direction,
    );
  }

  void toggleGps() {
    _state = _state.copyWith(gpsLocked: !_state.gpsLocked);
  }

  void selectProfile(DroneProfile profile) {
    _state = _state.copyWith(activeProfile: profile);
  }

  void resetBattery() {
    _state = _state.copyWith(batteryPercent: 100.0, voltage: 12.6);
  }

  void overrideToManual() {
    if (_state.flightMode == FlightMode.autoMission) {
      _state = _state.copyWith(flightMode: FlightMode.manual);
    }
  }
}
