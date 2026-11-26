import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/main.dart';
import 'package:drone_simulator/models/drone_profile.dart';
import 'package:drone_simulator/models/flight_map.dart';
import 'package:drone_simulator/models/race_course.dart';
import 'package:drone_simulator/services/records_repository.dart';
import 'package:drone_simulator/simulation/freestyle_manager.dart';
import 'package:drone_simulator/simulation/quadrotor_physics_6dof.dart';
import 'package:drone_simulator/simulation/race_manager.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/simulation/world_generator.dart';
import 'package:drone_simulator/widgets/game_hud_overlay.dart';
import 'package:drone_simulator/widgets/mini_map_widget.dart';
import 'package:drone_simulator/widgets/virtual_joystick.dart';

void main() {
  group('Bloco 4 — Missões Aéreas & Piloto Automático', () {
    test('AerialMission.forMap gera missões válidas e evita No-Fly Zones', () {
      for (final map in FlightMap.availableMaps) {
        final missions = AerialMission.forMap(map);
        expect(missions.length, greaterThanOrEqualTo(4));
        expect(missions.any((m) => m.kind == MissionKind.waypointRoute), isTrue);
        expect(
            missions.any((m) => m.kind == MissionKind.towerInspection), isTrue);
        expect(missions.any((m) => m.kind == MissionKind.roofPrecisionLanding),
            isTrue);
        expect(missions.any((m) => m.kind == MissionKind.noFlyPatrol), isTrue);

        for (final m in missions) {
          expect(m.checkpoints, isNotEmpty);
          if (m.forbidNoFlyZone) {
            for (final cp in m.checkpoints) {
              for (final nfz in map.noFlyZones) {
                final nfzMeters = FlightMap.latLngToMeters(nfz.center, map.center);
                final dist = math.sqrt(
                  math.pow(cp.x - nfzMeters.dx, 2) +
                      math.pow(cp.y - nfzMeters.dy, 2),
                );
                expect(dist, greaterThan(nfz.radiusMeters),
                    reason: '${m.id} cp ${cp.index} não pode ficar dentro da NFZ');
              }
            }
          }
        }
      }
    });

    test('MissionManager valida hover, falha por NFZ e pouso de precisão', () {
      const mission = AerialMission(
        id: 'test_mission',
        mapId: 'distrito_urbano',
        name: 'Teste',
        description: 'Teste unitário',
        kind: MissionKind.roofPrecisionLanding,
        forbidNoFlyZone: true,
        checkpoints: [
          MissionCheckpoint(
            index: 0,
            label: 'WP1',
            x: 10.0,
            y: 20.0,
            z: 18.0,
            captureRadius: 6.0,
            requiredHoverSec: 0.5,
          ),
          MissionCheckpoint(
            index: 1,
            label: 'Pouso',
            x: 10.0,
            y: 20.0,
            z: 11.0,
            captureRadius: 5.0,
            requireLanding: true,
          ),
        ],
      );

      final manager = MissionManager(mission: mission)..start();
      // Hover de 0.6s no WP1 conclui WP1.
      for (var i = 0; i < 6; i++) {
        manager.update(
          dt: 0.1,
          x: 10.0,
          y: 20.0,
          z: 18.0,
          isLanded: false,
          isGrounded: false,
          groundHeightM: 11.0,
          crashed: false,
          inNoFlyZone: false,
          geofenceBreach: false,
        );
      }
      expect(manager.currentCheckpointIndex, 1);
      expect(manager.checkpointsCompleted, 1);

      // Pousa no telhado dentro do raio -> conclui missão.
      manager.update(
        dt: 0.1,
        x: 10.5,
        y: 19.5,
        z: 11.0,
        isLanded: true,
        isGrounded: true,
        groundHeightM: 11.0,
        crashed: false,
        inNoFlyZone: false,
        geofenceBreach: false,
      );
      expect(manager.status, MissionStatus.completed);
      expect(manager.score, greaterThan(500.0));

      // Invasão de NFZ falha imediatamente.
      final nfzManager = MissionManager(mission: mission)..start();
      nfzManager.update(
        dt: 0.1,
        x: 120.0,
        y: -280.0,
        z: 20.0,
        isLanded: false,
        isGrounded: false,
        groundHeightM: 0.0,
        crashed: false,
        inNoFlyZone: true,
        geofenceBreach: false,
      );
      expect(nfzManager.status, MissionStatus.failed);
      expect(nfzManager.failureReason, contains('No-Fly Zone'));
    });

    test(
        'SimulatorController executa missão autônoma de pouso em telhado e desengaja ao toque manual',
        () async {
      final store = InMemoryKeyValueStore();
      final repo = RecordsRepository(store: store);
      final controller = SimulatorController(records: repo);
      addTearDown(controller.dispose);

      controller.setWindMultiplier(0.0);
      controller.setSimulatorMode(SimulatorMode.missions);
      final roofMission = controller.availableMissionsForActiveMap
          .firstWhere((m) => m.kind == MissionKind.roofPrecisionLanding);
      controller.selectMission(roofMission, autopilot: true);
      expect(controller.isMissionAutopilotActive, isTrue);

      // Decola até altitude segura antes de testar desengate manual.
      for (var i = 0; i < 160; i++) {
        controller.update(0.016);
      }
      expect(controller.z, greaterThan(5.0));

      // Toque manual forte desengaja o piloto automático.
      controller.setManualInput(pitch: 0.6);
      expect(controller.isMissionAutopilotActive, isFalse);
      controller.setManualInput();

      // Reativa piloto automático mesmo em modo Acro e acompanha até concluir o pouso no telhado.
      controller.setFlightMode(FlightControlMode.acro);
      controller.setMissionAutopilot(true);
      for (var i = 0;
          i < 5500 && controller.missionStatus != MissionStatus.completed;
          i++) {
        controller.update(0.016);
      }

      expect(controller.missionStatus, MissionStatus.completed);
      expect(controller.isLanded, isTrue);
      expect(controller.currentGroundHeightM, greaterThan(5.0));
      await Future<void>.delayed(Duration.zero);
      expect(
        repo.recordFor(FlightMap.dronePark.id).completedMissions,
        contains('roof_precision_landing'),
      );
    });
  });

  group('Bloco 4 — Circuitos Variados (Dificuldade e Reversa)', () {
    test('RaceCourse.forMap gera 10 portais livres em Easy, Medium, Pro e Reverse',
        () {
      for (final map in FlightMap.availableMaps) {
        final obstacles = WorldGenerator.generateFor(map);
        final mediumStd = RaceCourse.forMap(
          map,
          difficulty: CourseDifficulty.medium,
          direction: CourseDirection.standard,
        );
        final easyStd = RaceCourse.forMap(
          map,
          difficulty: CourseDifficulty.easy,
          direction: CourseDirection.standard,
        );
        final proRev = RaceCourse.forMap(
          map,
          difficulty: CourseDifficulty.pro,
          direction: CourseDirection.reverse,
        );

        expect(mediumStd.gates.length, 10);
        expect(easyStd.gates.length, 10);
        expect(proRev.gates.length, 10);
        expect(easyStd.gates.first.radius, closeTo(6.2, 1e-6));
        expect(mediumStd.gates.first.radius, closeTo(4.5, 1e-6));
        expect(proRev.gates.first.radius, closeTo(3.2, 1e-6));

        final medRev = RaceCourse.forMap(
          map,
          difficulty: CourseDifficulty.medium,
          direction: CourseDirection.reverse,
        );
        expect(medRev.gates.first.x, closeTo(mediumStd.gates.last.x, 1e-3));
        expect(medRev.gates.first.y, closeTo(mediumStd.gates.last.y, 1e-3));

        for (final course in [easyStd, mediumStd, proRev]) {
          for (final g in course.gates) {
            expect(g.z, inInclusiveRange(8.0, 45.0));
            for (final o in obstacles) {
              if (o.collidesAt(g.x, g.y, g.radius)) {
                expect(g.z, greaterThan(o.height),
                    reason:
                        '${map.id} ${course.variantKey} gate ${g.index} em ${o.id}');
              }
            }
          }
        }
      }
    });

    test('RaceManager escala pontuação e bônus de Time Attack conforme dificuldade',
        () {
      final easyMgr = RaceManager(
        course: RaceCourse.forMap(
          FlightMap.dronePark,
          difficulty: CourseDifficulty.easy,
        ),
        timeAttackMode: true,
      )..start();
      final proMgr = RaceManager(
        course: RaceCourse.forMap(
          FlightMap.dronePark,
          difficulty: CourseDifficulty.pro,
        ),
        timeAttackMode: true,
      )..start();

      final gEasy = easyMgr.activeGate!;
      easyMgr.update(
          dt: 0.05, x: gEasy.x, y: gEasy.y, z: gEasy.z, speedKmh: 50, crashed: false);
      final gPro = proMgr.activeGate!;
      proMgr.update(
          dt: 0.05, x: gPro.x, y: gPro.y, z: gPro.z, speedKmh: 50, crashed: false);

      expect(proMgr.score, greaterThan(easyMgr.score));
      expect(easyMgr.remainingSeconds, greaterThan(proMgr.remainingSeconds));
    });
  });

  group('Bloco 4 — Freestyle 2.0 (Gap, Under Bridge & Desafio)', () {
    test('FreestyleManager detecta UNDER BRIDGE, GAP THREAD e completa desafio sem cair',
        () {
      var challengeAwarded = false;
      final fs = FreestyleManager(
        challenge: const FreestyleChallenge(
          mapId: 'canion_represa',
          title: 'Desafio Teste',
          description: '1000 pts e 3 manobras sem cair',
          targetScore: 1000.0,
          requireNoCrash: true,
          minDistinctTricks: 3,
        ),
        onChallengeCompleted: (_) => challengeAwarded = true,
      )..start();

      // 1. Under bridge (0.3s) -> 360 pts
      for (var i = 0; i < 20; i++) {
        fs.update(
          dt: 1.0 / 60.0,
          altitude: 10.0,
          speedKmh: 40.0,
          verticalSpeedMs: 0.0,
          omegaPitchRadS: 0.0,
          omegaRollRadS: 0.0,
          omegaYawRadS: 0.0,
          minObstacleClearance: 6.0,
          crashed: false,
          underBridge: true,
        );
      }
      expect(fs.lastTrickLabel, 'UNDER BRIDGE');
      expect(fs.trickBreakdown['UNDER BRIDGE'], 1);

      // 2. Gap thread (0.35s) -> +320*2 = 640 pts (combo 2)
      for (var i = 0; i < 24; i++) {
        fs.update(
          dt: 1.0 / 60.0,
          altitude: 8.0,
          speedKmh: 42.0,
          verticalSpeedMs: 0.0,
          omegaPitchRadS: 0.0,
          omegaRollRadS: 0.0,
          omegaYawRadS: 0.0,
          minObstacleClearance: 3.0,
          crashed: false,
          inTightGap: true,
        );
      }
      expect(fs.lastTrickLabel, 'GAP THREAD');
      expect(fs.trickBreakdown['GAP THREAD'], 1);

      // 3. Flip 360° fecha 3 manobras distintas e bate meta de 1000 pts.
      for (var i = 0; i < 70; i++) {
        fs.update(
          dt: 1.0 / 60.0,
          altitude: 20.0,
          speedKmh: 36.0,
          verticalSpeedMs: 0.0,
          omegaPitchRadS: 5.5,
          omegaRollRadS: 0.0,
          omegaYawRadS: 0.0,
          minObstacleClearance: 15.0,
          crashed: false,
        );
      }
      expect(fs.challengeCompleted, isTrue);
      expect(challengeAwarded, isTrue);

      // Se cair antes, desafio sem-queda não completa.
      final fsFail = FreestyleManager(
        challenge: const FreestyleChallenge(
          mapId: 'canion_represa',
          title: 'Desafio Sem Cair',
          description: 'Sem quedas',
          targetScore: 200.0,
          requireNoCrash: true,
          minDistinctTricks: 1,
        ),
      )..start();
      fsFail.update(
        dt: 0.016,
        altitude: 5.0,
        speedKmh: 30.0,
        verticalSpeedMs: 0.0,
        omegaPitchRadS: 0.0,
        omegaRollRadS: 0.0,
        omegaYawRadS: 0.0,
        minObstacleClearance: 10.0,
        crashed: true,
      );
      expect(fsFail.hadCrash, isTrue);
      for (var i = 0; i < 70; i++) {
        fsFail.update(
          dt: 1.0 / 60.0,
          altitude: 20.0,
          speedKmh: 35.0,
          verticalSpeedMs: 0.0,
          omegaPitchRadS: 5.5,
          omegaRollRadS: 0.0,
          omegaYawRadS: 0.0,
          minObstacleClearance: 15.0,
          crashed: false,
        );
      }
      expect(fsFail.challengeCompleted, isFalse);
    });
  });

  group('Bloco 4 — Garagem/Tuning & Recorde/Ghost por Perfil', () {
    test(
        'DroneTuning serializa com clamp defensivo e altera parâmetros 6-DoF no RecordsRepository',
        () async {
      final badDecoded = DroneTuning.fromJson({
        'ledColorHex': 'invalido',
        'armColorHex': '#123456',
        'cameraFovDeg': 250.0,
        'weightMultiplier': 0.2,
        'batteryCapacityMultiplier': 5.0,
      });
      expect(badDecoded.ledColorHex, '#00d4ff');
      expect(badDecoded.armColorHex, '#123456');
      expect(badDecoded.cameraFovDeg, 105.0);
      expect(badDecoded.weightMultiplier, 0.80);
      expect(badDecoded.batteryCapacityMultiplier, 1.50);

      final store = InMemoryKeyValueStore();
      final repo1 = RecordsRepository(store: store);
      await repo1.loadAll();
      const custom = DroneTuning(
        ledColorHex: '#ff7a00',
        armColorHex: '#5c6773',
        cameraFovDeg: 88.0,
        weightMultiplier: 1.20,
        batteryCapacityMultiplier: 1.40,
      );
      await repo1.saveDroneTuning(custom);

      final repo2 = RecordsRepository(store: store);
      await repo2.loadAll();
      expect(repo2.droneTuning, equals(custom));

      final baseParams = QuadrotorPhysicsEngine.paramsForProfile(
        DroneProfile.fpvRacer,
      );
      final tunedParams = QuadrotorPhysicsEngine.paramsForProfile(
        DroneProfile.fpvRacer,
        tuning: custom,
      );
      expect(tunedParams.massKg, closeTo(baseParams.massKg * 1.20, 1e-6));
      expect(tunedParams.batteryCapacityWh,
          closeTo(baseParams.batteryCapacityWh * 1.40, 1e-6));
    });

    test(
        'Recordes, medalhas e GhostTrajectory são isolados entre Mini 249g e FPV Racer',
        () async {
      final store = InMemoryKeyValueStore();
      final repo = RecordsRepository(store: store);
      await repo.loadAll();

      await repo.saveRaceResult(
        mapId: FlightMap.dronePark.id,
        profileId: DroneProfileType.fpvRacer.name,
        elapsedSeconds: 36.0,
        score: 2600,
        bestCombo: 5,
        ghostFrames: const [
          GhostFrame(
              t: 0, x: 0, y: 0, z: 10, pitchRad: 0, rollRad: 0, yawRad: 0),
          GhostFrame(
              t: 10, x: 100, y: 100, z: 20, pitchRad: 0, rollRad: 0, yawRad: 0),
        ],
      );

      final recBeforeMini = repo.recordFor(FlightMap.dronePark.id);
      expect(recBeforeMini.bestTimeForProfile(DroneProfileType.fpvRacer.name),
          36.0);
      expect(recBeforeMini.medalForProfile(DroneProfileType.fpvRacer.name),
          MedalTier.gold);
      expect(recBeforeMini.bestTimeForProfile(DroneProfileType.mini249g.name),
          isNull);
      expect(recBeforeMini.medalForProfile(DroneProfileType.mini249g.name),
          MedalTier.none);
      expect(
          recBeforeMini
              .ghostTrajectoryForProfile(DroneProfileType.mini249g.name)
              .isEmpty,
          isTrue);

      final miniSaved = await repo.saveRaceResult(
        mapId: FlightMap.dronePark.id,
        profileId: DroneProfileType.mini249g.name,
        elapsedSeconds: 52.0,
        score: 1800,
        bestCombo: 3,
        ghostFrames: const [
          GhostFrame(
              t: 0, x: 0, y: 0, z: 10, pitchRad: 0, rollRad: 0, yawRad: 0),
          GhostFrame(
              t: 10, x: 25, y: 25, z: 15, pitchRad: 0, rollRad: 0, yawRad: 0),
        ],
      );
      expect(miniSaved.isNewRecord, isTrue);

      final controller = SimulatorController(records: repo);
      addTearDown(controller.dispose);
      controller.setSimulatorMode(SimulatorMode.gateRace);
      controller.selectDroneProfile(DroneProfile.mini249g);
      controller.update(0.1);
      final miniGhost = controller.currentGhostFrame;
      expect(miniGhost, isNotNull);
      expect(miniGhost!.x, lessThan(2.0));

      controller.selectDroneProfile(DroneProfile.fpvRacer);
      final racerGhost = controller.currentGhostFrame;
      expect(racerGhost, isNotNull);
      expect(racerGhost!.x, closeTo(miniGhost.x * 4.0, 0.2));
    });

    test('Cena 3D inclui aparência da garagem e marcadores 3D de missão sem CDN',
        () {
      final html = File('assets/scene3d/index.html').readAsStringSync();
      expect(html.contains('window.setDroneAppearance'), isTrue);
      expect(html.contains('window.updateMissionState'), isTrue);
      expect(html.contains('missionGroup'), isTrue);
      expect(html.contains('baseFovDeg'), isTrue);
      expect(html.contains('cdn.jsdelivr.net'), isFalse);
    });
  });

  group('Bloco 4 — Widgets em 640x360 & 0 Rebuilds', () {
    testWidgets(
        'HomeMenuScreen em 640x360 exibe todos os 5 modos, Garagem, variantes e recorde por perfil',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = InMemoryKeyValueStore();
      final repo = RecordsRepository(store: store);
      await repo.saveRaceResult(
        mapId: FlightMap.dronePark.id,
        profileId: DroneProfileType.fpvRacer.name,
        elapsedSeconds: 38.4,
        score: 2500,
        bestCombo: 4,
      );

      await tester.pumpWidget(
        DroneSimulatorApp(showHomeOnStart: true, recordsRepository: repo),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.byKey(const Key('mode_freeFlight')), findsOneWidget);
      expect(find.byKey(const Key('mode_gateRace')), findsOneWidget);
      expect(find.byKey(const Key('mode_timeAttack')), findsOneWidget);
      expect(find.byKey(const Key('mode_freestyle')), findsOneWidget);
      expect(find.byKey(const Key('mode_missions')), findsOneWidget);
      expect(find.byKey(const Key('btn_home_garage')), findsOneWidget);

      // FPV Racer tem recorde 00:38.4; ao alternar para Mini 249g muda para Sem recorde.
      expect(find.textContaining('00:38.4'), findsOneWidget);
      await tester.tap(find.byKey(const Key('profile_mini249g')));
      await tester.pump();
      expect(find.textContaining('00:38.4'), findsNothing);

      // Seleciona pista Reversa + Pro.
      await tester.ensureVisible(find.byKey(const Key('course_dir_reverse')));
      await tester.tap(find.byKey(const Key('course_dir_reverse')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('course_diff_pro')));
      await tester.tap(find.byKey(const Key('course_diff_pro')));
      await tester.pump();

      // Abre a Garagem, muda LED e fecha.
      await tester.tap(find.byKey(const Key('btn_home_garage')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('garage_led_2')));
      await tester.pump();
      expect(repo.droneTuning.ledColorHex, DroneTuning.ledPalette[2]);
      await tester.tap(find.byKey(const Key('garage_sheet_close_button')));
      await tester.pumpAndSettle();

      // Seleciona modo Missões e inicia voo.
      await tester.tap(find.byKey(const Key('mode_missions')));
      await tester.pump();
      expect(find.byKey(const Key('home_mission_tower_inspection')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('home_mission_tower_inspection')));
      await tester.tap(find.byKey(const Key('home_mission_tower_inspection')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_start_simulator')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      tester.takeException();

      expect(find.byType(FlightSimulatorScreen), findsOneWidget);
      expect(find.byKey(const Key('mission_panel')), findsOneWidget);
    });

    testWidgets(
        'GameHudOverlay exibe painel de missão, falha NFZ, desafio Freestyle e conclusão',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = SimulatorController(
        records: RecordsRepository(store: InMemoryKeyValueStore()),
      );
      addTearDown(controller.dispose);
      controller.setSimulatorMode(SimulatorMode.missions);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GameHudOverlay(controller: controller)),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('mission_panel')), findsOneWidget);
      expect(find.byKey(const Key('btn_mission_autopilot')), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_mission_autopilot')));
      await tester.pump();
      expect(controller.isMissionAutopilotActive, isTrue);

      // Testa card de falha por NFZ em patrulha.
      final patrol = controller.availableMissionsForActiveMap
          .firstWhere((m) => m.kind == MissionKind.noFlyPatrol);
      controller.selectMission(patrol);
      controller.armAndTakeoff();
      controller.setPosition(120.0, -280.0, 20.0);
      controller.update(0.016);
      await tester.pump();
      expect(find.byKey(const Key('mission_failed_card')), findsOneWidget);
      expect(find.byKey(const Key('btn_restart_mission')), findsOneWidget);

      // Testa pílula de desafio no Freestyle.
      controller.setSimulatorMode(SimulatorMode.freestyle);
      await tester.pump();
      expect(find.byKey(const Key('freestyle_challenge_pill')), findsOneWidget);
    });

    testWidgets(
        'MiniMapWidget em Missões mantém camadas únicas e FlightSimulatorScreen mantém 0 rebuilds',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = SimulatorController(
        records: RecordsRepository(store: InMemoryKeyValueStore()),
      );
      addTearDown(controller.dispose);
      controller.setSimulatorMode(SimulatorMode.missions);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: MiniMapWidget(
                controller: controller,
                showControls: true,
                offlineVectorMode: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      tester.takeException();

      expect(find.byType(PolygonLayer), findsOneWidget);
      expect(find.byType(PolylineLayer), findsOneWidget);
      expect(find.byType(CircleLayer), findsOneWidget);
      expect(find.byType(MarkerLayer), findsOneWidget);

      final prevRebuildCallback = debugOnRebuildDirtyWidget;
      var screenRebuilds = 0;
      var joystickRebuilds = 0;
      addTearDown(() {
        debugOnRebuildDirtyWidget = prevRebuildCallback;
      });

      await tester.pumpWidget(
        MaterialApp(
          home: FlightSimulatorScreen(
            initialMode: SimulatorMode.missions,
            recordsRepository: RecordsRepository(store: InMemoryKeyValueStore()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      tester.takeException();

      debugOnRebuildDirtyWidget = (Element element, bool builtOnce) {
        if (element.widget is FlightSimulatorScreen) {
          screenRebuilds++;
        } else if (element.widget is VirtualJoystick) {
          joystickRebuilds++;
        }
      };

      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      tester.takeException();

      expect(screenRebuilds, 0);
      expect(joystickRebuilds, 0);
    });
  });
}
