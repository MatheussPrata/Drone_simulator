import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/simulation/flight_physics.dart';

void main() {
  group('SimulatorController Tests', () {
    test('Initial state is landed with zero altitude and full battery', () {
      final controller = SimulatorController();
      expect(controller.status, SimulatorStatus.landed);
      expect(controller.isLanded, true);
      expect(controller.isArmed, false);
      expect(controller.x, 0.0);
      expect(controller.y, 0.0);
      expect(controller.z, 0.0);
      expect(controller.battery, 100.0);
    });

    test('Flow: Takeoff -> sobe automaticamente até z = 10m e estabiliza em hovering', () {
      final controller = SimulatorController();
      controller.armAndTakeoff();

      expect(controller.isArmed, true);
      expect(controller.status, SimulatorStatus.takingOff);

      // Simula subida até 10 metros (a 2.5 m/s, leva 4 segundos = 250 frames a dt 0.016)
      for (int i = 0; i < 300; i++) {
        controller.update(0.016);
        if (controller.status == SimulatorStatus.hovering) break;
      }

      // Deve atingir z = 10m e estabilizar em hovering
      expect(controller.z, closeTo(10.0, 0.3));
      expect(controller.status, SimulatorStatus.hovering);
      expect(controller.isHovering, true);
    });

    test('Flow: Complete Takeoff -> Move -> Trigger RTH -> Land to (0,0,0)', () {
      final controller = SimulatorController();

      // 1. Takeoff
      controller.armAndTakeoff();
      while (controller.status == SimulatorStatus.takingOff) {
        controller.update(0.016);
      }
      expect(controller.status, SimulatorStatus.hovering);
      expect(controller.z, closeTo(10.0, 0.3));

      // 2. Simula deslocamento para (30m, 40m) = 50m do centro
      controller.setPosition(30.0, 40.0);
      expect(controller.x, 30.0);
      expect(controller.y, 40.0);

      // 3. Dispara RTH
      controller.triggerRTH();
      expect(controller.status, SimulatorStatus.rth);
      expect(controller.isRTH, true);

      // 4. Executa frames de RTH até alcançar (0, 0) e iniciar pouso
      int maxFrames = 2500;
      int frames = 0;
      while (controller.status == SimulatorStatus.rth && frames < maxFrames) {
        controller.update(0.016);
        frames++;
      }

      // Ao chegar em (0, 0), deve transicionar para landing
      expect(controller.x, closeTo(0.0, 0.01));
      expect(controller.y, closeTo(0.0, 0.01));
      expect(controller.status, SimulatorStatus.landing);

      // 5. Continua descida até o pouso completo
      while (controller.status == SimulatorStatus.landing && frames < maxFrames) {
        controller.update(0.016);
        frames++;
      }

      // Pouso concluído com sucesso
      expect(controller.z, 0.0);
      expect(controller.status, SimulatorStatus.landed);
      expect(controller.isLanded, true);
      expect(controller.isArmed, false);
    });

    test('Automatic battery fail-safe triggers RTH when battery drops below 15%', () {
      final controller = SimulatorController();
      controller.armAndTakeoff();

      // Estabiliza em 10m
      while (controller.status == SimulatorStatus.takingOff) {
        controller.update(0.016);
      }
      expect(controller.status, SimulatorStatus.hovering);

      // Posiciona longe do centro
      controller.setPosition(50.0, 50.0);

      // Bateria cai para 14%
      controller.setBattery(14.0);

      // Deve disparar RTH automaticamente
      expect(controller.status, SimulatorStatus.rth);
      expect(controller.isRTH, true);
    });

    test('Reset restores all initial parameters', () {
      final controller = SimulatorController();
      controller.armAndTakeoff();
      controller.setPosition(100.0, 200.0, 15.0);
      controller.setBattery(50.0);

      controller.reset();

      expect(controller.status, SimulatorStatus.landed);
      expect(controller.x, 0.0);
      expect(controller.y, 0.0);
      expect(controller.z, 0.0);
      expect(controller.battery, 100.0);
      expect(controller.isArmed, false);
    });
  });
}
