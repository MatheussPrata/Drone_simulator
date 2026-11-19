import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:drone_simulator/simulation/flight_physics.dart';

/// Status operacional do simulador de voo
enum SimulatorStatus {
  disarmed,
  takingOff,
  hovering,
  flying,
  rth,
  landing,
  landed,
}

/// Controller central de simulação desacoplado da interface gráfica.
///
/// Gerencia o loop temporal a 60 FPS (dt = 0.016s), comandos automáticos
/// de voo (Takeoff -> Hover, RTH em direção a (0,0), Pouso e Failsafe de Bateria),
/// integrando-se diretamente à engine física [FlightPhysics].
class SimulatorController extends ChangeNotifier {
  static const double fixedDt = 0.016; // 60 FPS (~16.6ms)
  static const double targetTakeoffAltitude = 10.0; // z = 10m
  static const double climbSpeed = 2.5; // m/s subida automática
  static const double descentSpeed = 2.0; // m/s descida automática
  static const double rthSpeed = 8.0; // m/s velocidade fixa de retorno a (0,0)

  final FlightPhysics physics;
  Timer? _timer;

  SimulatorStatus _status = SimulatorStatus.landed;
  double _x = 0.0;
  double _y = 0.0;
  double _z = 0.0;
  double _battery = 100.0;
  bool _isArmed = false;

  SimulatorController({FlightPhysics? physics})
      : physics = physics ?? FlightPhysics();

  SimulatorStatus get status => _status;
  double get x => _x;
  double get y => _y;
  double get z => _z;
  double get battery => _battery;
  bool get isArmed => _isArmed;
  bool get isLanded => _status == SimulatorStatus.landed;
  bool get isHovering => _status == SimulatorStatus.hovering;
  bool get isTakingOff => _status == SimulatorStatus.takingOff;
  bool get isRTH => _status == SimulatorStatus.rth;
  bool get isLanding => _status == SimulatorStatus.landing;
  bool get isRunning => _timer != null;

  /// Inicia o loop de atualização a 60 FPS
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      update(fixedDt);
    });
  }

  /// Pausa o loop de tempo
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

  /// Sobe automaticamente até z = 10m e estabiliza (hovering)
  void armAndTakeoff() {
    _isArmed = true;
    _status = SimulatorStatus.takingOff;
    physics.takeoff();
    notifyListeners();
  }

  /// Desce até z = 0 e muda status para landed
  void land() {
    _status = SimulatorStatus.landing;
    physics.land();
    notifyListeners();
  }

  /// Move (x, y) em direção a (0, 0) a uma velocidade fixa e pousa ao chegar
  void triggerRTH() {
    if (_status == SimulatorStatus.landed || _status == SimulatorStatus.landing) {
      return;
    }
    _status = SimulatorStatus.rth;
    physics.triggerRTL();
    notifyListeners();
  }

  /// Reseta o simulador e a física para o estado inicial
  void reset() {
    _status = SimulatorStatus.landed;
    _x = 0.0;
    _y = 0.0;
    _z = 0.0;
    _battery = 100.0;
    _isArmed = false;
    physics.resetBattery();
    physics.selectMap(physics.activeMap);
    notifyListeners();
  }

  /// Permite definir coordenadas (x, y, [z]) para posicionamento ou simulação
  void setPosition(double newX, double newY, [double? newZ]) {
    _x = newX;
    _y = newY;
    if (newZ != null) _z = newZ;
    notifyListeners();
  }

  /// Define o nível de bateria percentual [0-100]
  void setBattery(double percent) {
    _battery = percent.clamp(0.0, 100.0);
    _checkBatteryFailSafe();
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

  /// Gerencia o loop de atualização chamando FlightPhysics.update com dt fixo (0.016s)
  void update([double dt = fixedDt]) {
    // 1. Verificação contínua de bateria e fail-safe
    if (_isArmed && _status != SimulatorStatus.landed) {
      _checkBatteryFailSafe();
    }

    // 2. Máquina de estados dos comandos automáticos
    switch (_status) {
      case SimulatorStatus.takingOff:
        _z += climbSpeed * dt;
        if (_z >= targetTakeoffAltitude) {
          _z = targetTakeoffAltitude;
          _status = SimulatorStatus.hovering; // Estabiliza em 10m
        }
        break;

      case SimulatorStatus.hovering:
      case SimulatorStatus.flying:
        // Mantém altitude estável
        break;

      case SimulatorStatus.rth:
        // Move (x, y) em direção a (0, 0) a velocidade fixa (8.0 m/s)
        final double dist = sqrt(_x * _x + _y * _y);
        final double step = rthSpeed * dt;

        if (dist <= step || dist < 0.2) {
          _x = 0.0;
          _y = 0.0;
          // Ao chegar em (0, 0), inicia pouso automaticamente
          land();
        } else {
          final double ux = -_x / dist;
          final double uy = -_y / dist;
          _x += ux * step;
          _y += uy * step;
        }
        break;

      case SimulatorStatus.landing:
        // Desce até z = 0 e muda status para landed
        _z -= descentSpeed * dt;
        if (_z <= 0.0) {
          _z = 0.0;
          _status = SimulatorStatus.landed;
          _isArmed = false;
        }
        break;

      case SimulatorStatus.disarmed:
      case SimulatorStatus.landed:
        _z = 0.0;
        break;
    }

    // 3. Atualiza o motor de física com dt fixo
    physics.update(dt);

    // 4. Notifica observers/widgets
    notifyListeners();
  }
}
