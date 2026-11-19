import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/widgets/telemetry_hud.dart';

void main() {
  group('Etapa 5 — Barra superior (HUD) em landscape', () {
    testWidgets('Cabe em tela landscape estreita sem overflow nem scroll',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = SimulatorController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: TelemetryHud(
                    controller: controller,
                    actionsPlacement: HudActionsPlacement.top,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // Nenhum RenderFlex overflow / erro de layout.
      expect(tester.takeException(), isNull);

      // Não existe scroll horizontal na barra superior.
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.byKey(const Key('btn_camera_mode')), findsOneWidget);
      expect(find.byKey(const Key('btn_map_settings')), findsOneWidget);
    });

    testWidgets('Banner de geofence não aparece a 17m do Home', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = SimulatorController();
      addTearDown(controller.dispose);

      controller.armAndTakeoff();
      controller.setPosition(17.0, 0.0, 10.0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: TelemetryHud(controller: controller),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('banner_geofence')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
