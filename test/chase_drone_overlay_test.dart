import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/models/drone_state.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/widgets/chase_drone_overlay.dart';

void main() {
  group('Etapa 4 - Criar o Drone Vetorial 3D em 3ª Pessoa (ChaseDroneOverlay)', () {
    testWidgets('Compila e renderiza de forma isolada com IgnorePointer ativo', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChaseDroneOverlay(
              altitude: 5.0,
              pitch: -5.0,
              roll: 10.0,
              flightMode: FlightMode.hover,
            ),
          ),
        ),
      );

      expect(find.byType(ChaseDroneOverlay), findsOneWidget);
      expect(find.byKey(const Key('chase_drone_overlay_pointer')), findsOneWidget);

      final ignorePointer = tester.widget<IgnorePointer>(
        find.byKey(const Key('chase_drone_overlay_pointer')),
      );
      expect(ignorePointer.ignoring, isTrue);
    });

    testWidgets('Integração com SimulatorController atualiza parâmetros dinamicamente', (tester) async {
      final controller = SimulatorController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChaseDroneOverlay(
              controller: controller,
            ),
          ),
        ),
      );

      expect(find.byType(ChaseDroneOverlay), findsOneWidget);

      // Decolar atualiza altitude e flightMode
      controller.armAndTakeoff();
      await tester.pump(const Duration(milliseconds: 50));

      expect(controller.isTakingOff || controller.isHovering, isTrue);
      expect(controller.state.flightMode, equals(FlightMode.hover));

      controller.dispose();
    });

    test('ChaseDronePainter: shouldRepaint detecta alterações de estado com precisão', () {
      final painter1 = ChaseDronePainter(
        altitude: 2.0,
        pitch: 0.0,
        roll: 0.0,
        flightMode: FlightMode.hover,
        speedKmh: 10.0,
        isGeofenceWarning: false,
        isNoFlyWarning: false,
        batteryPercent: 90.0,
      );

      final painterIdentical = ChaseDronePainter(
        altitude: 2.0,
        pitch: 0.0,
        roll: 0.0,
        flightMode: FlightMode.hover,
        speedKmh: 10.0,
        isGeofenceWarning: false,
        isNoFlyWarning: false,
        batteryPercent: 90.0,
      );

      final painterDiffAlt = ChaseDronePainter(
        altitude: 6.0,
        pitch: 0.0,
        roll: 0.0,
        flightMode: FlightMode.hover,
        speedKmh: 10.0,
        isGeofenceWarning: false,
        isNoFlyWarning: false,
        batteryPercent: 90.0,
      );

      final painterDiffPitch = ChaseDronePainter(
        altitude: 2.0,
        pitch: -10.0,
        roll: 0.0,
        flightMode: FlightMode.hover,
        speedKmh: 10.0,
        isGeofenceWarning: false,
        isNoFlyWarning: false,
        batteryPercent: 90.0,
      );

      final painterDiffRoll = ChaseDronePainter(
        altitude: 2.0,
        pitch: 0.0,
        roll: 15.0,
        flightMode: FlightMode.hover,
        speedKmh: 10.0,
        isGeofenceWarning: false,
        isNoFlyWarning: false,
        batteryPercent: 90.0,
      );

      final painterDiffMode = ChaseDronePainter(
        altitude: 2.0,
        pitch: 0.0,
        roll: 0.0,
        flightMode: FlightMode.rtl,
        speedKmh: 10.0,
        isGeofenceWarning: false,
        isNoFlyWarning: false,
        batteryPercent: 90.0,
      );

      final painterDiffWarning = ChaseDronePainter(
        altitude: 2.0,
        pitch: 0.0,
        roll: 0.0,
        flightMode: FlightMode.hover,
        speedKmh: 10.0,
        isGeofenceWarning: true,
        isNoFlyWarning: false,
        batteryPercent: 90.0,
      );

      expect(painter1.shouldRepaint(painterIdentical), isFalse);
      expect(painter1.shouldRepaint(painterDiffAlt), isTrue);
      expect(painter1.shouldRepaint(painterDiffPitch), isTrue);
      expect(painter1.shouldRepaint(painterDiffRoll), isTrue);
      expect(painter1.shouldRepaint(painterDiffMode), isTrue);
      expect(painter1.shouldRepaint(painterDiffWarning), isTrue);
    });

    testWidgets('Renderiza modos de voo distintos (Desarmado, Voo, RTL e Alertas) sem exceção', (tester) async {
      // 1. Desarmado
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChaseDroneOverlay(
              altitude: 0.0,
              flightMode: FlightMode.disarmed,
            ),
          ),
        ),
      );
      expect(find.byType(ChaseDroneOverlay), findsOneWidget);

      // 2. Voo armado / Pairado
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChaseDroneOverlay(
              altitude: 12.0,
              pitch: -15.0,
              roll: 5.0,
              flightMode: FlightMode.manual,
            ),
          ),
        ),
      );
      expect(find.byType(ChaseDroneOverlay), findsOneWidget);

      // 3. RTH (Return to Home)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChaseDroneOverlay(
              altitude: 25.0,
              flightMode: FlightMode.rtl,
            ),
          ),
        ),
      );
      expect(find.byType(ChaseDroneOverlay), findsOneWidget);

      // 4. Alerta de Bateria / Geofence
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChaseDroneOverlay(
              altitude: 8.0,
              flightMode: FlightMode.hover,
              isGeofenceWarning: true,
              batteryPercent: 12.0,
            ),
          ),
        ),
      );
      expect(find.byType(ChaseDroneOverlay), findsOneWidget);
    });

    testWidgets('Sombra do solo: desenha quando altitude < 15m e oculta quando altitude >= 15m', (tester) async {
      // Altitude baixa (0m) -> Sombra renderizada
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: ChaseDroneOverlay(
                altitude: 0.0,
                flightMode: FlightMode.hover,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ChaseDroneOverlay), findsOneWidget);

      // Altitude alta (25m) -> Sombra ultrapassa o limiar de 15m
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: ChaseDroneOverlay(
                altitude: 25.0,
                flightMode: FlightMode.hover,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ChaseDroneOverlay), findsOneWidget);
    });
  });
}
