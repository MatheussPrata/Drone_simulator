import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/widgets/map_canvas.dart';
import 'package:drone_simulator/models/flight_map.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';

void main() {
  group('MapCanvas Widget & Layout Tests', () {
    testWidgets('Widget renderiza sem erros de layout em tela cheia (SizedBox.expand)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: MapCanvas(
                droneX: 0.0,
                droneY: 0.0,
                droneZ: 0.0,
                yaw: 0.0,
                pixelsPerMeter: 1.0,
                followDrone: true,
              ),
            ),
          ),
        ),
      );

      // Critério de aceite: sem qualquer erro ou exceção de layout
      expect(tester.takeException(), isNull);
      expect(find.byType(MapCanvas), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('MapCanvas renderiza com drone em altitude e rotação (sombra projetada e yaw)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: MapCanvas(
                droneX: 80.0,
                droneY: 120.0,
                droneZ: 25.0, // altitude que ativa a sombra
                yaw: 90.0,    // virado para o leste
                pixelsPerMeter: 1.2,
                followDrone: true,
                geofenceRadius: 500.0,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(MapCanvas), findsOneWidget);
    });

    testWidgets('MapCanvas renderiza zonas no-fly e mapa configurado em tela cheia', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: MapCanvas(
                droneX: 0.0,
                droneY: 0.0,
                droneZ: 10.0,
                yaw: 45.0,
                flightMap: FlightMap.dronePark,
                followDrone: false, // câmera fixa no centro (0,0)
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(MapCanvas), findsOneWidget);
    });

    testWidgets('MapCanvas reage a atualizações do SimulatorController', (tester) async {
      final controller = SimulatorController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: MapCanvas(
                controller: controller,
                followDrone: true,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      // Executa decolagem no controller
      controller.armAndTakeoff();
      for (int i = 0; i < 50; i++) {
        controller.update(0.016);
      }
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(controller.z > 0.0, true);

      controller.dispose();
    });
  });
}
