import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/models/flight_map.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/widgets/map_settings_modal.dart';
import 'package:drone_simulator/widgets/minimap_pip.dart';
import 'package:drone_simulator/widgets/telemetry_hud.dart';

void main() {
  group('Etapa 3 - Seletor de Camada de Mapa e Locais de Voo', () {
    test('SimulatorController alterna camada de mapa entre Satélite e Ruas', () {
      final controller = SimulatorController();
      expect(controller.isSatellite, isTrue);

      // Alterna para Ruas
      controller.toggleTileLayer();
      expect(controller.isSatellite, isFalse);

      // Alterna de volta para Satélite
      controller.toggleTileLayer();
      expect(controller.isSatellite, isTrue);

      // Define explicitamente
      controller.setSatellite(false);
      expect(controller.isSatellite, isFalse);

      controller.setSatellite(true);
      expect(controller.isSatellite, isTrue);

      controller.dispose();
    });

    test('3 cenários temáticos estão modelados com nomes fiéis ao cenário 3D', () {
      final locations = FlightMap.predefinedTakeoffLocations;
      expect(locations.length, 3);

      expect(locations.map((l) => l.name).toList(),
          ['Distrito Urbano', 'Parque Florestal', 'Cânion & Represa']);

      final urbano = locations.firstWhere((l) => l.id == 'distrito_urbano');
      expect(urbano.name, 'Distrito Urbano');
      expect(urbano.radiusMeters, 500.0);
      expect(urbano.maxAltitudeMeters, 120.0);
      expect(urbano.noFlyZones.isNotEmpty, true);

      final floresta = locations.firstWhere((l) => l.id == 'parque_florestal');
      expect(floresta.name, 'Parque Florestal');
      expect(floresta.radiusMeters, 500.0);
      expect(floresta.noFlyZones, isEmpty);

      final canion = locations.firstWhere((l) => l.id == 'canion_represa');
      expect(canion.name, 'Cânion & Represa');
      expect(canion.radiusMeters, 500.0);
    });

    test('Nenhum mapa usa nome de cidade real', () {
      for (final map in FlightMap.predefinedTakeoffLocations) {
        expect(map.name.toLowerCase().contains('paranavaí'), false);
        expect(map.name.toLowerCase().contains('paranavai'), false);
        expect(map.name.toLowerCase().contains('são paulo'), false);
        expect(map.name.toLowerCase().contains('sao paulo'), false);
      }
    });

    test('Critério de aceite: Selecionar local de decolagem redefine o ponto Home e reseta o voo', () {
      final controller = SimulatorController();

      // Inicia voo e desloca o drone
      controller.armAndTakeoff();
      controller.setPosition(50.0, 75.0, 15.0);
      expect(controller.x, equals(50.0));
      expect(controller.z, equals(15.0));
      expect(controller.isLanded, isFalse);

      // Seleciona o Distrito Urbano
      final novoLocal = FlightMap.dronePark;
      controller.selectTakeoffLocation(novoLocal);

      // Verifica se o mapa ativo e Home foram redefinidos
      expect(controller.activeMap.id, equals('distrito_urbano'));
      expect(controller.activeMap.homePosition, equals(novoLocal.homePosition));

      // Verifica se o voo foi resetado para Home (0,0,0) e pousado
      expect(controller.x, equals(0.0));
      expect(controller.y, equals(0.0));
      expect(controller.z, equals(0.0));
      expect(controller.isLanded, isTrue);
      expect(controller.isArmed, isFalse);

      controller.dispose();
    });

    testWidgets('MapSettingsModal permite alternar entre Satélite e Ruas instantaneamente', (tester) async {
      final controller = SimulatorController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapSettingsModal(controller: controller),
          ),
        ),
      );
      await tester.pump();

      // Inicialmente em Satélite
      expect(find.byKey(const Key('btn_layer_satellite')), findsOneWidget);
      expect(find.byKey(const Key('btn_layer_streets')), findsOneWidget);
      expect(controller.isSatellite, isTrue);

      // Toca em Mapa de Ruas
      await tester.tap(find.byKey(const Key('btn_layer_streets')));
      await tester.pump();

      expect(controller.isSatellite, isFalse);

      // Toca em Satélite
      await tester.tap(find.byKey(const Key('btn_layer_satellite')));
      await tester.pump();

      expect(controller.isSatellite, isTrue);

      controller.dispose();
    });

    testWidgets('MapSettingsModal exibe os 3 cenários temáticos e permite seleção', (tester) async {
      final controller = SimulatorController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapSettingsModal(controller: controller),
          ),
        ),
      );
      await tester.pump();

      // Verifica os 3 cenários de decolagem
      expect(find.byKey(const Key('loc_distrito_urbano')), findsOneWidget);
      expect(find.byKey(const Key('loc_parque_florestal')), findsOneWidget);
      expect(find.byKey(const Key('loc_canion_represa')), findsOneWidget);

      expect(find.text('Distrito Urbano'), findsWidgets);
      expect(find.text('Parque Florestal'), findsWidgets);
      expect(find.text('Cânion & Represa'), findsWidgets);

      // Seleciona Parque Florestal
      await tester.tap(find.byKey(const Key('loc_parque_florestal')));
      await tester.pump();

      expect(controller.activeMap.id, equals('parque_florestal'));

      // Seleciona Cânion & Represa
      await tester.tap(find.byKey(const Key('loc_canion_represa')));
      await tester.pump();

      expect(controller.activeMap.id, equals('canion_represa'));

      controller.dispose();
    });

    testWidgets('TelemetryHud exibe botão discreto de camadas e abre o MapSettingsModal', (tester) async {
      final controller = SimulatorController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TelemetryHud(
              controller: controller,
              actionsPlacement: HudActionsPlacement.top,
            ),
          ),
        ),
      );
      await tester.pump();

      // Botão de Camadas na barra superior
      final btnFinder = find.byKey(const Key('btn_map_settings'));
      expect(btnFinder, findsOneWidget);
      expect(find.text('Camadas'), findsOneWidget);

      // Toca no botão de camadas para abrir o modal
      await tester.tap(btnFinder);
      await tester.pumpAndSettle();

      expect(find.byType(MapSettingsModal), findsOneWidget);
      expect(find.text('Camadas e Locais de Voo'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('MiniMapPip exibe botão discreto de camadas no canto do minimapa', (tester) async {
      final controller = SimulatorController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MiniMapPip(
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pump();

      // Botão discreto no canto superior esquerdo do minimapa
      final pipLayersFinder = find.byKey(const Key('pip_layers_button'));
      expect(pipLayersFinder, findsOneWidget);

      // Toca no botão de camadas do minimapa
      await tester.tap(pipLayersFinder);
      await tester.pumpAndSettle();

      expect(find.byType(MapSettingsModal), findsOneWidget);

      // Toca no botão de fechar do modal
      await tester.tap(find.byKey(const Key('modal_close_button')));
      await tester.pumpAndSettle();

      expect(find.byType(MapSettingsModal), findsNothing);

      controller.dispose();
    });
  });
}
