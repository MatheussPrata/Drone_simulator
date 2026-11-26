import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/simulation/world_generator.dart';

/// Widget de renderização do cenário 3D em Three.js local via WebView.
///
/// Substitui o fundo 2D antigo, executando a simulação 3D em WebGL offline.
/// É estritamente envolvido em [IgnorePointer] para garantir que toques e gestos
/// não sejam interceptados pela página web, fluindo diretamente para os joysticks
/// e controles virtuais do Flutter.
class World3dView extends StatefulWidget {
  final SimulatorController controller;
  final WebViewController? customWebViewController;

  const World3dView({
    super.key,
    required this.controller,
    this.customWebViewController,
  });

  @override
  State<World3dView> createState() => _World3dViewState();
}

class _World3dViewState extends State<World3dView> {
  WebViewController? _webViewController;
  bool _isPageLoaded = false;
  bool _isSending = false;
  String? _loadedScenarioId;
  String? _lastRaceMapId;
  String? _lastRaceVariantKey;
  int _lastRaceGateIndex = -1;
  String? _lastRaceMode;
  bool _racePushed = false;
  String? _lastMissionId;
  int _lastMissionIndex = -1;
  bool _missionPushed = false;
  DroneTuning? _lastDroneTuning;
  TimeOfDayPreset? _lastLightingPreset;

  @override
  void initState() {
    super.initState();
    _initWebViewController();
    widget.controller.addListener(_onControllerTick);
  }

