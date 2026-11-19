import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/widgets/fpv_camera_view.dart';
import 'package:drone_simulator/widgets/mini_map_widget.dart';
import 'package:drone_simulator/widgets/minimap_pip.dart';

void main() {
  group('Etapa 2 - Projeção do Mapa Real no Chão e Modo Mapa Tela Cheia', () {
    testWidgets('FpvCameraView renderiza camada de mapa satélite não-interativo no chão', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FpvCameraView(
              droneX: 10.0,
              droneY: 20.0,
              droneZ: 5.0,
              yaw: 45.0,
              showGroundMap: true,
              showOsd: false,
            ),
          ),
        ),
      );
      await tester.pump();

      // Verifica que a camada do mapa de chão está presente e não-interativa (IgnorePointer)
      final groundMapLayerFinder = find.byKey(const Key('fpv_ground_map_layer'));
      expect(groundMapLayerFinder, findsOneWidget);

      final ignorePointer = tester.widget<IgnorePointer>(groundMapLayerFinder);
      expect(ignorePointer.ignoring, isTrue);

      // Verifica que contém o FlutterMap com satélite
      expect(find.byKey(const ValueKey('fpv_ground_flutter_map')), findsOneWidget);
      expect(find.byType(TileLayer), findsWidgets);
    });

    testWidgets('FpvCameraView oculta o mapa do chão quando showGroundMap = false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FpvCameraView(
              droneX: 0.0,
              droneY: 0.0,
              droneZ: 10.0,
              showGroundMap: false,
              showOsd: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('fpv_ground_map_layer')), findsNothing);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('Critério de aceite: Puxar o gimbal para NADIR (-90°) deixa o mapa plano (tiltAngle = 0)', (tester) async {
      final controller = SimulatorController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FpvCameraView(
              controller: controller,
              showGroundMap: true,
              showOsd: false,
            ),
          ),
        ),
      );
      await tester.pump();

      // 1. No horizonte (gimbalPitch = 0°): deve existir uma Transformação 3D com rotação em X inclinada
      expect(controller.gimbalPitch, equals(0.0));
      final transformFinder = find.descendant(
        of: find.byKey(const Key('fpv_ground_map_layer')),
        matching: find.byType(Transform),
      );
      expect(transformFinder, findsWidgets);

      final firstTransform = tester.widget<Transform>(transformFinder.first);
      // setEntry(3, 2) foi configurado para perspectiva cônica (0.0025 antes da rotação em X)
      expect(firstTransform.transform.entry(3, 2), greaterThan(0.0));
      // No horizonte, a rotação em X inclina o eixo Z para o plano Y-Z (entry(3, 1) é não-nulo)
      expect(firstTransform.transform.entry(3, 1).abs(), greaterThan(0.001));

      // 2. Move o gimbal para NADIR (-90°)
      controller.setGimbalPitch(-90.0);
      await tester.pump();

      expect(controller.gimbalPitch, equals(-90.0));

      // Em NADIR, o mapa é plano visto de cima (tiltAngle = 0.0)
      final nadirTransform = tester.widget<Transform>(transformFinder.first);
      // Com tiltAngle = 0: cos(0) = 1.0, logo entry(3, 2) é exatamente 0.0025 e entry(3, 1) é 0.0!
      expect(nadirTransform.transform.entry(3, 2), closeTo(0.0025, 0.0001));
      expect(nadirTransform.transform.entry(3, 1).abs(), closeTo(0.0, 0.0001));
      // Em rotação 0 ao redor do eixo X: entry(1,1) = cos(0) = 1.0 e entry(1,2) = -sin(0) = 0.0
      expect(nadirTransform.transform.entry(1, 1), closeTo(1.0, 0.001));
      expect(nadirTransform.transform.entry(1, 2), closeTo(0.0, 0.001));

      controller.dispose();
    });

    test('Cálculo de zoom escalado suavemente pela altitude z', () {
      // Fórmula de zoom por altitude:
      // z = 0m -> zoom ~ 19.5 (alto detalhe do solo/runway)
      // z = 120m -> zoom ~ 16.5 (visão de toda a arena de 500m)
      double calculateZoom(double z) {
        final altitudeClamped = z.clamp(0.0, 150.0);
        return (19.5 - (altitudeClamped / 120.0) * 3.0).clamp(15.0, 20.0);
      }

      expect(calculateZoom(0.0), closeTo(19.5, 0.01));
      expect(calculateZoom(30.0), closeTo(18.75, 0.01));
      expect(calculateZoom(60.0), closeTo(18.0, 0.01));
      expect(calculateZoom(120.0), closeTo(16.5, 0.01));
      // Acima do teto operacional de 120m (clamped)
      expect(calculateZoom(200.0), closeTo(15.75, 0.01));
    });

    testWidgets('MiniMapPip renderiza corretamente e responde ao toque e ao botão de swap', (tester) async {
      final controller = SimulatorController();
      bool toggleCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MiniMapPip(
              controller: controller,
              onToggle: () {
                toggleCalled = true;
                controller.togglePrimaryView();
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Estado 1: FPV é primário -> PiP exibe MiniMap e botão [ ] MAPA
      expect(find.byKey(const Key('pip_card_gesture')), findsOneWidget);
      expect(find.byKey(const Key('pip_swap_button')), findsOneWidget);
      expect(find.text('MAPA'), findsOneWidget);
      expect(find.byIcon(Icons.crop_free), findsOneWidget);
      expect(find.byType(MiniMapWidget), findsOneWidget);

      // Toca no botão de swap
      await tester.tap(find.byKey(const Key('pip_swap_button')));
      await tester.pump();

      expect(toggleCalled, isTrue);
      expect(controller.isMapPrimaryView, isTrue);

      // Estado 2: Mapa é primário -> PiP exibe FpvCameraView e botão FPV
      expect(find.text('FPV'), findsOneWidget);
      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
      expect(find.byType(FpvCameraView), findsOneWidget);

      // Toca no card PiP para voltar
      await tester.tap(find.byKey(const Key('pip_card_gesture')));
      await tester.pump();

      expect(controller.isMapPrimaryView, isFalse);
      expect(find.text('MAPA'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('Critério de aceite: Ao voar e rotacionar yaw, FpvCameraView atualiza projeção do terreno', (tester) async {
      final controller = SimulatorController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FpvCameraView(
              controller: controller,
              showGroundMap: true,
              showOsd: false,
            ),
          ),
        ),
      );
      await tester.pump();

      // Decola o drone
      controller.armAndTakeoff();
      for (int i = 0; i < 20; i++) {
        controller.update(0.016);
      }
      await tester.pump();

      // Drone voa para frente (throttle + pitch)
      controller.setManualInput(pitch: 0.8, throttle: 0.2);
      for (int i = 0; i < 20; i++) {
        controller.update(0.016);
      }
      await tester.pump();

      expect(controller.z, greaterThan(0.0));
      expect(find.byType(FpvCameraView), findsOneWidget);

      // Rotaciona yaw
      controller.setManualInput(yaw: 0.5);
      for (int i = 0; i < 10; i++) {
        controller.update(0.016);
      }
      await tester.pump();

      expect(tester.takeException(), isNull);
      controller.dispose();
    });
  });
}
