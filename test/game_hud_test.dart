import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drone_simulator/simulation/flight_physics.dart';
import 'package:drone_simulator/simulation/race_manager.dart';
import 'package:drone_simulator/widgets/game_hud_overlay.dart';
import 'package:drone_simulator/widgets/telemetry_hud.dart';

void main() {
  group('Etapa 4 — HUD do modo jogo e tela de crash', () {
    testWidgets('Botão da barra alterna VOO LIVRE ↔ MODO JOGO', (tester) async {
      final controller = SimulatorController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: TelemetryHud(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('btn_sim_mode')), findsOneWidget);
      expect(find.text('VOO LIVRE'), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_sim_mode')));
      await tester.pump();

      expect(controller.isRaceMode, true);
      expect(find.text('MODO JOGO'), findsOneWidget);
    });

    testWidgets('Painel da corrida mostra portal, tempo, pontos e distância',
        (tester) async {
      final controller = SimulatorController();
      addTearDown(controller.dispose);
      controller.toggleSimulatorMode();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GameHudOverlay(controller: controller)),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('race_panel')), findsOneWidget);
      expect(find.text('PORTAL'), findsOneWidget);
      expect(find.text('1/10'), findsOneWidget);
      expect(find.text('TEMPO'), findsOneWidget);
      expect(find.text('PONTOS'), findsOneWidget);
      expect(find.text('PRÓXIMO'), findsOneWidget);
    });

    testWidgets('Card de queda mostra impacto e reinicia o voo', (tester) async {
      final controller = SimulatorController();
      addTearDown(controller.dispose);

      controller.sixDof.baseWindWorld = const Vec3(0, 0, 0);
      controller.sixDof.turbulenceIntensity = 0.0;

      final tower = WorldGenerator.generateFor(FlightMap.dronePark)
          .firstWhere((o) => o.type == ObstacleType.tower);

      controller.armAndTakeoff();
      for (var i = 0; i < 500; i++) {
        controller.update(0.016);
        if (controller.status == SimulatorStatus.hovering) break;
      }
      controller.setPosition(tower.x, tower.y - 22.0, 10.0);
      controller.setManualInput(pitch: 1.0);
      for (var i = 0; i < 600 && !controller.isCrashed; i++) {
        controller.update(0.016);
      }
      expect(controller.isCrashed, true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GameHudOverlay(controller: controller)),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('crash_card')), findsOneWidget);
      expect(find.text('QUEDA DETECTADA'), findsOneWidget);
      expect(find.byKey(const Key('btn_restart_flight')), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_restart_flight')));
      await tester.pump();

      expect(controller.isCrashed, false);
      expect(find.byKey(const Key('crash_card')), findsNothing);
    });

    testWidgets('Card de vitória aparece ao concluir os 10 portais',
        (tester) async {
      final controller = SimulatorController();
      addTearDown(controller.dispose);
      controller.toggleSimulatorMode();

      final manager = controller.raceManager!;
      for (final gate in manager.course.gates) {
        controller.setPosition(gate.x, gate.y, gate.z);
        controller.update(0.016);
      }

      expect(manager.status, RaceStatus.finished);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GameHudOverlay(controller: controller)),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('race_finish_card')), findsOneWidget);
      expect(find.text('CIRCUITO CONCLUÍDO!'), findsOneWidget);
      expect(find.byKey(const Key('btn_race_replay')), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_race_replay')));
      await tester.pump();

      expect(controller.raceManager!.status, RaceStatus.racing);
      expect(find.byKey(const Key('race_finish_card')), findsNothing);
    });
  });
}
