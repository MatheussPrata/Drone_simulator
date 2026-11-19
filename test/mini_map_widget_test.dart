import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:drone_simulator/models/flight_map.dart';
import 'package:drone_simulator/widgets/mini_map_widget.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';

void main() {
  group('Geographic Coordinates & FlightMap Conversion Tests', () {
    test('defaultHome está configurado em coordenada central padrão', () {
      expect(FlightMap.defaultHome.latitude, -23.5475);
      expect(FlightMap.defaultHome.longitude, -46.7230);
    });

    test('metersToLatLng converte (0,0) para a origem padrão', () {
      final pos = FlightMap.metersToLatLng(0.0, 0.0);
      expect(pos.latitude, closeTo(FlightMap.defaultHome.latitude, 0.000001));
      expect(pos.longitude, closeTo(FlightMap.defaultHome.longitude, 0.000001));
    });

    test('metersToLatLng desloca corretamente em metros para Norte (+Y) e Leste (+X)', () {
      final north100 = FlightMap.metersToLatLng(0.0, 100.0);
      expect(north100.latitude, greaterThan(FlightMap.defaultHome.latitude));
      expect(north100.longitude, closeTo(FlightMap.defaultHome.longitude, 0.00001));

      final east100 = FlightMap.metersToLatLng(100.0, 0.0);
      expect(east100.longitude, greaterThan(FlightMap.defaultHome.longitude));
      expect(east100.latitude, closeTo(FlightMap.defaultHome.latitude, 0.00001));
    });

    test('latLngToMeters e metersToLatLng são inversíveis (round-trip)', () {
      const startX = 120.0;
      const startY = -85.0;

      final latLng = FlightMap.metersToLatLng(startX, startY);
      final offset = FlightMap.latLngToMeters(latLng);

      expect(offset.dx, closeTo(startX, 0.05));
      expect(offset.dy, closeTo(startY, 0.05));
    });
  });

  group('MiniMapWidget Rendering & Control Tests', () {
    testWidgets('Compila e renderiza FlutterMap, TileLayer, CircleLayer e Markers sem erros', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: MiniMapWidget(
                droneX: 0.0,
                droneY: 0.0,
                droneZ: 0.0,
                yaw: 0.0,
                isSatellite: true,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(MiniMapWidget), findsOneWidget);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(TileLayer), findsOneWidget);
      expect(find.byType(CircleLayer), findsOneWidget);
      expect(find.byType(MarkerLayer), findsOneWidget);
      expect(find.text('H'), findsOneWidget); // Ponto de pouso Home
    });

    testWidgets('Alternar entre Satélite e Mapa de Ruas atualiza o TileLayer', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: MiniMapWidget(
                isSatellite: true,
                showControls: true,
              ),
            ),
          ),
        ),
      );

      // Encontra TileLayer inicial (satélite)
      TileLayer tileLayer = tester.widget(find.byType(TileLayer));
      expect(tileLayer.urlTemplate, contains('World_Imagery'));

      // Toca no botão de alternar mapa
      final toggleButton = find.byTooltip('Mudar para Mapa de Ruas');
      expect(toggleButton, findsOneWidget);
      await tester.tap(toggleButton);
      await tester.pump();

      // Agora deve exibir tiles do OpenStreetMap
      tileLayer = tester.widget(find.byType(TileLayer));
      expect(tileLayer.urlTemplate, contains('openstreetmap.org'));
    });

    testWidgets('MiniMapWidget responde a atualizações do SimulatorController', (tester) async {
      final controller = SimulatorController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: MiniMapWidget(
                controller: controller,
                followDrone: true,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      // Movimenta o drone pelo controller
      controller.setPosition(50.0, 75.0, 10.0);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(MiniMapWidget), findsOneWidget);

      controller.dispose();
    });
  });
}