  void _initWebViewController() {
    if (widget.customWebViewController != null) {
      _webViewController = widget.customWebViewController;
      _isPageLoaded = true;
      _loadedScenarioId = widget.controller.activeMap.id;
      return;
    }

    // Em ambiente de testes sem plataforma nativa de WebView registrada,
    // não tenta instanciar para evitar asserções do Flutter Test.
    if (WebViewPlatform.instance == null) {
      return;
    }

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B1118))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isPageLoaded = true;
              });
              _pushObstacleLayout();
              _pushLightingPreset();
              _pushDroneAppearance();
              _syncStateTo3d();
            }
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('Erro no World3dView: ${error.description}');
          },
        ),
      )
      ..loadFlutterAsset('assets/scene3d/index.html');

    _webViewController = controller;
  }

  @override
  void didUpdateWidget(covariant World3dView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerTick);
      widget.controller.addListener(_onControllerTick);
    }
  }

  void _onControllerTick() {
    _syncStateTo3d();
  }

  /// Envia o preset de iluminação (day, sunset, night) quando mudar.
  void _pushLightingPreset() {
    if (_webViewController == null) return;
    final preset = widget.controller.timeOfDay;
    if (_lastLightingPreset == preset) return;
    _lastLightingPreset = preset;

    _webViewController!
        .runJavaScript("window.setLightingPreset('${preset.name}');")
        .catchError((Object error) {
      debugPrint('Erro ao enviar iluminação ao WebView: $error');
    });
  }

  /// Drena os eventos sonoros pendentes e dispara no Web Audio API.
  void _pushSoundEvents() {
    if (_webViewController == null) return;
    final events = widget.controller.feedback.drainPendingSounds();
    for (final ev in events) {
      final val = ev.value.toStringAsFixed(2);
      _webViewController!
          .runJavaScript("window.triggerSoundEffect('${ev.kind.name}', $val);")
          .catchError((_) {});
    }
  }

  /// Envia aparência da garagem (LEDs, braços e FOV base) quando mudar.
  void _pushDroneAppearance() {
    if (_webViewController == null) return;
    final tuning = widget.controller.droneTuning;
    if (_lastDroneTuning == tuning) return;
    _lastDroneTuning = tuning;

    final payload =
        '{"ledColor":"${tuning.ledColorHex}","armColor":"${tuning.armColorHex}",'
        '"baseFov":${tuning.cameraFovDeg.toStringAsFixed(1)}}';
    _webViewController!
        .runJavaScript("window.setDroneAppearance('$payload');")
        .catchError((Object error) {
      debugPrint('Erro ao enviar aparência do drone ao WebView: $error');
    });
  }

  /// Envia o circuito de portais e o índice ativo para a cena 3D.
  void _pushRaceState() {
    final controller = widget.controller;
    final course = controller.raceCourse;
    final modeName = controller.simulatorMode.name;

    if (!controller.isRaceMode || course == null) {
      if (_racePushed) {
        _racePushed = false;
        _lastRaceMapId = null;
        _lastRaceVariantKey = null;
        _lastRaceGateIndex = -1;
        _lastRaceMode = null;
        _webViewController!
            .runJavaScript("window.updateRaceState('{\"mode\":\"freeFlight\"}');")
            .catchError((Object error) {
          debugPrint('Erro ao limpar circuito no WebView: $error');
        });
      }
      return;
    }

    final index = controller.raceGateIndex;
    final variantKey = course.variantKey;
    if (_racePushed &&
        _lastRaceMapId == course.mapId &&
        _lastRaceVariantKey == variantKey &&
        _lastRaceGateIndex == index &&
        _lastRaceMode == modeName) {
      return;
    }

    _racePushed = true;
    _lastRaceMapId = course.mapId;
    _lastRaceVariantKey = variantKey;
    _lastRaceGateIndex = index;
    _lastRaceMode = modeName;

    final courseJson = course.toJsonString();
    final body = '${courseJson.substring(0, courseJson.length - 1)},'
        '"mode":"$modeName","activeIndex":$index}';

    _webViewController!
        .runJavaScript("window.updateRaceState('$body');")
        .catchError((Object error) {
      debugPrint('Erro ao enviar circuito ao WebView: $error');
    });
  }

  /// Envia checkpoints da missão ativa para renderização 3D.
  void _pushMissionState() {
    if (_webViewController == null) return;
    final controller = widget.controller;
    final mission = controller.activeMission;
    final manager = controller.missionManager;

    if (!controller.isMissionMode || mission == null || manager == null) {
      if (_missionPushed) {
        _missionPushed = false;
        _lastMissionId = null;
        _lastMissionIndex = -1;
        _webViewController!
            .runJavaScript("window.updateMissionState('{\"active\":false}');")
            .catchError((Object error) {
          debugPrint('Erro ao limpar missão no WebView: $error');
        });
      }
      return;
    }

    final activeIndex = manager.currentCheckpointIndex;
    if (_missionPushed &&
        _lastMissionId == mission.id &&
        _lastMissionIndex == activeIndex) {
      return;
    }

    _missionPushed = true;
    _lastMissionId = mission.id;
    _lastMissionIndex = activeIndex;
    final json = mission
        .toJsonString(activeIndex: activeIndex, active: true)
        .replaceAll("'", "\\'");
    _webViewController!
        .runJavaScript("window.updateMissionState('$json');")
        .catchError((Object error) {
      debugPrint('Erro ao enviar missão ao WebView: $error');
    });
  }

  /// Envia o cenário (tema do terreno + planta de obstáculos) do mapa ativo
  /// sempre que ele muda, mantendo 3D e colisão perfeitamente alinhados.
  void _pushObstacleLayout() {
    if (_webViewController == null) return;
    final map = widget.controller.activeMap;
    if (_loadedScenarioId == map.id) return;
    _loadedScenarioId = map.id;

    final json = WorldGenerator.obstaclesJson(map).replaceAll("'", "\\'");
    _webViewController!
        .runJavaScript("window.loadMapScenario('$json');")
        .catchError((Object error) {
      debugPrint('Erro ao enviar obstáculos ao WebView: $error');
    });
  }

  String _buildStatePayload() {
    final s = widget.controller;
    final cameraModeStr =
        s.cameraMode == CameraViewMode.thirdPerson ? 'thirdPerson' : 'fpv';
    final isFlying = s.status == SimulatorStatus.flying ||
        s.status == SimulatorStatus.takingOff ||
        s.status == SimulatorStatus.rth ||
        s.status == SimulatorStatus.hovering ||
        (s.isReplaying && !s.isReplayPaused);

    final motors = s.motorNormalizedRpm
        .map((m) => m.clamp(0.0, 1.0).toStringAsFixed(3))
        .join(',');

    final q = s.orientationQuat;
    final ghost = s.currentGhostFrame;
    final ghostJson = ghost == null
        ? '{"active":false}'
        : '{"active":true,"x":${ghost.x.toStringAsFixed(2)},'
            '"y":${ghost.y.toStringAsFixed(2)},'
            '"z":${ghost.z.toStringAsFixed(2)},'
            '"pitchRad":${ghost.pitchRad.toStringAsFixed(4)},'
            '"rollRad":${ghost.rollRad.toStringAsFixed(4)},'
            '"yawRad":${ghost.yawRad.toStringAsFixed(4)}}';

    final audioOn = s.audioEnabled && (!s.isReplaying || !s.isReplayPaused);
    final armedForRender = s.isArmed || s.isReplaying;

    return '{"x":${s.x.toStringAsFixed(2)},"y":${s.y.toStringAsFixed(2)},"z":${s.z.toStringAsFixed(2)},'
        '"groundHeightM":${s.currentGroundHeightM.toStringAsFixed(2)},'
        '"yaw":${s.yaw.toStringAsFixed(2)},"pitch":${s.visualPitch.toStringAsFixed(2)},"roll":${s.visualRoll.toStringAsFixed(2)},'
        '"visualPitch":${s.visualPitch.toStringAsFixed(2)},"visualRoll":${s.visualRoll.toStringAsFixed(2)},'
        '"pitchRad":${s.pitchRad.toStringAsFixed(4)},"rollRad":${s.rollRad.toStringAsFixed(4)},'
        '"yawRad":${s.yawRad.toStringAsFixed(4)},'
        '"qx":${q.x.toStringAsFixed(5)},"qy":${q.y.toStringAsFixed(5)},'
        '"qz":${q.z.toStringAsFixed(5)},"qw":${q.w.toStringAsFixed(5)},'
        '"motors":[$motors],'
        '"gimbalPitch":${s.gimbalPitch.toStringAsFixed(2)},"cameraMode":"$cameraModeStr",'
        '"flightMode":"${s.flightMode.name}",'
        '"fpvUptiltDeg":${s.fpvUptiltDeg.toStringAsFixed(1)},'
        '"baseFovDeg":${s.droneTuning.cameraFovDeg.toStringAsFixed(1)},'
        '"audioEnabled":$audioOn,'
        '"speedKmh":${s.speedKmh.toStringAsFixed(1)},'
        '"ghost":$ghostJson,'
        '"flying":$isFlying,"battery":${s.battery.toStringAsFixed(1)},"isArmed":$armedForRender,'
        '"impactShake":${s.impactShake.toStringAsFixed(3)},'
        '"isCrashed":${s.isCrashed},'
        '"crashImpactSpeedKmh":${s.crashImpactSpeedKmh.toStringAsFixed(1)},'
        '"status":"${s.status.name}"}';
  }

  void _syncStateTo3d() {
    if (!_isPageLoaded || _webViewController == null) return;

    _pushObstacleLayout();
    _pushLightingPreset();
    _pushDroneAppearance();
    _pushRaceState();
    _pushMissionState();
    _pushSoundEvents();

    if (_isSending) return;
    _isSending = true;
    final payload = _buildStatePayload();
    _webViewController!
        .runJavaScript('window.updateDroneState($payload);')
        .whenComplete(() {
      _isSending = false;
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerTick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_webViewController == null) {
      return Container(
        key: const Key('world_3d_placeholder'),
        color: const Color(0xFF0B1118),
      );
    }

    return IgnorePointer(
      ignoring: true,
      child: WebViewWidget(
        key: const Key('world_3d_webview'),
        controller: _webViewController!,
      ),
    );
  }
}
