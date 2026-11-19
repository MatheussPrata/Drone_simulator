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

    test('3 locais pré-definidos de decolagem em Paranavaí estão modelados corretamente', () {
      final locations = FlightMap.predefinedTakeoffLocations;
      expect(locations.length, 3);

      final centro = locations.firstWhere((l) => l.id == 'paranavai_centro');
      expect(centro.name, contains('Centro'));
      expect(centro.radiusMeters, 500.0);
      expect(centro.maxAltitudeMeters, 120.0);
      expect(centro.homePosition.latitude, closeTo(-23.0825, 0.001));

      final parque = locations.firstWhere((l) => l.id == 'paranavai_parque');
      expect(parque.name, contains('Parque'));
      expect(parque.radiusMeters, 500.0);
      expect(parque.homePosition.latitude, closeTo(-23.0760, 0.001));

      final represa = locations.firstWhere((l) => l.id == 'paranavai_represa');
      expect(represa.name, contains('Represa'));
      expect(represa.radiusMeters, 500.0);
      expect(represa.homePosition.latitude, closeTo(-23.0910, 0.001));
    });

    test('Critério de aceite: Selecionar local de decolagem redefine o ponto Home e reseta o voo', () {
      final controller = SimulatorController();

      // Inicia voo e desloca o drone
      controller.armAndTakeoff();
      controller.setPosition(50.0, 75.0, 15.0);
      expect(controller.x, equals(50.0));
      expect(controller.z, equals(15.0));
      expect(controller.isLanded, isFalse);

      // Seleciona Paranavaí - Centro
      final novoLocal = FlightMap.paranavaiCentro;
      controller.selectTakeoffLocation(novoLocal);

      // Verifica se o mapa ativo e Home foram redefinidos
      expect(controller.activeMap.id, equals('paranavai_centro'));
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

    testWidgets('MapSettingsModal exibe os 3 locais de Paranavaí e permite seleção', (tester) async {
      final controller = SimulatorController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapSettingsModal(controller: controller),
          ),
        ),
      );
      await tester.pump();

      // Verifica os 3 locais de decolagem
      expect(find.byKey(const Key('loc_paranavai_centro')), findsOneWidget);
      expect(find.byKey(const Key('loc_paranavai_parque')), findsOneWidget);
      expect(find.byKey(const Key('loc_paranavai_represa')), findsOneWidget);

      // Seleciona Parque / Área Verde
      await tester.tap(find.byKey(const Key('loc_paranavai_parque')));
      await tester.pump();

      expect(controller.activeMap.id, equals('paranavai_parque'));

      // Seleciona Represa / Lago
      await tester.tap(find.byKey(const Key('loc_paranavai_represa')));
      await tester.pump();

      expect(controller.activeMap.id, equals('paranavai_represa'));

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
