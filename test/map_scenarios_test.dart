import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/simulation/flight_physics.dart';

void main() {
  group('Etapa 4 — Cenários temáticos e recarga do 3D', () {
    test('Nomes exatos dos 3 mapas', () {
      expect(FlightMap.dronePark.name, 'Distrito Urbano');
      expect(FlightMap.aeroclube.name, 'Parque Florestal');
      expect(FlightMap.fpvArena.name, 'Cânion & Represa');
      expect(FlightMap.dronePark.id, 'distrito_urbano');
      expect(FlightMap.aeroclube.id, 'parque_florestal');
      expect(FlightMap.fpvArena.id, 'canion_represa');
    });

    test('Cada cenário gera geometria e tema distintos', () {
      final urban = WorldGenerator.generateFor(FlightMap.dronePark);
      final forest = WorldGenerator.generateFor(FlightMap.aeroclube);
      final canyon = WorldGenerator.generateFor(FlightMap.fpvArena);

      expect(urban.where((o) => o.type == ObstacleType.building), isNotEmpty);
      expect(forest.where((o) => o.type == ObstacleType.building), isEmpty);
      expect(forest.where((o) => o.type == ObstacleType.tree).length,
          greaterThan(urban.where((o) => o.type == ObstacleType.tree).length));

      expect(canyon.where((o) => o.type == ObstacleType.dam), isNotEmpty);
      expect(canyon.where((o) => o.type == ObstacleType.pillar).length, 6);
      expect(canyon.where((o) => o.type == ObstacleType.rock), isNotEmpty);

      final urbanTheme = WorldGenerator.themeFor(WorldScenario.urban);
      final canyonTheme = WorldGenerator.themeFor(WorldScenario.canyon);
      expect(urbanTheme['water'], false);
      expect(canyonTheme['water'], true);
      expect(urbanTheme['ground'], isNot(canyonTheme['ground']));
    });

    test('JSON enviado ao WebView carrega tema e obstáculos do mapa', () {
      for (final map in FlightMap.predefinedTakeoffLocations) {
        final payload = jsonDecode(WorldGenerator.obstaclesJson(map))
            as Map<String, dynamic>;
        expect(payload.containsKey('scenario'), true);
        expect(payload.containsKey('theme'), true);
        expect((payload['obstacles'] as List).isNotEmpty, true);
      }
    });

    test('Selecionar mapa troca obstáculos ativos da física', () {
      final physics = FlightPhysics(initialMap: FlightMap.dronePark);
      final urbanCount = physics.obstacles.length;

      physics.selectMap(FlightMap.fpvArena);
      expect(physics.obstacles.length, isNot(urbanCount));
      expect(
        physics.obstacles.any((o) => o.type == ObstacleType.dam),
        true,
      );
      expect(physics.activeMap.name, 'Cânion & Represa');
    });
  });
}
