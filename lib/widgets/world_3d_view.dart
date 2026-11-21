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
    final cameraModeStr = s.cameraMode == CameraViewMode.thirdPerson ? 'thirdPerson' : 'fpv';
    final isFlying = s.status == SimulatorStatus.flying ||
        s.status == SimulatorStatus.takingOff ||
        s.status == SimulatorStatus.rth ||
        s.status == SimulatorStatus.hovering;

    final motors = s.motorNormalizedRpm
        .map((m) => m.clamp(0.0, 1.0).toStringAsFixed(3))
        .join(',');

    return '{"x":${s.x.toStringAsFixed(2)},"y":${s.y.toStringAsFixed(2)},"z":${s.z.toStringAsFixed(2)},'
        '"yaw":${s.yaw.toStringAsFixed(2)},"pitch":${s.visualPitch.toStringAsFixed(2)},"roll":${s.visualRoll.toStringAsFixed(2)},'
        '"visualPitch":${s.visualPitch.toStringAsFixed(2)},"visualRoll":${s.visualRoll.toStringAsFixed(2)},'
        '"pitchRad":${s.pitchRad.toStringAsFixed(4)},"rollRad":${s.rollRad.toStringAsFixed(4)},'
        '"yawRad":${s.yawRad.toStringAsFixed(4)},"motors":[$motors],'
        '"gimbalPitch":${s.gimbalPitch.toStringAsFixed(2)},"cameraMode":"$cameraModeStr",'
        '"flying":$isFlying,"battery":${s.battery.toStringAsFixed(1)},"isArmed":${s.isArmed},'
        '"impactShake":${s.impactShake.toStringAsFixed(3)},'
        '"isCrashed":${s.isCrashed},'
        '"crashImpactSpeedKmh":${s.crashImpactSpeedKmh.toStringAsFixed(1)},'
        '"status":"${s.status.name}"}';
  }

  void _syncStateTo3d() {
    if (!_isPageLoaded || _isSending || _webViewController == null) return;

    _pushObstacleLayout();

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
