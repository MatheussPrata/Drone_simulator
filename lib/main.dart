import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/widgets/map_canvas.dart';
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
          // ── Camada 1: Mapa Tático 2D Nativo (Fundo) ──
          Positioned.fill(
            child: MapCanvas(
              controller: _controller,
              followDrone: true,
            ),
          ),

          // ── Camada 2: Barra Superior de Telemetria e Alertas (Topo) ──
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
