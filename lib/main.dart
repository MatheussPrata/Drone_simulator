import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/widgets/fpv_camera_view.dart';
import 'package:drone_simulator/widgets/fpv_osd_overlay.dart';
import 'package:drone_simulator/widgets/gimbal_slider.dart';
import 'package:drone_simulator/widgets/mini_map_widget.dart';
import 'package:drone_simulator/widgets/telemetry_hud.dart';
import 'package:drone_simulator/widgets/virtual_joystick.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const DroneSimulatorApp());
}

class DroneSimulatorApp extends StatelessWidget {
  const DroneSimulatorApp({super.key});

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
      home: const FlightSimulatorScreen(),
    );
  }
}

class FlightSimulatorScreen extends StatefulWidget {
  const FlightSimulatorScreen({super.key});

  @override
  State<FlightSimulatorScreen> createState() => _FlightSimulatorScreenState();
}

class _FlightSimulatorScreenState extends State<FlightSimulatorScreen> {
  late final SimulatorController _controller;
  bool _isFpvMain = true; // Visão FPV como tela cheia principal por padrão

  @override
  void initState() {
    super.initState();
    _controller = SimulatorController()..start();
  }

  @override
  void dispose() {
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
          // ── Camada 1: Visão Principal (FPV 3D com OSD estilo DJI ou Mapa Real) ──
          Positioned.fill(
            child: _isFpvMain
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      FpvCameraView(
                        controller: _controller,
                        showOsd: false,
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

          // ── Camada 2: Janela PiP (Picture-in-Picture) alternável entre Mapa e Câmera FPV ──
          Positioned(
            left: 24,
            bottom: 155, // Posicionada de forma limpa acima do joystick esquerdo
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isFpvMain = !_isFpvMain;
                });
              },
              child: Container(
                width: 150,
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.cyanAccent.withOpacity(0.8),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.6),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8.5),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _isFpvMain
                            ? MiniMapWidget(
                                controller: _controller,
                                followDrone: true,
                              )
                            : FpvCameraView(
                                controller: _controller,
                                showOsd: false,
                              ),
                      ),
                      // Badge indicativo de toque para alternar visão
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.cyanAccent.withOpacity(0.4), width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.swap_horiz,
                                size: 12,
                                color: Colors.cyanAccent,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                _isFpvMain ? 'MAPA' : 'FPV',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
            ),
          ),

          // ── Camada 3: Joystick Esquerdo Modo 2 (Throttle / Yaw) ──
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

          // ── Camada 4: Joystick Direito Modo 2 (Pitch / Roll) ──
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
