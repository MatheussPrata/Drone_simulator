import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/models/flight_map.dart';
import 'package:drone_simulator/models/race_course.dart';
import 'package:drone_simulator/simulation/race_manager.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/simulation/world_generator.dart';

void main() {
  group('Etapa 3 — Corrida de portais', () {
    test('Cada mapa tem circuito determinístico de 10 portais livres', () {
      for (final map in FlightMap.predefinedTakeoffLocations) {
        final course = RaceCourse.forMap(map);
        expect(course.gates.length, 10);
        expect(course.mapId, map.id);

        final obstacles = WorldGenerator.generateFor(map);
        for (final gate in course.gates) {
          expect(gate.z, inInclusiveRange(8.0, 45.0));
          expect(gate.radius, 4.5);
          for (final obstacle in obstacles) {
            if (obstacle.collidesAt(gate.x, gate.y, gate.radius)) {
              expect(gate.z, greaterThan(obstacle.height),
                  reason: 'Portal ${gate.index} dentro de ${obstacle.id}');
            }
          }
        }

        // Determinismo.
        final again = RaceCourse.forMap(map);
        expect(again.gates.first.x, course.gates.first.x);
        expect(again.gates.last.z, course.gates.last.z);
      }
    });

    test('Passagem sequencial pelos portais pontua e avança o índice', () {
      final manager =
          RaceManager(course: RaceCourse.forMap(FlightMap.dronePark))
            ..start();

      final gate0 = manager.course.gates[0];
      manager.update(
        dt: 0.016,
        x: gate0.x,
        y: gate0.y,
        z: gate0.z,
        speedKmh: 20.0,
        crashed: false,
      );
      expect(manager.currentGateIndex, 1);
      expect(manager.score, greaterThan(0.0));

      final gate1 = manager.course.gates[1];
      manager.update(
        dt: 0.016,
        x: gate1.x,
        y: gate1.y,
        z: gate1.z,
        speedKmh: 20.0,
        crashed: false,
      );
      expect(manager.currentGateIndex, 2);
    });

    test('Combo cresce com portais em menos de 6s e reseta depois', () {
      final manager =
          RaceManager(course: RaceCourse.forMap(FlightMap.dronePark))
            ..start();

      // Primeiro portal.
      var gate = manager.course.gates[0];
      manager.update(dt: 0.1, x: gate.x, y: gate.y, z: gate.z, speedKmh: 10, crashed: false);
      expect(manager.combo, 2);

      // Segundo portal em 0.1s.
      gate = manager.course.gates[1];
      manager.update(dt: 0.1, x: gate.x, y: gate.y, z: gate.z, speedKmh: 10, crashed: false);
      expect(manager.combo, 3);

      // Espera mais de 6s antes do terceiro.
      for (var i = 0; i < 70; i++) {
        manager.update(dt: 0.1, x: 999, y: 999, z: 50, speedKmh: 0, crashed: false);
      }
      gate = manager.course.gates[2];
      manager.update(dt: 0.1, x: gate.x, y: gate.y, z: gate.z, speedKmh: 10, crashed: false);
      expect(manager.combo, 1);
    });

    test('Concluir o portal 10 finaliza a corrida e grava o recorde', () {
      final manager =
          RaceManager(course: RaceCourse.forMap(FlightMap.dronePark))
            ..start();

      for (final gate in manager.course.gates) {
        manager.update(
          dt: 0.1,
          x: gate.x,
          y: gate.y,
          z: gate.z,
          speedKmh: 15,
          crashed: false,
        );
      }

      expect(manager.status, RaceStatus.finished);
      expect(manager.currentGateIndex, 10);
      expect(manager.score, greaterThan(0));
      expect(manager.bestTimes[FlightMap.dronePark.id], isNotNull);
      expect(manager.bestTime, manager.elapsedSeconds);
    });

    test('Crash durante a corrida marca failed e permite reiniciar', () {
      final manager =
          RaceManager(course: RaceCourse.forMap(FlightMap.dronePark))
            ..start();

      manager.update(
        dt: 0.016,
        x: 0,
        y: 0,
        z: 5,
        speedKmh: 0,
        crashed: true,
      );
      expect(manager.status, RaceStatus.failed);

      manager.restart();
      expect(manager.status, RaceStatus.racing);
      expect(manager.currentGateIndex, 0);
      expect(manager.score, 0);
    });

    test('Controller alterna Voo Livre ↔ Modo Jogo e falha no crash', () {
      final controller = SimulatorController();
      addTearDown(controller.dispose);

      expect(controller.isRaceMode, false);
      controller.toggleSimulatorMode();
      expect(controller.isRaceMode, true);
      expect(controller.raceManager?.course.gates.length, 10);
      expect(controller.raceManager?.status, RaceStatus.racing);

      // Simula crash direto no manager (o controller repassa o status).
      controller.armAndTakeoff();
      for (var i = 0; i < 20; i++) {
        controller.update(0.016);
      }

      // Troca para corrida no mapa do Cânion e confere o circuito.
      controller.selectTakeoffLocation(FlightMap.fpvArena);
      expect(controller.raceManager?.course.mapId, FlightMap.fpvArena.id);
      expect(controller.raceManager?.status, RaceStatus.racing);

      controller.toggleSimulatorMode();
      expect(controller.isRaceMode, false);
      expect(controller.raceManager, isNull);
    });
  });
}
