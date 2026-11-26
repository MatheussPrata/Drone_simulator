import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/main.dart';
import 'package:drone_simulator/services/gamepad_service.dart';
import 'package:drone_simulator/services/records_repository.dart';
import 'package:drone_simulator/simulation/quadrotor_physics_6dof.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/widgets/fpv_osd_overlay.dart';
import 'package:drone_simulator/widgets/mini_map_widget.dart';
import 'package:drone_simulator/widgets/virtual_joystick.dart';

void main() {
  group('Bloco 3 — Joystick Flutuante & Throttle Livre no Acro', () {
    testWidgets(
        'VirtualJoystick com autoCenterY=false mantém throttle e centraliza yaw ao soltar',
        (tester) async {
      Offset lastEmitted = Offset.zero;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: VirtualJoystick(
                radius: 50,
                stickRadius: 20,
                autoCenterY: false,
                onPositionChanged: (pos) => lastEmitted = pos,
              ),
            ),
          ),
        ),
      );

      final gestureFinder = find.byKey(const Key('virtual_joystick_gesture'));
      final center = tester.getCenter(gestureFinder);
      final gesture = await tester.startGesture(center);
      await tester.pump();
      await gesture.moveBy(const Offset(25, -20));
      await tester.pump();

      expect(lastEmitted.dx, greaterThan(0.4));
      expect(lastEmitted.dy, lessThan(-0.4));

      await gesture.up();
      await tester.pump();

      expect(lastEmitted.dx, 0.0);
      expect(lastEmitted.dy, lessThan(-0.4));
    });

    testWidgets(
        'VirtualJoystick flutuante centraliza onde o toque inicia e zera ao soltar',
        (tester) async {
      Offset lastEmitted = const Offset(99, 99);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: VirtualJoystick(
                radius: 40,
                stickRadius: 15,
                floating: true,
                floatingWidth: 200,
                floatingHeight: 140,
                onPositionChanged: (pos) => lastEmitted = pos,
              ),
            ),
          ),
        ),
      );

      final gestureFinder = find.byKey(const Key('virtual_joystick_gesture'));
      final topLeft = tester.getTopLeft(gestureFinder);
      final touchStart = topLeft + const Offset(55, 60);
      final gesture = await tester.startGesture(touchStart);
      await tester.pump();

      expect(lastEmitted, Offset.zero);

      await gesture.moveBy(const Offset(20, -15));
      await tester.pump();

      expect(lastEmitted.dx, greaterThan(0.5));
      expect(lastEmitted.dy, lessThan(-0.4));

      await gesture.up();
      await tester.pump();

      expect(lastEmitted, Offset.zero);
    });

    test(
        'AcroSettings persiste novas flags e QuadrotorPhysicsEngine aplica throttle livre no Acro',
        () async {
      final store = InMemoryKeyValueStore();
      final repo1 = RecordsRepository(store: store);
      await repo1.loadAll();

      const settings = AcroSettings(
        preset: AcroRatePreset.freestyle,
        maxRateDegPerSec: 310.0,
        expo: 0.55,
        horizonAssist: 0.0,
        fpvUptiltDeg: 14.0,
        coordinatedTurn: false,
        floatingJoysticks: true,
        manualAcroThrottle: true,
      );
      await repo1.saveAcroSettings(settings);

      final repo2 = RecordsRepository(store: store);
      await repo2.loadAll();
      expect(repo2.acroSettings.floatingJoysticks, isTrue);
      expect(repo2.acroSettings.manualAcroThrottle, isTrue);
      expect(repo2.acroSettings, equals(settings));

      final engine = QuadrotorPhysicsEngine(acroSettings: settings);
      engine.reset(position: const Vec3(0, 0, 25));
      engine.setArmed(true);

      // Throttle mínimo (-1.0) mantém motores em idle (~4%).
      for (var i = 0; i < 60; i++) {
        engine.step(
          input: const PilotStickInput(throttle: -1.0),
          dt: 1.0 / 60.0,
          mode: FlightControlMode.acro,
        );
      }
      final lowRpm =
          engine.snapshot.motorNormalizedRpm.reduce((a, b) => a + b) / 4.0;
      expect(lowRpm, lessThan(0.30));

      // Throttle máximo (+1.0) leva motores perto de 100%.
      for (var i = 0; i < 60; i++) {
        engine.step(
          input: const PilotStickInput(throttle: 1.0),
          dt: 1.0 / 60.0,
          mode: FlightControlMode.acro,
        );
      }
      final highRpm =
          engine.snapshot.motorNormalizedRpm.reduce((a, b) => a + b) / 4.0;
      expect(highRpm, greaterThan(0.85));
    });
  });

  group('Bloco 3 — Gamepad HID & Atalhos de Teclado', () {
    test('GamepadInputBridge aplica deadzone, mapeia eixos Modo 2 e botões',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final controller = SimulatorController(
        records: RecordsRepository(store: InMemoryKeyValueStore()),
      );
      addTearDown(controller.dispose);

      final bridge = GamepadInputBridge(controller: controller);
      bridge.attach();
      addTearDown(bridge.detach);

      expect(GamepadInputBridge.applyDeadzone(0.05), 0.0);
      expect(GamepadInputBridge.applyDeadzone(1.0), 1.0);
      expect(GamepadInputBridge.applyDeadzone(-0.54), inInclusiveRange(-0.6, -0.4));

      // Simula chamada nativa do MethodChannel de gamepad.
      const codec = StandardMethodCodec();
      final axesMessage = codec.encodeMethodCall(
        const MethodCall('axes', {
          'leftX': 0.5,
          'leftY': -0.8,
          'rightX': 0.2,
          'rightY': -0.6,
          'device': 'ELRS Radio HID',
        }),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        GamepadInputBridge.channel.name,
        axesMessage,
        (_) {},
      );

      expect(bridge.isGamepadConnected, isTrue);
      expect(bridge.connectedDeviceName, 'ELRS Radio HID');

      // Testa ações de botão via canal.
      final takeoffMessage = codec.encodeMethodCall(
        const MethodCall('button', {'action': 'arm_takeoff'}),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        GamepadInputBridge.channel.name,
        takeoffMessage,
        (_) {},
      );
      expect(controller.isArmed, isTrue);

      bridge.handleButtonAction('cycle_flight_mode');
      expect(controller.flightMode, FlightControlMode.sport);

      bridge.handleButtonAction('toggle_camera');
      expect(controller.cameraMode, CameraViewMode.thirdPerson);

      bridge.handleButtonAction('land');
      expect(controller.isLanding, isTrue);
    });

    test('GamepadInputBridge processa atalhos de teclado WASD / Setas / Space / C',
        () {
      final controller = SimulatorController(
        records: RecordsRepository(store: InMemoryKeyValueStore()),
      );
      addTearDown(controller.dispose);
      final bridge = GamepadInputBridge(controller: controller);

      final spaceRes = bridge.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.space,
          logicalKey: LogicalKeyboardKey.space,
          timeStamp: Duration.zero,
        ),
      );
      expect(spaceRes, KeyEventResult.handled);
      expect(controller.isArmed, isTrue);

      final camRes = bridge.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyC,
          logicalKey: LogicalKeyboardKey.keyC,
          timeStamp: Duration(milliseconds: 20),
        ),
      );
      expect(camRes, KeyEventResult.handled);
      expect(controller.cameraMode, CameraViewMode.thirdPerson);

      final wRes = bridge.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyW,
          logicalKey: LogicalKeyboardKey.keyW,
          timeStamp: Duration(milliseconds: 40),
        ),
      );
      expect(wRes, KeyEventResult.handled);
    });
  });

  group('Bloco 3 — OSD Alinhado ao Uptilt FPV, Cena 3D e Minimapa Offline', () {
    test('FpvOsdMath.effectiveCameraPitchDeg soma pitch, gimbal e fpvUptiltDeg',
        () {
      expect(
        FpvOsdMath.effectiveCameraPitchDeg(
          visualPitchDeg: -8.0,
          gimbalPitchDeg: -5.0,
          fpvUptiltDeg: 14.0,
        ),
        closeTo(1.0, 1e-6),
      );

      final a = FpvOsdPainter(
        yaw: 0,
        visualPitch: 0,
        visualRoll: 0,
        gimbalPitch: 0,
        fpvUptiltDeg: 10.0,
        altitudeAgl: 5.0,
        verticalSpeedMs: 1.2,
        nextGateX: 50.0,
        nextGateY: 0.0,
        nextGateNumber: 1,
        droneX: 0,
        droneY: 0,
        droneZ: 5,
      );
      final b = FpvOsdPainter(
        yaw: 0,
        visualPitch: 0,
        visualRoll: 0,
        gimbalPitch: 0,
        fpvUptiltDeg: 16.0,
        altitudeAgl: 5.0,
        verticalSpeedMs: 1.2,
        nextGateX: 50.0,
        nextGateY: 0.0,
        nextGateNumber: 1,
        droneX: 0,
        droneY: 0,
        droneZ: 5,
      );
      expect(a.shouldRepaint(b), isTrue);
    });

    testWidgets('FpvOsdOverlay renderiza em modo Acro + Gate Race sem exceções',
        (tester) async {
      final controller = SimulatorController(
        records: RecordsRepository(store: InMemoryKeyValueStore()),
      );
      addTearDown(controller.dispose);
      controller.setSimulatorMode(SimulatorMode.gateRace);
      controller.setFlightMode(FlightControlMode.acro);
      controller.setPosition(0, 0, 12);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 480,
              child: FpvOsdOverlay(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    test('Cena 3D inclui marcador de pouso no solo/telhado e ruído de hélices/vento',
        () {
      final html = File('assets/scene3d/index.html').readAsStringSync();
      expect(html.contains('landingMarkerGroup'), isTrue);
      expect(html.contains('updateLandingMarker'), isTrue);
      expect(html.contains('groundHeightM'), isTrue);
      expect(html.contains('propNoiseFilter'), isTrue);
      expect(html.contains('propNoiseGain'), isTrue);
      expect(html.contains('windGain'), isTrue);
      expect(html.contains('cdn.jsdelivr.net'), isFalse);
    });

    testWidgets(
        'MiniMapWidget renderiza modo vetorial offline mantendo layers únicas e botão de alternância',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = SimulatorController(
        records: RecordsRepository(store: InMemoryKeyValueStore()),
      );
      addTearDown(controller.dispose);

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

      expect(find.byKey(const Key('badge_offline_vector')), findsOneWidget);
      expect(find.text('VETORIAL OFFLINE'), findsOneWidget);
      expect(find.byType(TileLayer), findsOneWidget);
      expect(find.byType(PolygonLayer), findsOneWidget);
      expect(find.byType(PolylineLayer), findsOneWidget);
      expect(find.byType(CircleLayer), findsOneWidget);
      expect(find.byType(MarkerLayer), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_toggle_offline_vector')));
      await tester.pump();
      tester.takeException();
      expect(find.byKey(const Key('badge_offline_vector')), findsNothing);

      await tester.tap(find.byKey(const Key('btn_toggle_offline_vector')));
      await tester.pump();
      tester.takeException();
      expect(find.byKey(const Key('badge_offline_vector')), findsOneWidget);
    });

    testWidgets(
        'FlightSimulatorScreen com joystick flutuante e throttle livre mantém 0 rebuilds a 60 FPS',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final prevRebuildCallback = debugOnRebuildDirtyWidget;
      var screenRebuilds = 0;
      var joystickRebuilds = 0;
      addTearDown(() {
        debugOnRebuildDirtyWidget = prevRebuildCallback;
      });

      final repo = RecordsRepository(store: InMemoryKeyValueStore());
      await tester.pumpWidget(
        MaterialApp(
          home: FlightSimulatorScreen(
            initialFlightMode: FlightControlMode.acro,
            initialAcroSettings: const AcroSettings(
              floatingJoysticks: true,
              manualAcroThrottle: true,
            ),
            recordsRepository: repo,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException();

      final joysticks =
          tester.widgetList<VirtualJoystick>(find.byType(VirtualJoystick)).toList();
      expect(joysticks.length, 2);
      expect(joysticks[0].floating, isTrue);
      expect(joysticks[0].autoCenterY, isFalse);
      expect(joysticks[1].floating, isTrue);
      expect(joysticks[1].autoCenterY, isTrue);

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
