import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/simulation/flight_physics.dart';

void main() {
  group('Etapa 2 — Planta única de obstáculos e colisão sólida', () {
    test('WorldGenerator é determinístico e cobre os 3 cenários', () {
      final a = WorldGenerator.generateFor(FlightMap.dronePark);
      final b = WorldGenerator.generateFor(FlightMap.dronePark);
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].x, b[i].x);
        expect(a[i].y, b[i].y);
        expect(a[i].height, b[i].height);
      }

      expect(WorldGenerator.scenarioFor(FlightMap.dronePark), WorldScenario.urban);
      expect(WorldGenerator.scenarioFor(FlightMap.aeroclube), WorldScenario.forest);
      expect(WorldGenerator.scenarioFor(FlightMap.fpvArena), WorldScenario.canyon);

      expect(
        WorldGenerator.generateFor(FlightMap.dronePark)
            .where((o) => o.type == ObstacleType.building),
        isNotEmpty,
      );
      expect(
        WorldGenerator.generateFor(FlightMap.aeroclube)
            .where((o) => o.type == ObstacleType.building),
        isEmpty,
      );
      expect(
        WorldGenerator.generateFor(FlightMap.fpvArena)
            .where((o) => o.type == ObstacleType.dam),
        isNotEmpty,
      );
    });

    test('Obstáculos nunca ocupam o heliponto central nem passam dos 500m', () {
      for (final map in [
        FlightMap.dronePark,
        FlightMap.aeroclube,
        FlightMap.fpvArena,
      ]) {
        for (final o in WorldGenerator.generateFor(map)) {
          final dist = (o.x * o.x + o.y * o.y);
          expect(dist, greaterThan(8.0 * 8.0),
              reason: 'Obstáculo em cima do Home (${o.id})');
          expect(dist, lessThan(560.0 * 560.0),
              reason: 'Obstáculo fora do raio de voo (${o.id})');
        }
      }
    });

    test('Drone não atravessa a torre de rádio em voo baixo', () {
      final physics = FlightPhysics(initialMap: FlightMap.dronePark);
      final tower = WorldGenerator.generateFor(FlightMap.dronePark)
          .firstWhere((o) => o.type == ObstacleType.tower);

      physics.takeoff();
      // Posiciona 12m ao sul da torre, voando para o norte
      physics.syncExternal(
        east: tower.x,
        north: tower.y - 12.0,
        altitude: 10.0,
        heading: 0.0,
      );
      physics.setManualInput(0.0, 0.0, 1.0, 0.0);

      for (var i = 0; i < 300; i++) {
        physics.update(0.016);
      }

      // Deve parar antes de penetrar o cilindro da torre
      final dx = physics.eastMeters - tower.x;
      final dy = physics.northMeters - tower.y;
      final distance = (dx * dx + dy * dy);
      expect(distance, greaterThan(pow2(tower.radius + 0.55)),
          reason: 'O drone penetrou a torre');
    });

    test('Voo acima da torre passa livremente', () {
      final physics = FlightPhysics(initialMap: FlightMap.dronePark);
      final tower = WorldGenerator.generateFor(FlightMap.dronePark)
          .firstWhere((o) => o.type == ObstacleType.tower);

      physics.takeoff();
      physics.syncExternal(
        east: tower.x,
        north: tower.y - 12.0,
        altitude: tower.height + 5.0,
        heading: 0.0,
      );
      physics.setManualInput(0.0, 0.0, 1.0, 0.0);

      for (var i = 0; i < 300; i++) {
        physics.update(0.016);
      }

      expect(physics.northMeters, greaterThan(tower.y + 2.0));
    });

    test('Colisão em alta velocidade marca crashed e o drone cai ao solo', () {
      final physics = FlightPhysics(initialMap: FlightMap.dronePark);
      final tower = WorldGenerator.generateFor(FlightMap.dronePark)
          .firstWhere((o) => o.type == ObstacleType.tower);

      physics.takeoff();
      physics.syncExternal(
        east: tower.x,
        north: tower.y - 120.0,
        altitude: 10.0,
        heading: 0.0,
      );
      physics.setManualInput(0.0, 0.0, 1.0, 0.0);

      var crashed = false;
      for (var i = 0; i < 1500; i++) {
        physics.update(0.016);
        if (physics.state.isCrashed) {
          crashed = true;
          break;
        }
      }
      expect(crashed, true, reason: 'Impacto acima de 35 km/h deve derrubar');

      for (var i = 0; i < 800; i++) {
        physics.update(0.016);
        if (!physics.state.isCrashed) break;
      }
      expect(physics.state.altitude, 0.0);
      expect(physics.state.flightMode, FlightMode.disarmed);
    });

    test('Pouso suave sobre o telhado de um prédio é permitido', () {
      final physics = FlightPhysics(initialMap: FlightMap.dronePark);
      final building = WorldGenerator.generateFor(FlightMap.dronePark)
          .firstWhere((o) => o.type == ObstacleType.building && o.height < 60);

      physics.takeoff();
      physics.syncExternal(
        east: building.x,
        north: building.y,
        altitude: building.height + 12.0,
        heading: 0.0,
      );
      physics.setManualInput(-1.0, 0.0, 0.0, 0.0); // desce

      for (var i = 0; i < 400; i++) {
        physics.update(0.016);
        if (physics.state.altitude <= building.height + 0.01) break;
      }

      expect(physics.state.altitude, closeTo(building.height, 0.35),
          reason: 'O drone deve pousar no teto, não atravessar o prédio');
      expect(physics.state.isCrashed, false);
    });
  });
}

double pow2(double v) => v * v;
