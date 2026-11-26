import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/models/race_course.dart';
import 'package:drone_simulator/services/records_repository.dart';
import 'package:drone_simulator/simulation/freestyle_manager.dart';
import 'package:drone_simulator/simulation/race_manager.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/widgets/game_hud_overlay.dart';

void main() {
  group('Bloco 2 — Detecção no plano orientado do portal (RaceManager)', () {
    test('Rejeita voo paralelo à frente e retorno sem cruzar o plano', () {
      const gate = RaceGate(
        index: 0,
        x: 0.0,
        y: 50.0,
        z: 15.0,
        yawDeg: 0.0,
        radius: 4.5,
      );
      const course = RaceCourse(
        mapId: 'test_plane',
        name: 'Teste Plano',
        gates: [gate],
      );
      final manager = RaceManager(course: course)..start();

      // Voo paralelo a 2.0 m antes do portal (dentro da esfera de 4.5 m, sem cruzar o plano).
      for (var x = -3.0; x <= 3.0; x += 0.5) {
        manager.update(
          dt: 0.016,
          x: x,
          y: 48.0,
          z: 15.0,
          speedKmh: 40.0,
          crashed: false,
        );
      }
      expect(manager.gatesCleared, 0);
      expect(manager.currentGateIndex, 0);

      // Aproxima até 1.0 m e recua sem cruzar o plano y = 50.0.
      manager.update(
        dt: 0.016,
        x: 0.0,
        y: 49.0,
        z: 15.0,
        speedKmh: 30.0,
        crashed: false,
      );
      manager.update(
        dt: 0.016,
        x: 0.0,
        y: 47.0,
        z: 15.0,
        speedKmh: 30.0,
        crashed: false,
      );
      expect(manager.gatesCleared, 0);
    });

    test('Rejeita cruzamento fora do raio interno e valida cruzamento interno + alta velocidade',
        () {
      const gate0 = RaceGate(
        index: 0,
        x: 0.0,
        y: 50.0,
        z: 15.0,
        yawDeg: 0.0,
        radius: 4.5,
      );
      const gate1 = RaceGate(
        index: 1,
        x: 40.0,
        y: 90.0,
        z: 18.0,
        yawDeg: 45.0,
        radius: 4.5,
      );
      const course = RaceCourse(
        mapId: 'test_plane_2',
        name: 'Teste Plano 2',
        gates: [gate0, gate1],
      );
      final manager = RaceManager(course: course)..start();

      // Cruza o plano y = 50 fora do anel (x = 5.5 m > radius 4.5 m).
      manager.update(
        dt: 0.016,
        x: 5.5,
        y: 48.0,
        z: 15.0,
        speedKmh: 60.0,
        crashed: false,
      );
      manager.update(
        dt: 0.016,
        x: 5.5,
        y: 52.0,
        z: 15.0,
        speedKmh: 60.0,
        crashed: false,
      );
      expect(manager.gatesCleared, 0);

      // Volta para trás e cruza em alta velocidade (y = 40 -> 60) com x = 1.5 m.
      manager.update(
        dt: 0.016,
        x: 1.5,
        y: 40.0,
        z: 15.0,
        speedKmh: 110.0,
        crashed: false,
      );
      manager.update(
        dt: 0.016,
        x: 1.5,
        y: 60.0,
        z: 15.0,
        speedKmh: 110.0,
        crashed: false,
      );
      expect(manager.gatesCleared, 1);
      expect(manager.currentGateIndex, 1);
      expect(manager.lastGateAccuracy, closeTo(1.0 - 1.5 / 4.5, 0.02));

      // Portal diagonal (yawDeg = 45°): cruza ao longo da normal (sin 45°, cos 45°).
      final (nx, ny) = gate1.planeNormal;
      manager.update(
        dt: 0.016,
        x: gate1.x - nx * 2.5,
        y: gate1.y - ny * 2.5,
        z: gate1.z,
        speedKmh: 80.0,
        crashed: false,
      );
      manager.update(
        dt: 0.016,
        x: gate1.x + nx * 2.5,
        y: gate1.y + ny * 2.5,
        z: gate1.z,
        speedKmh: 80.0,
        crashed: false,
      );
      expect(manager.status, RaceStatus.finished);
      expect(manager.gatesCleared, 2);
    });
  });

  group('Bloco 2 — Novas manobras no FreestyleManager', () {
    test('Detecta POWER LOOP quando há loop 360° com variação vertical e velocidade',
        () {
      final fs = FreestyleManager()..start();

      // Simula um loop completo de 1.2s com variação de altitude de 12m para 22m.
      const steps = 72;
      for (var i = 0; i < steps; i++) {
        final phase = i / steps;
        final alt = 12.0 + math.sin(phase * math.pi) * 10.0;
        fs.update(
          dt: 1.0 / 60.0,
          altitude: alt,
          speedKmh: 48.0,
          verticalSpeedMs: 4.0,
          omegaPitchRadS: 5.4,
          omegaRollRadS: 0.0,
          omegaYawRadS: 0.0,
          minObstacleClearance: 20.0,
          crashed: false,
        );
      }

      expect(fs.lastTrickLabel, 'POWER LOOP');
      expect(fs.score, greaterThanOrEqualTo(400.0));
      expect(fs.trickBreakdown['POWER LOOP'], 1);
    });

    test('Detecta SPLIT-S sem duplicar Dive Recovery', () {
      final fs = FreestyleManager()..start();

      // 1. Rola até ficar invertido em altitude segura (25m).
      for (var i = 0; i < 24; i++) {
        fs.update(
          dt: 1.0 / 60.0,
          altitude: 25.0,
          speedKmh: 38.0,
          verticalSpeedMs: -0.5,
          omegaPitchRadS: 0.0,
          omegaRollRadS: 6.0,
          omegaYawRadS: 0.0,
          minObstacleClearance: 20.0,
          crashed: false,
          upWorldZ: i > 12 ? -0.6 : 0.4,
        );
      }

      // 2. Puxa pitch durante o mergulho perdendo altitude.
      for (var i = 0; i < 40; i++) {
        fs.update(
          dt: 1.0 / 60.0,
          altitude: 24.0 - i * 0.25,
          speedKmh: 62.0,
          verticalSpeedMs: -8.0,
          omegaPitchRadS: 3.2,
          omegaRollRadS: 0.0,
          omegaYawRadS: 0.0,
          minObstacleClearance: 20.0,
          crashed: false,
          upWorldZ: -0.2,
        );
      }

      // 3. Nivela no fundo (14m -> perda > 10m).
      fs.update(
        dt: 1.0 / 60.0,
        altitude: 14.0,
        speedKmh: 55.0,
        verticalSpeedMs: -0.5,
        omegaPitchRadS: 2.5,
        omegaRollRadS: 0.0,
        omegaYawRadS: 0.0,
        minObstacleClearance: 20.0,
        crashed: false,
        upWorldZ: 0.85,
      );

      expect(fs.lastTrickLabel, 'SPLIT-S');
      expect(fs.trickBreakdown['SPLIT-S'], 1);
      expect(fs.trickBreakdown['DIVE RECOVERY'], isNull);
      expect(fs.score, greaterThanOrEqualTo(380.0));
    });

    test('Detecta INVERTED HANGTIME sustentado e ignora flip invertido rápido',
        () {
      final fs = FreestyleManager()..start();

      // Passa brevemente invertido (0.35s) -> não deve premiar.
      for (var i = 0; i < 21; i++) {
        fs.update(
          dt: 1.0 / 60.0,
          altitude: 18.0,
          speedKmh: 28.0,
          verticalSpeedMs: 0.0,
          omegaPitchRadS: 0.0,
          omegaRollRadS: 0.0,
          omegaYawRadS: 0.0,
          minObstacleClearance: 20.0,
          crashed: false,
          upWorldZ: -0.75,
        );
      }
      expect(fs.tricksCount, 0);

      // Volta a ficar direito e depois sustenta invertido por 1.0s.
      for (var i = 0; i < 30; i++) {
        fs.update(
          dt: 1.0 / 60.0,
          altitude: 18.0,
          speedKmh: 28.0,
          verticalSpeedMs: 0.0,
          omegaPitchRadS: 0.0,
          omegaRollRadS: 0.0,
          omegaYawRadS: 0.0,
          minObstacleClearance: 20.0,
          crashed: false,
          upWorldZ: 0.9,
        );
      }
      for (var i = 0; i < 60; i++) {
        fs.update(
          dt: 1.0 / 60.0,
          altitude: 18.0,
          speedKmh: 26.0,
          verticalSpeedMs: -1.0,
          omegaPitchRadS: 0.0,
          omegaRollRadS: 0.0,
          omegaYawRadS: 0.0,
          minObstacleClearance: 20.0,
          crashed: false,
          upWorldZ: -0.8,
        );
      }

      expect(fs.lastTrickLabel, 'INVERTED HANGTIME');
      expect(fs.trickBreakdown['INVERTED HANGTIME'], 1);
      expect(fs.score, greaterThanOrEqualTo(220.0));
    });
  });

  group('Bloco 2 — Replay pós-corrida (SimulatorController & GameHudOverlay)',
      () {
    test('Quat.fromEuler preserva ângulos no round-trip com toEulerRadians', () {
      const p = 0.35;
      const r = -0.42;
      const y = 1.15;
      final q = Quat.fromEuler(pitch: p, roll: r, yaw: y);
      final euler = q.toEulerRadians();
      expect(euler.pitch, closeTo(p, 1e-6));
      expect(euler.roll, closeTo(r, 1e-6));
      expect(euler.yaw, closeTo(y, 1e-6));
    });

    test('SimulatorController grava trajetória da corrida e controla replay completo',
        () {
      final controller = SimulatorController(
        records: RecordsRepository(store: InMemoryKeyValueStore()),
      );
      addTearDown(controller.dispose);

      controller.setSimulatorMode(SimulatorMode.gateRace);
      controller.armAndTakeoff();
      final gates = controller.raceCourse!.gates;
      for (var i = 0; i < gates.length; i++) {
        final gate = gates[i];
        controller.setPosition(gate.x, gate.y, gate.z);
        // Roda alguns ticks para produzir duração real de replay (> 0.3s).
        for (var k = 0; k < 4; k++) {
          controller.update(0.016);
        }
      }

      expect(controller.raceStatus, RaceStatus.finished);
      expect(controller.hasReplayAvailable, isTrue);
      expect(controller.replayDurationSeconds, greaterThan(0.2));

      final batteryBeforeReplay = controller.battery;
      expect(controller.cameraMode, CameraViewMode.fpv);
      expect(controller.startReplay(), isTrue);
      expect(controller.isReplaying, isTrue);
      expect(controller.isReplayPaused, isFalse);
      expect(controller.cameraMode, CameraViewMode.thirdPerson);

      // Avança replay e confirma que o tempo avança e a bateria não drena.
      controller.update(0.1);
      expect(controller.replayTimeSeconds, closeTo(0.1, 1e-4));
      expect(controller.battery, batteryBeforeReplay);

      // Velocidade cicla 1.0 -> 2.0 -> 0.5 -> 1.0.
      expect(controller.replaySpeed, 1.0);
      controller.cycleReplaySpeed();
      expect(controller.replaySpeed, 2.0);
      controller.cycleReplaySpeed();
      expect(controller.replaySpeed, 0.5);
      controller.cycleReplaySpeed();
      expect(controller.replaySpeed, 1.0);

      // Seek + pausa automática ao alcançar o fim.
      final dur = controller.replayDurationSeconds;
      controller.seekReplay(dur * 0.5);
      expect(controller.replayTimeSeconds, closeTo(dur * 0.5, 1e-4));

      controller.update(dur + 1.0);
      expect(controller.replayTimeSeconds, closeTo(dur, 1e-4));
      expect(controller.isReplayPaused, isTrue);

      // Reiniciar e parar replay restauram o modo de câmera anterior.
      controller.restartReplay();
      expect(controller.replayTimeSeconds, 0.0);
      expect(controller.isReplayPaused, isFalse);

      controller.stopReplay();
      expect(controller.isReplaying, isFalse);
      expect(controller.cameraMode, CameraViewMode.fpv);
      expect(controller.raceStatus, RaceStatus.finished);
    });

    testWidgets(
        'GameHudOverlay em 640x360 exibe ASSISTIR REPLAY, controles de replay e retorna ao card final',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = SimulatorController(
        records: RecordsRepository(store: InMemoryKeyValueStore()),
      );
      addTearDown(controller.dispose);
      controller.setSimulatorMode(SimulatorMode.gateRace);
      controller.armAndTakeoff();

      for (final gate in controller.raceCourse!.gates) {
        controller.setPosition(gate.x, gate.y, gate.z);
        for (var k = 0; k < 4; k++) {
          controller.update(0.016);
        }
      }
      expect(controller.raceStatus, RaceStatus.finished);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GameHudOverlay(controller: controller)),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      expect(find.byKey(const Key('race_finish_card')), findsOneWidget);
      expect(find.byKey(const Key('btn_watch_replay')), findsOneWidget);
      expect(find.byKey(const Key('btn_race_replay')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('btn_watch_replay')));
      await tester.tap(find.byKey(const Key('btn_watch_replay')));
      await tester.pump();
      expect(tester.takeException(), isNull);

      expect(controller.isReplaying, isTrue);
      expect(find.byKey(const Key('race_finish_card')), findsNothing);
      expect(find.byKey(const Key('replay_controls_bar')), findsOneWidget);
      expect(find.byKey(const Key('btn_replay_play_pause')), findsOneWidget);
      expect(find.byKey(const Key('btn_replay_speed')), findsOneWidget);
      expect(find.byKey(const Key('btn_replay_camera')), findsOneWidget);
      expect(find.byKey(const Key('btn_replay_exit')), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_replay_speed')));
      await tester.pump();
      expect(find.text('2.0x'), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_replay_camera')));
      await tester.pump();
      expect(find.text('FPV'), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_replay_exit')));
      await tester.pump();
      expect(controller.isReplaying, isFalse);
      expect(find.byKey(const Key('race_finish_card')), findsOneWidget);
    });
  });
}
