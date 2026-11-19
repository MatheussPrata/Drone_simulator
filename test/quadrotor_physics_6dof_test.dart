import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/simulation/quadrotor_physics_6dof.dart';

void main() {
  const dt = 1.0 / 60.0;

  QuadrotorPhysicsEngine engineAt(double z) {
    final engine = QuadrotorPhysicsEngine(
      baseWindWorld: Vec3.zero,
      turbulenceIntensity: 0.0,
    );
    engine.reset(position: Vec3(0, 0, z));
    engine.setArmed(true);
    return engine;
  }

  group('QuadrotorPhysicsEngine 6-DOF', () {
    test('Hover no modo stabilized permanece estável por 3s (sem NaN)', () {
      final engine = engineAt(5.0);

      for (var i = 0; i < 180; i++) {
        engine.step(input: PilotStickInput.neutral, dt: dt);
      }

      final snap = engine.snapshot;
      expect(snap.position.z.isFinite, true);
      expect(snap.velocity.z.isFinite, true);
      expect(snap.position.z, closeTo(5.0, 0.8),
          reason: 'Altitude Hold deve manter o drone em torno de 5 m');
      expect(snap.speedKmh, lessThan(2.0));
      expect(snap.motorNormalizedRpm.length, 4);
      expect(snap.motorNormalizedRpm.every((m) => m.isFinite), true);
      expect(snap.motorNormalizedRpm.every((m) => m >= 0.0 && m <= 1.0), true);
    });

    test('Inércia e arrasto: desliza e desacelera suavemente após soltar', () {
      final engine = engineAt(10.0);
      engine.step(input: PilotStickInput.neutral, dt: dt);

      // Acelera com pitch = 1.0 por 1.5 s.
      for (var i = 0; i < 90; i++) {
        engine.step(
          input: const PilotStickInput(pitch: 1.0),
          dt: dt,
        );
      }
      final peakSpeed = engine.snapshot.speedKmh;
      expect(peakSpeed, greaterThan(5.0), reason: 'Deve ganhar velocidade');

      // Solta o stick: continua deslizando (não para instantaneamente).
      for (var i = 0; i < 6; i++) {
        engine.step(input: PilotStickInput.neutral, dt: dt);
      }
      final justAfter = engine.snapshot.speedKmh;
      expect(justAfter, greaterThan(peakSpeed * 0.4),
          reason: 'Inércia deve manter boa parte da velocidade');

      // E desacelera gradualmente.
      for (var i = 0; i < 120; i++) {
        engine.step(input: PilotStickInput.neutral, dt: dt);
      }
      final later = engine.snapshot.speedKmh;
      expect(later, lessThan(justAfter),
          reason: 'Arrasto deve reduzir a velocidade com o tempo');
    });

    test('Efeito solo: groundEffectFactor > 1.05 abaixo de 0.35m', () {
      final nearGround = engineAt(0.12);
      nearGround.step(input: PilotStickInput.neutral, dt: dt);
      expect(nearGround.snapshot.groundEffectFactor, greaterThan(1.05));
      expect(nearGround.snapshot.groundEffectFactor, lessThanOrEqualTo(1.38));

      final high = engineAt(20.0);
      high.step(input: PilotStickInput.neutral, dt: dt);
      expect(high.snapshot.groundEffectFactor, lessThan(1.01),
          reason: 'Longe do solo o efeito solo deve desaparecer');
    });

    test('Modo acro: throttle -1 faz a gravidade acelerar para baixo', () {
      final engine = engineAt(30.0);

      for (var i = 0; i < 60; i++) {
        engine.step(
          input: const PilotStickInput(throttle: -1.0),
          dt: dt,
          mode: FlightControlMode.acro,
        );
      }

      expect(engine.snapshot.velocity.z, lessThan(-1.0),
          reason: 'Motores em marcha lenta: gravidade domina');
      expect(engine.snapshot.position.z, lessThan(30.0));
    });

    test('Descarga de bateria é proporcional ao uso dos motores', () {
      final idle = engineAt(10.0);
      for (var i = 0; i < 300; i++) {
        idle.step(input: PilotStickInput.neutral, dt: dt);
      }

      final heavy = engineAt(40.0);
      for (var i = 0; i < 300; i++) {
        heavy.step(
          input: const PilotStickInput(throttle: 1.0),
          dt: dt,
          mode: FlightControlMode.acro,
        );
      }

      final idleDrop = 100.0 - idle.snapshot.batteryPercent;
      final heavyDrop = 100.0 - heavy.snapshot.batteryPercent;

      expect(idleDrop, greaterThan(0.0));
      expect(heavyDrop, greaterThan(idleDrop * 1.5),
          reason: 'Uso intenso dos motores deve consumir mais bateria');
      expect(heavyDrop, lessThan(100.0));
    });

    test('Sub-stepping 240 Hz mantém quatérnio normalizado em manobras agressivas',
        () {
      final engine = engineAt(40.0);

      for (var i = 0; i < 240; i++) {
        engine.step(
          input: const PilotStickInput(
            throttle: 0.6,
            roll: 1.0,
            pitch: 1.0,
            yaw: 0.4,
          ),
          dt: dt,
          mode: FlightControlMode.acro,
        );
      }

      final q = engine.snapshot.orientation;
      final norm = math.sqrt(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z);
      expect(norm, closeTo(1.0, 1e-6));
      expect(engine.snapshot.position.z.isFinite, true);
    });

    test('Correção externa de colisão aplica posição e velocidade corrigidas', () {
      final engine = engineAt(10.0);
      engine.step(
        input: const PilotStickInput(pitch: 1.0),
        dt: dt,
      );

      engine.applyExternalCollisionCorrection(
        correctedPosition: const Vec3(0.0, 4.8, 9.9),
        correctedVelocity: const Vec3(0.0, -1.2, 0.2),
        angularImpulseBody: const Vec3(0.6, -0.4, 0.1),
      );

      final snap = engine.snapshot;
      expect(snap.position.y, closeTo(4.8, 1e-9));
      expect(snap.velocity.y, closeTo(-1.2, 1e-9));
      expect(snap.angularVelocityBody.x, isNot(0.0));
      expect(snap.velocity.z.isFinite, true);
    });

    test('Reset restaura posição, bateria e zera os motores', () {
      final engine = engineAt(15.0);
      for (var i = 0; i < 60; i++) {
        engine.step(
          input: const PilotStickInput(throttle: 1.0, pitch: 0.5),
          dt: dt,
        );
      }

      engine.reset(position: const Vec3(1, 2, 3), batteryPercent: 80.0);
      final snap = engine.snapshot;
      expect(snap.position.z, 3.0);
      expect(snap.batteryPercent, 80.0);
      expect(snap.motorNormalizedRpm.every((m) => m < 0.2), true);
    });
  });
}
