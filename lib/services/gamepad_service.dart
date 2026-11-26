import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';

/// Ponte de entrada para controles físicos (Gamepad/HID Android via MethodChannel)
/// e atalhos de teclado em desktop/emulador.
class GamepadInputBridge {
  static const MethodChannel channel =
      MethodChannel('com.dronesim.drone_simulator/gamepad');
  static const double axisDeadzone = 0.08;

  static final Set<LogicalKeyboardKey> _axisKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.keyW,
    LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyD,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  };

  static final Map<LogicalKeyboardKey, String> _actionKeyMap =
      <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.space: 'arm_takeoff',
    LogicalKeyboardKey.keyL: 'land',
    LogicalKeyboardKey.keyH: 'rth',
    LogicalKeyboardKey.keyM: 'cycle_flight_mode',
    LogicalKeyboardKey.keyC: 'toggle_camera',
    LogicalKeyboardKey.keyR: 'reset',
  };

  final SimulatorController controller;

  bool isGamepadConnected = false;
  String? connectedDeviceName;
  final Set<LogicalKeyboardKey> _pressedKeys = <LogicalKeyboardKey>{};
  bool _attached = false;

  GamepadInputBridge({required this.controller});

  /// Remove ruído próximo ao centro e reescala suavemente o restante até 1.0.
  static double applyDeadzone(double value, [double deadzone = axisDeadzone]) {
    final clamped = value.clamp(-1.0, 1.0);
    final absVal = clamped.abs();
    if (absVal < deadzone) return 0.0;
    final scaled = (absVal - deadzone) / (1.0 - deadzone);
    return clamped.sign * scaled.clamp(0.0, 1.0);
  }

  void attach() {
    if (_attached) return;
    _attached = true;
    try {
      channel.setMethodCallHandler(_onMethodCall);
    } catch (_) {
      // Testes unitários puros sem ServicesBinding inicializado.
    }
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    _pressedKeys.clear();
    try {
      channel.setMethodCallHandler(null);
    } catch (_) {
      // Sem binding ativo.
    }
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    final args = call.arguments;
    if (args is! Map) return null;

    if (call.method == 'axes') {
      handleAxisEvent(
        leftX: (args['leftX'] as num?)?.toDouble() ?? 0.0,
        leftY: (args['leftY'] as num?)?.toDouble() ?? 0.0,
        rightX: (args['rightX'] as num?)?.toDouble() ?? 0.0,
        rightY: (args['rightY'] as num?)?.toDouble() ?? 0.0,
        deviceName: args['device'] as String?,
      );
    } else if (call.method == 'button') {
      final action = args['action'];
      if (action is String) {
        handleButtonAction(action);
      }
    }
    return null;
  }

  void handleAxisEvent({
    required double leftX,
    required double leftY,
    required double rightX,
    required double rightY,
    String? deviceName,
  }) {
    isGamepadConnected = true;
    if (deviceName != null && deviceName.isNotEmpty) {
      connectedDeviceName = deviceName;
    }
    controller.setManualInput(
      throttle: -applyDeadzone(leftY),
      yaw: applyDeadzone(leftX),
      pitch: -applyDeadzone(rightY),
      roll: applyDeadzone(rightX),
    );
  }

  void handleButtonAction(String action) {
    switch (action) {
      case 'arm_takeoff':
        if (controller.isLanded) {
          controller.armAndTakeoff();
        } else if (controller.isCrashed) {
          controller.respawn();
        }
        break;
      case 'land':
        controller.land();
        break;
      case 'rth':
        controller.triggerRTH();
        break;
      case 'cycle_flight_mode':
        controller.cycleFlightMode();
        break;
      case 'toggle_camera':
        controller.toggleCameraMode();
        break;
      case 'reset':
        if (controller.isRaceMode ||
            controller.isFreestyle ||
            controller.isMissionMode) {
          controller.restartRace();
        } else {
          controller.reset();
        }
        break;
    }
  }

  KeyEventResult handleKeyEvent(KeyEvent event) {
    final key = event.logicalKey;

    if (_axisKeys.contains(key)) {
      if (event is KeyDownEvent) {
        _pressedKeys.add(key);
        _pushKeyboardAxes();
      } else if (event is KeyUpEvent) {
        _pressedKeys.remove(key);
        _pushKeyboardAxes();
      }
      return KeyEventResult.handled;
    }

    final action = _actionKeyMap[key];
    if (action != null) {
      if (event is KeyDownEvent) {
        handleButtonAction(action);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _pushKeyboardAxes() {
    double axis(LogicalKeyboardKey pos, LogicalKeyboardKey neg) {
      final p = _pressedKeys.contains(pos) ? 1.0 : 0.0;
      final n = _pressedKeys.contains(neg) ? 1.0 : 0.0;
      return p - n;
    }

    controller.setManualInput(
      throttle: axis(LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyS),
      yaw: axis(LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyA),
      pitch: axis(LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown),
      roll: axis(LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowLeft),
    );
  }
}
