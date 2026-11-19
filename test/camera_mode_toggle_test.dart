import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:drone_simulator/main.dart';
import 'package:drone_simulator/models/drone_profile.dart';
import 'package:drone_simulator/models/drone_state.dart';
import 'package:drone_simulator/models/flight_map.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/widgets/telemetry_hud.dart';

void main() {
  group('Etapa 1 - Estados de Câmera e Alternância de Tela', () {
    test('SimulatorController: estado inicial possui cameraMode = fpv e isMapPrimaryView = false', () {
      final controller = SimulatorController();

      expect(controller.cameraMode, equals(CameraViewMode.fpv));
      expect(controller.isMapPrimaryView, isFalse);

      controller.dispose();
    });

    test('SimulatorController: toggleCameraMode alterna entre fpv e thirdPerson notificando listeners', () {
      final controller = SimulatorController();
      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      // 1. Alterna para 3ª Pessoa
      controller.toggleCameraMode();
      expect(controller.cameraMode, equals(CameraViewMode.thirdPerson));
      expect(notifyCount, equals(1));

      // 2. Alterna de volta para FPV (1ª Pessoa)
      controller.toggleCameraMode();
      expect(controller.cameraMode, equals(CameraViewMode.fpv));
      expect(notifyCount, equals(2));

      // 3. setCameraMode explícito
      controller.setCameraMode(CameraViewMode.thirdPerson);
      expect(controller.cameraMode, equals(CameraViewMode.thirdPerson));
      expect(notifyCount, equals(3));

      controller.dispose();
    });

    test('SimulatorController: togglePrimaryView alterna isMapPrimaryView notificando listeners', () {
      final controller = SimulatorController();
      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      // 1. Alterna para Mapa em tela cheia
      controller.togglePrimaryView();
      expect(controller.isMapPrimaryView, isTrue);
      expect(notifyCount, equals(1));

      // 2. Alterna de volta para Câmera em tela cheia
      controller.togglePrimaryView();
      expect(controller.isMapPrimaryView, isFalse);
      expect(notifyCount, equals(2));

      // 3. setMapPrimaryView explícito
      controller.setMapPrimaryView(true);
      expect(controller.isMapPrimaryView, isTrue);
      expect(notifyCount, equals(3));

      // 4. Reset restaura cameraMode = fpv e isMapPrimaryView = false
      controller.reset();
      expect(controller.cameraMode, equals(CameraViewMode.fpv));
      expect(controller.isMapPrimaryView, isFalse);

      controller.dispose();
    });

    test('DroneState: preserva e atualiza cameraMode via copyWith', () {
      final state = DroneState(
        position: const LatLng(0, 0),
        homePosition: const LatLng(0, 0),
        activeProfile: DroneProfile.mini249g,
        activeMap: FlightMap.dronePark,
      );

      expect(state.cameraMode, equals(CameraViewMode.fpv));

      final thirdPersonState = state.copyWith(cameraMode: CameraViewMode.thirdPerson);
      expect(thirdPersonState.cameraMode, equals(CameraViewMode.thirdPerson));
    });

    testWidgets('TelemetryHud: botão na barra superior alterna rótulo e ícone entre 1ª Pessoa (FPV) e 3ª Pessoa', (tester) async {
      CameraViewMode currentMode = CameraViewMode.fpv;
      int toggleCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return TelemetryHud(
                  altitude: 10.0,
                  speed: 15.0,
                  distanceToHome: 50.0,
                  battery: 90.0,
                  cameraMode: currentMode,
                  onToggleCameraMode: () {
                    setState(() {
                      toggleCalls++;
                      currentMode = currentMode == CameraViewMode.fpv
                          ? CameraViewMode.thirdPerson
                          : CameraViewMode.fpv;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Estado 1: FPV (1ª Pessoa)
      expect(find.byKey(const Key('btn_camera_mode')), findsOneWidget);
      expect(find.text('1ª Pessoa (FPV)'), findsOneWidget);
      expect(find.byIcon(Icons.videocam), findsOneWidget);

      // Toca no botão
      await tester.tap(find.byKey(const Key('btn_camera_mode')));
      await tester.pump();

      // Estado 2: 3ª Pessoa
      expect(toggleCalls, equals(1));
      expect(find.text('3ª Pessoa'), findsOneWidget);
      expect(find.byIcon(Icons.accessibility_new), findsOneWidget);
      expect(find.text('1ª Pessoa (FPV)'), findsNothing);

      // Toca novamente
      await tester.tap(find.byKey(const Key('btn_camera_mode')));
      await tester.pump();

      // Estado 3: Volta para 1ª Pessoa (FPV)
      expect(toggleCalls, equals(2));
      expect(find.text('1ª Pessoa (FPV)'), findsOneWidget);
      expect(find.byIcon(Icons.videocam), findsOneWidget);
    });

    testWidgets('DroneSimulatorApp: integra botão de alternância de câmera com o controller', (tester) async {
      await tester.pumpWidget(const DroneSimulatorApp());
      await tester.pump();

      // Inicializa em 1ª Pessoa (FPV)
      expect(find.byKey(const Key('btn_camera_mode')), findsOneWidget);
      expect(find.text('1ª Pessoa (FPV)'), findsOneWidget);

      // Clica para alternar
      await tester.tap(find.byKey(const Key('btn_camera_mode')));
      await tester.pump();

      // Agora exibe 3ª Pessoa
      expect(find.text('3ª Pessoa'), findsOneWidget);

      // Clica para voltar
      await tester.tap(find.byKey(const Key('btn_camera_mode')));
      await tester.pump();

      expect(find.text('1ª Pessoa (FPV)'), findsOneWidget);
    });
  });
}
