import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drone_simulator/models/drone_profile.dart';
import 'package:drone_simulator/models/flight_map.dart';
import 'package:drone_simulator/services/records_repository.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/ui/screens/home_menu_screen.dart';
import 'package:drone_simulator/widgets/fpv_osd_overlay.dart';
import 'package:drone_simulator/widgets/game_hud_overlay.dart';
import 'package:drone_simulator/widgets/gimbal_slider.dart';
import 'package:drone_simulator/widgets/mini_map_widget.dart';
import 'package:drone_simulator/widgets/minimap_pip.dart';
import 'package:drone_simulator/widgets/telemetry_hud.dart';
import 'package:drone_simulator/widgets/virtual_joystick.dart';
import 'package:drone_simulator/widgets/world_3d_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const DroneSimulatorApp(showHomeOnStart: true));
}

class DroneSimulatorApp extends StatelessWidget {
  final bool showHomeOnStart;
  final RecordsRepository? recordsRepository;

  const DroneSimulatorApp({
    super.key,
    this.showHomeOnStart = false,
    this.recordsRepository,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drone Simulator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF101418),
        colorScheme: const ColorScheme.dark(
          primary: Colors.cyanAccent,
          secondary: Colors.orangeAccent,
          surface: Color(0xFF1E2630),
        ),
      ),
      home: showHomeOnStart
          ? HomeMenuScreen(recordsRepository: recordsRepository)
          : const FlightSimulatorScreen(),
    );
  }
}

class FlightSimulatorScreen extends StatefulWidget {
  final SimulatorMode initialMode;
  final FlightMap? initialMap;
  final DroneProfile? initialProfile;
  final FlightControlMode initialFlightMode;
  final TimeOfDayPreset initialTimeOfDay;
  final AcroSettings? initialAcroSettings;
  final bool initialAudioEnabled;
  final bool initialHapticsEnabled;
  final bool initialGhostEnabled;
  final RecordsRepository? recordsRepository;

  const FlightSimulatorScreen({
    super.key,
    this.initialMode = SimulatorMode.freeFlight,
    this.initialMap,
    this.initialProfile,
    this.initialFlightMode = FlightControlMode.stabilized,
    this.initialTimeOfDay = TimeOfDayPreset.day,
    this.initialAcroSettings,
    this.initialAudioEnabled = true,
    this.initialHapticsEnabled = true,
    this.initialGhostEnabled = true,
    this.recordsRepository,
  });

  @override
  State<FlightSimulatorScreen> createState() => _FlightSimulatorScreenState();
}

class _FlightSimulatorScreenState extends State<FlightSimulatorScreen> {
  late final SimulatorController _controller;
  bool _lastIsMapPrimaryView = false;

  bool get _isFpvMain => !_controller.isMapPrimaryView;

  @override
  void initState() {
    super.initState();
    _controller = SimulatorController(records: widget.recordsRepository);
    if (widget.initialAcroSettings != null) {
      _controller.setAcroSettings(widget.initialAcroSettings!, persist: false);
    }
    _controller.setAudioEnabled(widget.initialAudioEnabled);
    _controller.setHapticsEnabled(widget.initialHapticsEnabled);
    _controller.setGhostEnabled(widget.initialGhostEnabled);

    if (widget.initialMap != null ||
        widget.initialProfile != null ||
        widget.initialMode != SimulatorMode.freeFlight ||
        widget.initialFlightMode != FlightControlMode.stabilized ||
        widget.initialTimeOfDay != TimeOfDayPreset.day) {
      _controller.configureSession(
        mode: widget.initialMode,
        map: widget.initialMap ?? FlightMap.dronePark,
        profile: widget.initialProfile ?? DroneProfile.mini249g,
        flightMode: widget.initialFlightMode,
        timeOfDay: widget.initialTimeOfDay,
      );
    }
    _lastIsMapPrimaryView = _controller.isMapPrimaryView;
    _controller.start();
    _controller.addListener(_onControllerTick);
  }

  void _openHomeMenu() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => HomeMenuScreen(recordsRepository: _controller.records),
        ),
      );
    }
  }

  void _onControllerTick() {
    if (!mounted) return;
    final currentMapPrimary = _controller.isMapPrimaryView;
    if (currentMapPrimary != _lastIsMapPrimaryView) {
      _lastIsMapPrimaryView = currentMapPrimary;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerTick);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camada 1: Visão Principal (Cenário 3D Three.js com OSD estilo DJI ou Mapa Real) ──
          Positioned.fill(
            child: _isFpvMain
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      World3dView(
                        controller: _controller,
                      ),
                      FpvOsdOverlay(
                        controller: _controller,
                      ),
                    ],
                  )
                : MiniMapWidget(
                    controller: _controller,
                    followDrone: true,
                  ),
          ),

          // ── Camada 2: Card PiP Arredondado no Canto Inferior Esquerdo (Alternável entre Mini-Mapa e FPV) ──
          Positioned(
            left: 20,
            bottom: 155, // Posicionada de forma limpa acima do joystick esquerdo
            child: MiniMapPip(
              controller: _controller,
              onToggle: () => _controller.togglePrimaryView(),
            ),
          ),

          // ── Camada 3: Slider Vertical de Inclinação do Gimbal da Câmera (0° a -90°) ──
          Positioned(
            right: 20,
            bottom: 155, // Posicionado acima do joystick direito
            child: GimbalSlider(
              controller: _controller,
            ),
          ),

          // ── Camada 4: Barra Superior de Telemetria e Alertas (Topo) ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: TelemetryHud(
              controller: _controller,
              actionsPlacement: HudActionsPlacement.top,
              onOpenHomeMenu: _openHomeMenu,
            ),
          ),

          // ── Camada 4.5: HUD do Modo Jogo + Cards de Queda/Vitória ──
          Positioned.fill(
            child: GameHudOverlay(
              controller: _controller,
              onOpenHomeMenu: _openHomeMenu,
            ),
          ),

          // ── Camada 5: Joystick Esquerdo Modo 2 (Throttle / Yaw) - Translúcido ──
          Positioned(
            left: 28,
            bottom: 24,
            child: SafeArea(
              top: false,
              right: false,
              child: VirtualJoystick(
                label: 'THROTTLE / YAW',
                radius: 56,
                stickRadius: 20,
                opacity: 0.70, // Translúcido sobre o vídeo da câmera sem obstruir
                onPositionChanged: (offset) {
                  // Modo 2: para cima (-dy) = subir / aumentar altitude
                  _controller.setManualInput(
                    throttle: -offset.dy,
                    yaw: offset.dx,
                  );
                },
              ),
            ),
          ),

          // ── Camada 6: Joystick Direito Modo 2 (Pitch / Roll) - Translúcido ──
          Positioned(
            right: 28,
            bottom: 24,
            child: SafeArea(
              top: false,
              left: false,
              child: VirtualJoystick(
                label: 'PITCH / ROLL',
                radius: 56,
                stickRadius: 20,
                opacity: 0.70, // Translúcido sobre o vídeo da câmera sem obstruir
                onPositionChanged: (offset) {
                  // Modo 2: para frente (-dy) = avançar; para direita (+dx) = rolar direita
                  _controller.setManualInput(
                    pitch: -offset.dy,
                    roll: offset.dx,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
