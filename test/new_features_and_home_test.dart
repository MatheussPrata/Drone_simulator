import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/main.dart';
import 'package:drone_simulator/models/flight_map.dart';
import 'package:drone_simulator/models/race_course.dart';
import 'package:drone_simulator/services/records_repository.dart';
import 'package:drone_simulator/simulation/freestyle_manager.dart';
import 'package:drone_simulator/simulation/quadrotor_physics_6dof.dart';
import 'package:drone_simulator/simulation/race_manager.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/ui/screens/home_menu_screen.dart';
import 'package:drone_simulator/widgets/game_hud_overlay.dart';

void main() {
  group('Página Inicial, Novos Modos, Acro Aprimorado, Recordes e Ghost', () {
    testWidgets('HomeMenuScreen cabe em 640x360 sem overflow e inicia voo configurado',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = InMemoryKeyValueStore();
      final repo = RecordsRepository(store: store);

      await tester.pumpWidget(
        DroneSimulatorApp(
          showHomeOnStart: true,
          recordsRepository: repo,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(HomeMenuScreen), findsOneWidget);
      expect(find.byKey(const Key('mode_freeFlight')), findsOneWidget);
      expect(find.byKey(const Key('mode_gateRace')), findsOneWidget);
      expect(find.byKey(const Key('mode_timeAttack')), findsOneWidget);
      expect(find.byKey(const Key('mode_freestyle')), findsOneWidget);

      await tester.tap(find.byKey(const Key('mode_timeAttack')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('home_map_parque_florestal')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('home_light_night')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_start_simulator')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Drena eventuais exceções HTTP 400 do TileLayer no TestWidgetsFlutterBinding offline.
      tester.takeException();

      expect(find.byType(FlightSimulatorScreen), findsOneWidget);
      expect(find.text('TIME ATTACK'), findsOneWidget);
      expect(find.byKey(const Key('race_panel')), findsOneWidget);
    });

    test('Acro centrado em throttle=0 mantém voo controlável sem disparar ao espaço',
        () {
      final engine = QuadrotorPhysicsEngine(
        baseWindWorld: Vec3.zero,
        turbulenceIntensity: 0.0,
      );
      engine.reset(position: const Vec3(0, 0, 20));
      engine.setArmed(true);

      for (var i = 0; i < 180; i++) {
        engine.step(
          input: PilotStickInput.neutral,
          dt: 1.0 / 60.0,
          mode: FlightControlMode.acro,
        );
      }

      expect(engine.snapshot.position.z, closeTo(20.0, 2.5),
          reason: 'Stick esquerdo neutro deve pairar suave em Acro para touch');
    });

    test('Acro preset Freestyle permite flip 360° contínuo e é mais ágil que Smooth',
        () {
      final smooth = QuadrotorPhysicsEngine(
        acroSettings: AcroSettings.forPreset(AcroRatePreset.smooth),
      );
      final freestyle = QuadrotorPhysicsEngine(
        acroSettings: AcroSettings.forPreset(AcroRatePreset.freestyle),
      );
      smooth.reset(position: const Vec3(0, 0, 50));
      freestyle.reset(position: const Vec3(0, 0, 50));
      smooth.setArmed(true);
      freestyle.setArmed(true);

      double freestylePitchAccum = 0.0;
      for (var i = 0; i < 90; i++) {
        smooth.step(
          input: const PilotStickInput(pitch: 1.0),
          dt: 1.0 / 60.0,
          mode: FlightControlMode.acro,
        );
        final snap = freestyle.step(
          input: const PilotStickInput(pitch: 1.0),
          dt: 1.0 / 60.0,
          mode: FlightControlMode.acro,
        );
        freestylePitchAccum += snap.angularVelocityBody.x.abs() * (1.0 / 60.0);
      }

      expect(freestyle.snapshot.angularVelocityBody.x.abs(),
          greaterThan(smooth.snapshot.angularVelocityBody.x.abs() * 1.8));
      expect(freestylePitchAccum, greaterThan(2.0 * math.pi),
          reason: 'Preset Freestyle deve completar flip 360° em 1.5s');
    });

    test('Time Attack adiciona segundos bônus, cicla portais e encerra ao zerar relógio',
        () {
      final manager = RaceManager(
        course: RaceCourse.forMap(FlightMap.dronePark),
        timeAttackMode: true,
      )..start();

      expect(manager.remainingSeconds, 25.0);

      // Consome 10s sem passar em portal.
      for (var i = 0; i < 100; i++) {
        manager.update(
          dt: 0.1,
          x: 999,
          y: 999,
          z: 50,
          speedKmh: 0,
          crashed: false,
        );
      }
      expect(manager.remainingSeconds, closeTo(15.0, 0.2));

      // Cruza os 10 portais + 1 (circuito infinito).
      for (var i = 0; i < 11; i++) {
        final gate = manager.activeGate!;
        manager.update(
          dt: 0.05,
          x: gate.x,
          y: gate.y,
          z: gate.z,
          speedKmh: 50.0,
          crashed: false,
        );
      }
      expect(manager.gatesCleared, 11);
      expect(manager.currentGateIndex, 1);
      expect(manager.remainingSeconds, greaterThan(25.0));

      // Deixa o tempo zerar.
      for (var i = 0; i < 400; i++) {
        manager.update(
          dt: 0.1,
          x: 999,
          y: 999,
          z: 50,
          speedKmh: 0,
          crashed: false,
        );
        if (manager.isFinished) break;
      }
      expect(manager.status, RaceStatus.finished);
    });

    test('FreestyleManager detecta Flip 360°, Barrel Roll e Voo Rasante com combo',
        () {
      final fs = FreestyleManager()..start();

      // Flip 360° (~6.3 rad em 1.2s)
      for (var i = 0; i < 72; i++) {
        fs.update(
          dt: 1.0 / 60.0,
          altitude: 20.0,
          speedKmh: 35.0,
          verticalSpeedMs: 0.0,
          omegaPitchRadS: 5.5,
          omegaRollRadS: 0.0,
          omegaYawRadS: 0.0,
          minObstacleClearance: 20.0,
          crashed: false,
        );
      }
      expect(fs.lastTrickLabel, 'FLIP 360°');
      expect(fs.tricksCount, greaterThanOrEqualTo(1));
      expect(fs.score, greaterThanOrEqualTo(250.0));

      // Barrel Roll 360°
      for (var i = 0; i < 72; i++) {
        fs.update(
          dt: 1.0 / 60.0,
          altitude: 20.0,
          speedKmh: 35.0,
          verticalSpeedMs: 0.0,
          omegaPitchRadS: 0.0,
          omegaRollRadS: 5.5,
          omegaYawRadS: 0.0,
          minObstacleClearance: 20.0,
          crashed: false,
        );
      }
      expect(fs.lastTrickLabel, 'BARREL ROLL 360°');
      expect(fs.combo, greaterThan(1));

      // Voo Rasante (0.8s a <2.8m de altitude e >24 km/h)
      for (var i = 0; i < 50; i++) {
        fs.update(
          dt: 1.0 / 60.0,
          altitude: 1.8,
          speedKmh: 38.0,
          verticalSpeedMs: 0.0,
          omegaPitchRadS: 0.0,
          omegaRollRadS: 0.0,
          omegaYawRadS: 0.0,
          minObstacleClearance: 10.0,
          crashed: false,
        );
      }
      expect(fs.lastTrickLabel, 'VOO RASANTE');
    });

    test('RecordsRepository persiste medalhas e GhostTrajectory interpola posição',
        () async {
      final store = InMemoryKeyValueStore();
      final repo1 = RecordsRepository(store: store);
      await repo1.loadAll();

      final frames = [
        const GhostFrame(
            t: 0.0, x: 0, y: 0, z: 10, pitchRad: 0, rollRad: 0, yawRad: 0),
        const GhostFrame(
            t: 1.0, x: 10, y: 20, z: 14, pitchRad: 0.2, rollRad: 0, yawRad: 1.0),
      ];

      final saved = await repo1.saveRaceResult(
        mapId: FlightMap.dronePark.id,
        profileId: 'fpvRacer',
        elapsedSeconds: 39.5,
        score: 2450,
        bestCombo: 4,
        ghostFrames: frames,
      );

      expect(saved.isNewRecord, isTrue);
      expect(saved.record.medal, MedalTier.gold);

      // Recarrega a partir de outra instância usando o mesmo store.
      final repo2 = RecordsRepository(store: store);
      await repo2.loadAll();
      final loaded = repo2.recordFor(FlightMap.dronePark.id);
      expect(loaded.bestRaceTimeSec, 39.5);
      expect(loaded.medal, MedalTier.gold);

      final mid = loaded.ghostTrajectory.sampleAt(0.5);
      expect(mid, isNotNull);
      expect(mid!.x, closeTo(5.0, 0.05));
      expect(mid.y, closeTo(10.0, 0.05));
      expect(mid.z, closeTo(12.0, 0.05));
    });

    test('Cena 3D inclui Web Audio, luz dinâmica, ghost e câmera Acro quaternion',
        () {
      final html = File('assets/scene3d/index.html').readAsStringSync();
      expect(html.contains('AudioContext'), isTrue);
      expect(html.contains('window.triggerSoundEffect'), isTrue);
      expect(html.contains('window.setLightingPreset'), isTrue);
      expect(html.contains('ghostGroup'), isTrue);
      expect(html.contains('isAcroFpv'), isTrue);
      expect(html.contains('createGroundTexture'), isTrue);
      expect(html.contains('cdn.jsdelivr.net'), isFalse);
    });

    testWidgets('GameHudOverlay exibe painel de Freestyle e banner de manobra',
        (tester) async {
      final controller = SimulatorController(
        records: RecordsRepository(store: InMemoryKeyValueStore()),
      );
      addTearDown(controller.dispose);
      controller.setSimulatorMode(SimulatorMode.freestyle);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GameHudOverlay(controller: controller)),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('freestyle_panel')), findsOneWidget);
      expect(find.text('MANOBRAS'), findsOneWidget);
    });
  });
}
