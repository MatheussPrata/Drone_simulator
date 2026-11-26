import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/main.dart';
import 'package:drone_simulator/models/drone_profile.dart';
import 'package:drone_simulator/models/flight_map.dart';
import 'package:drone_simulator/models/world_obstacle.dart';
import 'package:drone_simulator/services/records_repository.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/simulation/world_generator.dart';
import 'package:drone_simulator/ui/screens/home_menu_screen.dart';
import 'package:drone_simulator/widgets/fpv_osd_overlay.dart';
import 'package:drone_simulator/widgets/map_settings_modal.dart';
import 'package:drone_simulator/widgets/virtual_joystick.dart';

void main() {
  group('Bloco 1 — Pouso em telhados 6-DoF', () {
    test('Pouso manual e automático (land) pousam suavemente sobre o telhado', () {
      final controller = SimulatorController(
        records: RecordsRepository(store: InMemoryKeyValueStore()),
      );
      addTearDown(controller.dispose);

      controller.sixDof.baseWindWorld = Vec3.zero;
      controller.sixDof.turbulenceIntensity = 0.0;

      final building = WorldGenerator.generateFor(FlightMap.dronePark)
          .firstWhere((o) => o.type == ObstacleType.building && o.height < 60);

      // 1. Descida manual sobre o telhado
      controller.armAndTakeoff();
      for (var i = 0; i < 400; i++) {
        controller.update(0.016);
        if (controller.status == SimulatorStatus.hovering) break;
      }
      expect(controller.status, SimulatorStatus.hovering);

      controller.setPosition(building.x, building.y, building.height + 6.0);
      controller.setManualInput(throttle: -1.0);
      for (var i = 0; i < 400; i++) {
        controller.update(0.016);
      }

      expect(controller.z, closeTo(building.height, 0.08));
      expect(controller.currentGroundHeightM, building.height);
      expect(controller.altitudeAgl, lessThan(0.1));
      expect(controller.isCrashed, isFalse);

      // 2. Comando land() sobre o telhado mantém posição (x, y) e pousa no topo
      controller.setManualInput();
      controller.setPosition(building.x, building.y, building.height + 6.0);
      controller.land();
      for (var i = 0; i < 500; i++) {
        controller.update(0.016);
        if (controller.status == SimulatorStatus.landed) break;
      }

      expect(controller.status, SimulatorStatus.landed);
      expect(controller.isArmed, isFalse);
      expect(controller.isCrashed, isFalse);
      expect(controller.z, closeTo(building.height, 0.02));
      expect(controller.currentGroundHeightM, building.height);
      expect(controller.altitudeAgl, closeTo(0.0, 0.02));
      expect(controller.x, closeTo(building.x, 1.0));
      expect(controller.y, closeTo(building.y, 1.0));
    });

    test('Decolagem (armAndTakeoff) a partir do telhado sobe 10 m acima do topo',
        () {
      final controller = SimulatorController(
        records: RecordsRepository(store: InMemoryKeyValueStore()),
      );
      addTearDown(controller.dispose);

      controller.sixDof.baseWindWorld = Vec3.zero;
      controller.sixDof.turbulenceIntensity = 0.0;

      final building = WorldGenerator.generateFor(FlightMap.dronePark)
          .firstWhere((o) => o.type == ObstacleType.building && o.height < 60);

      controller.setPosition(building.x, building.y, building.height);
      expect(controller.currentGroundHeightM, building.height);
      expect(controller.altitudeAgl, 0.0);

      controller.armAndTakeoff();
      for (var i = 0; i < 500; i++) {
        controller.update(0.016);
        if (controller.status == SimulatorStatus.hovering) break;
      }

      expect(controller.status, SimulatorStatus.hovering);
      expect(
        controller.z,
        closeTo(building.height + SimulatorController.targetTakeoffAltitude, 0.4),
      );
      expect(
        controller.altitudeAgl,
        closeTo(SimulatorController.targetTakeoffAltitude, 0.4),
      );
    });

    test('Queda violenta sobre o telhado dispara crash e pousa no topo do prédio',
        () {
      final controller = SimulatorController(
        records: RecordsRepository(store: InMemoryKeyValueStore()),
      );
      addTearDown(controller.dispose);

      controller.sixDof.baseWindWorld = Vec3.zero;
      controller.sixDof.turbulenceIntensity = 0.0;

      final building = WorldGenerator.generateFor(FlightMap.dronePark)
          .firstWhere((o) => o.type == ObstacleType.building && o.height < 60);

      controller.armAndTakeoff();
      for (var i = 0; i < 400; i++) {
        controller.update(0.016);
        if (controller.status == SimulatorStatus.hovering) break;
      }

      controller.setFlightMode(FlightControlMode.acro);
      controller.setPosition(building.x, building.y, building.height + 15.0);
      controller.setManualInput(throttle: -1.0);

      var sawCrash = false;
      for (var i = 0; i < 500; i++) {
        controller.update(0.016);
        if (controller.status == SimulatorStatus.crashed) {
          sawCrash = true;
          break;
        }
      }
      expect(sawCrash, isTrue);

      for (var i = 0; i < 600; i++) {
        controller.update(0.016);
        if (controller.status == SimulatorStatus.landed) break;
      }

      expect(controller.status, SimulatorStatus.landed);
      expect(controller.isArmed, isFalse);
      expect(controller.z, closeTo(building.height, 0.05));
    });

    test('Colisão lateral contra parede do prédio continua bloqueada', () {
      final controller = SimulatorController(
        records: RecordsRepository(store: InMemoryKeyValueStore()),
      );
      addTearDown(controller.dispose);

      controller.sixDof.baseWindWorld = Vec3.zero;
      controller.sixDof.turbulenceIntensity = 0.0;

      final building = WorldGenerator.generateFor(FlightMap.dronePark)
          .firstWhere((o) => o.type == ObstacleType.building && o.height > 25);

      controller.armAndTakeoff();
      for (var i = 0; i < 400; i++) {
        controller.update(0.016);
        if (controller.status == SimulatorStatus.hovering) break;
      }

      controller.setPosition(
        building.x,
        building.y - building.depth / 2 - 14.0,
        building.height * 0.5,
      );
      controller.setManualInput(pitch: 1.0);

      var crashed = false;
      for (var i = 0; i < 400; i++) {
        controller.update(0.016);
        if (controller.status == SimulatorStatus.crashed) {
          crashed = true;
          break;
        }
        expect(
          building.coversPoint(controller.x, controller.y),
          isFalse,
          reason: 'Drone abaixo do topo não deve invadir o interior do prédio',
        );
      }

      expect(crashed, isTrue);
    });
  });

  group('Bloco 1 — Otimização 60 FPS na tela principal', () {
    testWidgets(
        'FlightSimulatorScreen e VirtualJoystick não reconstroem durante ticks de 60 FPS',
        (tester) async {
      final prevRebuildCallback = debugOnRebuildDirtyWidget;
      var screenRebuilds = 0;
      var joystickRebuilds = 0;
      addTearDown(() {
        debugOnRebuildDirtyWidget = prevRebuildCallback;
      });

      final repo = RecordsRepository(store: InMemoryKeyValueStore());
      await tester.pumpWidget(
        MaterialApp(
          home: FlightSimulatorScreen(recordsRepository: repo),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException();

      debugOnRebuildDirtyWidget = (Element element, bool builtOnce) {
        if (element.widget is FlightSimulatorScreen) {
          screenRebuilds++;
        } else if (element.widget is VirtualJoystick) {
          joystickRebuilds++;
        }
      };

      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      tester.takeException();

      expect(screenRebuilds, 0,
          reason: 'Ticks 60 FPS não devem reconstruir FlightSimulatorScreen');
      expect(joystickRebuilds, 0,
          reason: 'Ticks 60 FPS não devem reconstruir VirtualJoystick');

      // Troca de visão (PiP swap) deve reconstruir a tela principal uma vez.
      await tester.tap(find.byKey(const Key('pip_swap_button')));
      await tester.pump();
      tester.takeException();

      expect(screenRebuilds, greaterThanOrEqualTo(1));
      expect(find.byType(FpvOsdOverlay), findsNothing);
    });
  });

  group('Bloco 1 — Persistência e edição de AcroSettings', () {
    test('AcroSettings serializa com toJson/fromJson e aplica clamp seguro', () {
      const original = AcroSettings(
        preset: AcroRatePreset.freestyle,
        maxRateDegPerSec: 310.0,
        expo: 0.62,
        horizonAssist: 0.0,
        fpvUptiltDeg: 18.0,
        coordinatedTurn: false,
      );

      final roundTrip = AcroSettings.fromJson(original.toJson());
      expect(roundTrip, equals(original));

      final clamped = AcroSettings.fromJson({
        'preset': 'invalido',
        'maxRateDegPerSec': 9999,
        'expo': -2.0,
        'horizonAssist': 5.0,
        'fpvUptiltDeg': 80.0,
        'coordinatedTurn': false,
      });
      expect(clamped.preset, AcroRatePreset.standard);
      expect(clamped.maxRateDegPerSec, 600.0);
      expect(clamped.expo, 0.0);
      expect(clamped.horizonAssist, 0.75);
      expect(clamped.fpvUptiltDeg, 30.0);
      expect(clamped.coordinatedTurn, isFalse);
    });

    test(
        'RecordsRepository persiste AcroSettings entre instâncias e SimulatorController respeita no Freestyle',
        () async {
      final store = InMemoryKeyValueStore();
      final repo1 = RecordsRepository(store: store);
      await repo1.loadAll();

      const custom = AcroSettings(
        preset: AcroRatePreset.smooth,
        maxRateDegPerSec: 135.0,
        expo: 0.35,
        horizonAssist: 0.0,
        fpvUptiltDeg: 16.0,
        coordinatedTurn: false,
      );
      await repo1.saveAcroSettings(custom);

      final repo2 = RecordsRepository(store: store);
      await repo2.loadAll();
      expect(repo2.hasSavedAcroSettings, isTrue);
      expect(repo2.acroSettings, equals(custom));

      final controller = SimulatorController(records: repo2);
      addTearDown(controller.dispose);
      expect(controller.acroSettings, equals(custom));

      controller.configureSession(
        mode: SimulatorMode.freestyle,
        map: FlightMap.dronePark,
        profile: DroneProfile.fpvRacer,
        flightMode: FlightControlMode.acro,
        timeOfDay: TimeOfDayPreset.day,
      );
      expect(controller.acroSettings, equals(custom));
    });

    testWidgets(
        'HomeMenuScreen e MapSettingsModal editam, preservam e persistem AcroSettings',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = InMemoryKeyValueStore();
      final repo1 = RecordsRepository(store: store);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeMenuScreen(recordsRepository: repo1),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_home_acro_config')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('acro_preset_smooth')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('acro_horizon_switch')));
      await tester.tap(find.byKey(const Key('acro_horizon_switch')));
      await tester.pump();
      await tester
          .ensureVisible(find.byKey(const Key('acro_coordinated_switch')));
      await tester.tap(find.byKey(const Key('acro_coordinated_switch')));
      await tester.pump();

      expect(repo1.acroSettings.preset, AcroRatePreset.smooth);
      expect(repo1.acroSettings.horizonAssist, 0.0);
      expect(repo1.acroSettings.coordinatedTurn, isFalse);

      // Fecha a bottom sheet da Home e recria a Home com novo repositório no mesmo store.
      await tester.tap(find.byKey(const Key('acro_sheet_close_button')));
      await tester.pumpAndSettle();

      final repo2 = RecordsRepository(store: store);
      await tester.pumpWidget(
        MaterialApp(
          home: HomeMenuScreen(
            key: const ValueKey('home_reloaded'),
            recordsRepository: repo2,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo2.hasSavedAcroSettings, isTrue);
      expect(repo2.acroSettings.preset, AcroRatePreset.smooth);

      await tester.tap(find.byKey(const Key('btn_start_simulator')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      tester.takeException();

      expect(find.byType(FlightSimulatorScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('pip_layers_button')));
      await tester.pumpAndSettle();
      expect(find.byType(MapSettingsModal), findsOneWidget);

      // Verifica que os valores salvos vieram para o modal em voo.
      await tester
          .ensureVisible(find.byKey(const Key('modal_acro_horizon_switch')));
      final modalHorizon = tester
          .widget<SwitchListTile>(find.byKey(const Key('modal_acro_horizon_switch')));
      await tester
          .ensureVisible(find.byKey(const Key('modal_acro_coordinated_switch')));
      final modalCoord = tester.widget<SwitchListTile>(
          find.byKey(const Key('modal_acro_coordinated_switch')));
      expect(modalHorizon.value, isFalse);
      expect(modalCoord.value, isFalse);

      // Edita dentro do voo e confirma persistência de volta no repositório.
      await tester
          .ensureVisible(find.byKey(const Key('modal_acro_preset_freestyle')));
      await tester.tap(find.byKey(const Key('modal_acro_preset_freestyle')));
      await tester.pump();
      await tester
          .ensureVisible(find.byKey(const Key('modal_acro_coordinated_switch')));
      await tester.tap(find.byKey(const Key('modal_acro_coordinated_switch')));
      await tester.pump();

      expect(repo2.acroSettings.preset, AcroRatePreset.freestyle);
      expect(repo2.acroSettings.coordinatedTurn, isTrue);

      await tester.ensureVisible(find.byKey(const Key('modal_close_button')));
      await tester.tap(find.byKey(const Key('modal_close_button')));
      await tester.pumpAndSettle();
      tester.takeException();

      // Volta ao HomeMenuScreen e confirma que a edição feita em voo refletiu na Home.
      await tester.tap(find.byKey(const Key('btn_open_home_menu')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      tester.takeException();
      expect(find.byType(HomeMenuScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_home_acro_config')));
      await tester.pumpAndSettle();
      final homeFreestyleChip = tester.widget<ChoiceChip>(
        find.byKey(const Key('acro_preset_freestyle')),
      );
      final homeCoordSwitch = tester.widget<SwitchListTile>(
        find.byKey(const Key('acro_coordinated_switch')),
      );
      expect(homeFreestyleChip.selected, isTrue);
      expect(homeCoordSwitch.value, isTrue);
    });
  });
}
