import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/widgets/virtual_joystick.dart';
import 'package:drone_simulator/widgets/telemetry_hud.dart';
import 'package:drone_simulator/widgets/map_canvas.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';

void main() {
  group('VirtualJoystick Widget Tests', () {
    testWidgets('Compila e renderiza de forma isolada sem erros', (tester) async {
      Offset currentOffset = const Offset(99, 99);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: VirtualJoystick(
                radius: 60,
                stickRadius: 20,
                label: 'THROTTLE / YAW',
                onPositionChanged: (pos) {
                  currentOffset = pos;
                },
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(VirtualJoystick), findsOneWidget);
      expect(find.text('THROTTLE / YAW'), findsOneWidget);
      expect(currentOffset, equals(const Offset(99, 99)));
    });

    testWidgets('Arrastar o joystick emite Offset normalizado [-1.0, 1.0] e soltar volta para (0,0)', (tester) async {
      Offset lastEmitted = const Offset(99, 99);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: VirtualJoystick(
                radius: 50,
                stickRadius: 20,
                onPositionChanged: (pos) {
                  lastEmitted = pos;
                },
              ),
            ),
          ),
        ),
      );

      final gestureFinder = find.byKey(const Key('virtual_joystick_gesture'));
      expect(gestureFinder, findsOneWidget);

      // 1. Toca no centro e arrasta para a direita
      final TestGesture gesture = await tester.startGesture(tester.getCenter(gestureFinder));
      await tester.pump();

      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();

      expect(lastEmitted.dx, greaterThan(0.0));
      expect(lastEmitted.dx, lessThanOrEqualTo(1.0));
      expect(lastEmitted.dy, closeTo(0.0, 0.05));

      // 2. Arrasta totalmente para a direita (além do raio)
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();

      expect(lastEmitted.dx, closeTo(1.0, 0.01));
      expect(lastEmitted.dy, closeTo(0.0, 0.01));

      // 3. Arrasta para o extremo diagonal: magnitude radial normalizada deve ser 1.0
      await gesture.moveBy(const Offset(0, 100));
      await tester.pump();

      final magnitude = sqrt(lastEmitted.dx * lastEmitted.dx + lastEmitted.dy * lastEmitted.dy);
      expect(magnitude, closeTo(1.0, 0.01));
      expect(lastEmitted.dx, inInclusiveRange(-1.0, 1.0));
      expect(lastEmitted.dy, inInclusiveRange(-1.0, 1.0));

      // 4. Solta o joystick -> deve voltar exatamente para (0, 0)
      await gesture.up();
      await tester.pump();

      expect(lastEmitted, equals(Offset.zero));
    });
  });

  group('TelemetryHud Widget Tests', () {
    testWidgets('Compila e exibe Altitude, Velocidade, Distância do Home e Bateria', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TelemetryHud(
              altitude: 18.5,
              speed: 24.2,
              distanceToHome: 135.0,
              battery: 82.0,
              isGeofenceWarning: false,
              isNoFlyWarning: false,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('18.5 m'), findsOneWidget);
      expect(find.text('24.2 km/h'), findsOneWidget);
      expect(find.text('135 m'), findsOneWidget);
      expect(find.text('82%'), findsOneWidget);

      // Banners vermelhos não devem aparecer quando desativados
      expect(find.byKey(const Key('banner_geofence')), findsNothing);
      expect(find.byKey(const Key('banner_nofly')), findsNothing);
    });

    testWidgets('Exibe banners de alerta vermelho quando isGeofenceWarning ou isNoFlyWarning estão ativos', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TelemetryHud(
              altitude: 45.0,
              speed: 12.0,
              distanceToHome: 480.0,
              battery: 65.0,
              isGeofenceWarning: true,
              isNoFlyWarning: true,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('banner_geofence')), findsOneWidget);
      expect(find.byKey(const Key('banner_nofly')), findsOneWidget);
      expect(find.textContaining('LIMITE MÁXIMO DE GEOFENCE'), findsOneWidget);
      expect(find.textContaining('ZONA DE EXCLUSÃO AÉREA'), findsOneWidget);
    });

    testWidgets('Botões de ação Decolar, Pousar, RTH e Reset disparam callbacks', (tester) async {
      bool takeoffPressed = false;
      bool landPressed = false;
      bool rthPressed = false;
      bool resetPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TelemetryHud(
              altitude: 0.0,
              speed: 0.0,
              distanceToHome: 0.0,
              battery: 100.0,
              onTakeoff: () => takeoffPressed = true,
              onLand: () => landPressed = true,
              onRth: () => rthPressed = true,
              onReset: () => resetPressed = true,
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('btn_takeoff')), findsOneWidget);
      expect(find.byKey(const Key('btn_land')), findsOneWidget);
      expect(find.byKey(const Key('btn_rth')), findsOneWidget);
      expect(find.byKey(const Key('btn_reset')), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_takeoff')));
      await tester.pump();
      expect(takeoffPressed, isTrue);

      await tester.tap(find.byKey(const Key('btn_land')));
      await tester.pump();
      expect(landPressed, isTrue);

      await tester.tap(find.byKey(const Key('btn_rth')));
      await tester.pump();
      expect(rthPressed, isTrue);

      await tester.tap(find.byKey(const Key('btn_reset')));
      await tester.pump();
      expect(resetPressed, isTrue);
    });

    testWidgets('Integração com SimulatorController atualiza telemetria dinamicamente', (tester) async {
      final controller = SimulatorController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TelemetryHud(controller: controller),
          ),
        ),
      );

      expect(find.text('0.0 m'), findsOneWidget); // altitude inicial 0
      expect(find.text('100%'), findsOneWidget);  // bateria inicial 100%

      // Modifica estado através do controller
      controller.setPosition(50.0, 50.0, 15.0);
      controller.setBattery(42.0);
      await tester.pump();

      expect(find.text('15.0 m'), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);

      controller.dispose();
    });
  });

  group('Stack Pilot Overlay Integration Tests', () {
    testWidgets('Interface de pilotagem completa sobre o mapa usando Stack compila e renderiza sem erros', (tester) async {
      final controller = SimulatorController();
      Offset leftStick = Offset.zero;
      Offset rightStick = Offset.zero;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                // 1. Camada de Fundo: Mapa 2D Canvas
                Positioned.fill(
                  child: MapCanvas(
                    controller: controller,
                    followDrone: true,
                  ),
                ),

                // 2. Camada Superior: HUD de Telemetria e Ações
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: TelemetryHud(
                    controller: controller,
                    actionsPlacement: HudActionsPlacement.top,
                  ),
                ),

                // 3. Camada Inferior Esquerda: Joystick Virtual (Altitude / Yaw)
                Positioned(
                  left: 20,
                  bottom: 20,
                  child: VirtualJoystick(
                    label: 'ALT / YAW',
                    radius: 55,
                    stickRadius: 20,
                    onPositionChanged: (pos) => leftStick = pos,
                  ),
                ),

                // 4. Camada Inferior Direita: Joystick Virtual (Pitch / Roll)
                Positioned(
                  right: 20,
                  bottom: 20,
                  child: VirtualJoystick(
                    label: 'PITCH / ROLL',
                    radius: 55,
                    stickRadius: 20,
                    onPositionChanged: (pos) => rightStick = pos,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Critério de aceite: compilação isolada e renderização sem warnings nem erros
      expect(tester.takeException(), isNull);
      expect(find.byType(MapCanvas), findsOneWidget);
      expect(find.byType(TelemetryHud), findsOneWidget);
      expect(find.byType(VirtualJoystick), findsNWidgets(2));
      expect(leftStick, equals(Offset.zero));
      expect(rightStick, equals(Offset.zero));

      controller.dispose();
    });
  });
}
