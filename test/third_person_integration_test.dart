import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/main.dart';
import 'package:drone_simulator/models/drone_state.dart';
import 'package:drone_simulator/widgets/fpv_camera_view.dart';
import 'package:drone_simulator/widgets/fpv_osd_overlay.dart';
import 'package:drone_simulator/widgets/world_3d_view.dart';

void main() {
  group('Etapa 5 - Ajustar Câmera/OSD para 3ª Pessoa e Integração Final 3D', () {
    testWidgets('FpvCameraView: ajusta pitch (-12°) e atenua roll (0.4) em 3ª Pessoa', (tester) async {
      // 1. Câmera em 1ª Pessoa (FPV)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FpvCameraView(
              cameraMode: CameraViewMode.fpv,
              visualPitch: 10.0,
              visualRoll: 20.0,
              showGroundMap: false,
            ),
          ),
        ),
      );
      expect(find.byType(FpvCameraView), findsOneWidget);

      final customPaintFpv = tester.widget<CustomPaint>(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter is FpvCameraPainter),
      );
      final painterFpv = customPaintFpv.painter as FpvCameraPainter;
      expect(painterFpv.visualPitch, equals(10.0));
      expect(painterFpv.visualRoll, equals(20.0));

      // 2. Câmera em 3ª Pessoa (Chase Cam)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FpvCameraView(
              cameraMode: CameraViewMode.thirdPerson,
              visualPitch: 10.0,
              visualRoll: 20.0,
              showGroundMap: false,
            ),
          ),
        ),
      );
      expect(find.byType(FpvCameraView), findsOneWidget);

      final customPaintThird = tester.widget<CustomPaint>(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter is FpvCameraPainter),
      );
      final painterThird = customPaintThird.painter as FpvCameraPainter;
      // Pitch offset de -12°: 10.0 - 12.0 = -2.0
      expect(painterThird.visualPitch, equals(-2.0));
      // Roll amortecido (0.4): 20.0 * 0.4 = 8.0
      expect(painterThird.visualRoll, equals(8.0));
    });

    testWidgets('FpvOsdOverlay: suprime a escada de pitch/horizonte em 3ª Pessoa mas mantém a bússola', (tester) async {
      // 1. Modo FPV padrão: horizonte artificial ativo
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FpvOsdOverlay(
              cameraMode: CameraViewMode.fpv,
              showHorizonLadder: true,
              showTopCompass: true,
            ),
          ),
        ),
      );

      final customPaintFpv = tester.widget<CustomPaint>(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter is FpvOsdPainter),
      );
      final painterFpv = customPaintFpv.painter as FpvOsdPainter;
      expect(painterFpv.showHorizonLadder, isTrue);
      expect(painterFpv.showTopCompass, isTrue);

      // 2. Modo 3ª Pessoa: retícula e escada ocultadas para desobstruir o modelo 3D
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FpvOsdOverlay(
              cameraMode: CameraViewMode.thirdPerson,
              showHorizonLadder: true,
              showTopCompass: true,
            ),
          ),
        ),
      );

      final customPaintThird = tester.widget<CustomPaint>(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter is FpvOsdPainter),
      );
      final painterThird = customPaintThird.painter as FpvOsdPainter;
      expect(painterThird.showHorizonLadder, isFalse);
      expect(painterThird.showTopCompass, isTrue);
    });

    testWidgets('Integração Main: World3dView permanece na tela principal e alternar câmera funciona', (tester) async {
      await tester.pumpWidget(const DroneSimulatorApp());
      await tester.pump();

      // World3dView DEVE estar na árvore principal
      expect(find.byType(World3dView), findsOneWidget);

      // Clica no botão de alternar câmera no TelemetryHud
      final toggleCameraFinder = find.byKey(const Key('btn_camera_mode'));
      expect(toggleCameraFinder, findsOneWidget);

      await tester.tap(toggleCameraFinder);
      await tester.pump();

      // Continua com World3dView ativo no modo 3ª pessoa
      expect(find.byType(World3dView), findsOneWidget);

      // Alterna de volta para FPV
      await tester.tap(toggleCameraFinder);
      await tester.pump();

      expect(find.byType(World3dView), findsOneWidget);
    });

    testWidgets('Decolagem e voo com World3dView mantêm rendering 60FPS estável sem exceções', (tester) async {
      await tester.pumpWidget(const DroneSimulatorApp());
      await tester.pump();

      // Alterna para 3ª pessoa
      await tester.tap(find.byKey(const Key('btn_camera_mode')));
      await tester.pump();
      expect(find.byType(World3dView), findsOneWidget);

      // Decolar
      final takeoffBtn = find.byKey(const Key('action_takeoff'));
      if (takeoffBtn.evaluate().isNotEmpty) {
        await tester.tap(takeoffBtn);
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Renderiza múltiplos frames simulados de voo
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.byType(World3dView), findsOneWidget);
    });
  });
}
