import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/simulation/flight_physics.dart';
import 'package:drone_simulator/simulation/quadrotor_physics_6dof.dart';

void main() {
  group('Etapa 1 — Física de queda realista', () {
    test('Colisão a > 4 m/s entra em crashed, corta motores e cai girando',
        () {
      final controller = SimulatorController();
      addTearDown(controller.dispose);

      // Sem vento para garantir aproximação retilínea à torre.
      controller.sixDof.baseWindWorld = const Vec3(0, 0, 0);
      controller.sixDof.turbulenceIntensity = 0.0;

      final tower = WorldGenerator.generateFor(FlightMap.dronePark)
          .firstWhere((o) => o.type == ObstacleType.tower);

      controller.armAndTakeoff();
      for (var i = 0; i < 500; i++) {
        controller.update(0.016);
        if (controller.status == SimulatorStatus.hovering) break;
      }
      expect(controller.status, SimulatorStatus.hovering);

      // Posiciona 22 m ao sul da torre e acelera para o norte.
      controller.setPosition(tower.x, tower.y - 22.0, 10.0);
      controller.setManualInput(pitch: 1.0);

      var crashed = false;
      for (var i = 0; i < 600; i++) {
        controller.update(0.016);
        if (controller.status == SimulatorStatus.crashed) {
          crashed = true;
          break;
        }
      }

      expect(crashed, true, reason: 'Impacto acima de 3,5 m/s deve derrubar');
      expect(controller.isArmed, false, reason: 'Motores devem ser cortados');
      expect(controller.crashImpactSpeedKmh, greaterThan(14.0));
      expect(controller.lastCrashTimestamp, isNotNull);
      expect(
        controller.state.crashImpactSpeedKmh,
        controller.crashImpactSpeedKmh,
      );

      // Continua simulando a queda: não pode congelar.
      var landed = false;
      for (var i = 0; i < 900; i++) {
        controller.update(0.016);
        if (controller.z <= 0.0 && controller.status != SimulatorStatus.crashed) {
          landed = true;
          break;
        }
      }

      expect(landed, true, reason: 'O drone deve cair até o chão');
      expect(controller.z, 0.0);
      expect(controller.status, SimulatorStatus.landed);

      // Caiu girando: atitude final não está perfeitamente nivelada.
      final tilt = math.max(
        controller.pitchRad.abs(),
        controller.rollRad.abs(),
      );
      expect(tilt, greaterThan(0.05),
          reason: 'O drone deve permanecer tombado após a queda');
    });

    test('Queda desarmada quica no solo em vez de assentar reta', () {
      final engine = QuadrotorPhysicsEngine();
      engine.reset(position: const Vec3(0, 0, 8));
      engine.setArmed(false);

      engine.applyExternalCollisionCorrection(
        correctedPosition: const Vec3(0, 0, 8),
        correctedVelocity: const Vec3(0.4, 0, -8.0),
        angularImpulseBody: const Vec3(4.0, -3.0, 2.0),
      );

      var bounced = false;
      var minVz = 0.0;
      for (var i = 0; i < 2400; i++) {
        engine.step(input: PilotStickInput.neutral, dt: 1.0 / 240.0);
        final s = engine.snapshot;
        minVz = math.min(minVz, s.velocity.z);
        if (s.position.z < 1.0 && s.velocity.z > 0.1) {
          bounced = true;
          break;
        }
      }

      expect(minVz, lessThan(-1.5));
      expect(bounced, true, reason: 'Deve quicar ao tocar o solo');

      final snap = engine.snapshot;
      final euler = snap.orientation.toEulerRadians();
      final tilt = math.max(euler.pitch.abs(), euler.roll.abs());
      expect(tilt, greaterThan(0.02),
          reason: 'Deve manter o tombamento ao parar');
    });

    test('Impacto vertical forte no solo durante o voo dispara crashed', () {
      final controller = SimulatorController();
      addTearDown(controller.dispose);

      controller.armAndTakeoff();
      for (var i = 0; i < 500; i++) {
        controller.update(0.016);
        if (controller.status == SimulatorStatus.hovering) break;
      }

      // Coloca o drone a 12 m e força queda livre em modo acro.
      controller.setFlightMode(FlightControlMode.acro);
      controller.setPosition(0, 0, 12.0);
      controller.setManualInput(throttle: -1.0);

      var crashed = false;
      for (var i = 0; i < 400; i++) {
        controller.update(0.016);
        if (controller.status == SimulatorStatus.crashed) {
          crashed = true;
          break;
        }
      }

      expect(crashed, true);
      expect(controller.crashImpactSpeedKmh, greaterThan(0.0));
    });
  });
}
