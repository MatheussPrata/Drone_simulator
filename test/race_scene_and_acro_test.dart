import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/models/flight_map.dart';
import 'package:drone_simulator/models/race_course.dart';
import 'package:drone_simulator/simulation/quadrotor_physics_6dof.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/simulation/world_generator.dart';

void main() {
  group('Correções de campo — mapa, portais e acro', () {
    test('Circuito serializa JSON válido para o Three.js', () {
      for (final map in FlightMap.predefinedTakeoffLocations) {
        final raw = RaceCourse.forMap(map).toJsonString();
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final gates = decoded['gates'] as List<dynamic>;
        expect(gates.length, 10);
        expect((gates.first as Map)['radius'], 4.5);
        expect(decoded['mapId'], map.id);
      }
    });

    test('Trocar local de decolagem muda cenário e obstáculos', () {
      final controller = SimulatorController();
      addTearDown(controller.dispose);

      controller.selectTakeoffLocation(FlightMap.dronePark);
      final urban = WorldGenerator.obstaclesJson(controller.activeMap);
      expect(urban.contains('"scenario":"urban"'), true);

      controller.selectTakeoffLocation(FlightMap.aeroclube);
      final forest = WorldGenerator.obstaclesJson(controller.activeMap);
      expect(controller.activeMap.id, 'parque_florestal');
      expect(forest.contains('"scenario":"forest"'), true);
      expect(forest.contains('"label":"Parque Florestal"'), true);
      expect(forest == urban, false);

      controller.selectTakeoffLocation(FlightMap.fpvArena);
      final canyon = WorldGenerator.obstaclesJson(controller.activeMap);
      expect(canyon.contains('"scenario":"canyon"'), true);
      expect(canyon.contains('"label":"Cânion & Represa"'), true);
    });

    test('Acro com stick cheio não completa um giro em 0,6s', () {
      final engine = QuadrotorPhysicsEngine();
      engine.reset(position: const Vec3(0, 0, 60));
      engine.setArmed(true);

      for (var i = 0; i < 144; i++) {
        engine.step(
          input: const PilotStickInput(pitch: 1.0, throttle: 0.0),
          dt: 1.0 / 240.0,
          mode: FlightControlMode.acro,
        );
      }

      final euler = engine.snapshot.orientation.toEulerRadians();
      final pitchDeg = euler.pitch.abs() * 180.0 / math.pi;
      expect(pitchDeg, greaterThan(25.0));
      expect(pitchDeg, lessThan(130.0),
          reason: 'Sem expo/taxa limitada o drone girava >180° em 0,6s');
    });
  });
}
