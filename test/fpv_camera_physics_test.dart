import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/simulation/flight_physics.dart';

void main() {
  group('FPV Camera & Gimbal Physics Tests (Etapa 2)', () {
    test('DroneState inicializa gimbalPitch, visualPitch e visualRoll com 0.0', () {
      final physics = FlightPhysics();
      expect(physics.state.gimbalPitch, 0.0);
      expect(physics.state.visualPitch, 0.0);
      expect(physics.state.visualRoll, 0.0);
      expect(physics.state.pitch, 0.0);
      expect(physics.state.roll, 0.0);
    });

    test('DroneState copyWith preserva e atualiza campos de câmera e atitude visual', () {
      final original = FlightPhysics().state;
      final updated = original.copyWith(
        gimbalPitch: -45.0,
        visualPitch: -15.5,
        visualRoll: 12.0,
      );

      expect(updated.gimbalPitch, -45.0);
      expect(updated.visualPitch, -15.5);
      expect(updated.visualRoll, 12.0);

      final cloned = updated.copyWith();
      expect(cloned.gimbalPitch, -45.0);
      expect(cloned.visualPitch, -15.5);
      expect(cloned.visualRoll, 12.0);
    });

    test(
        'Critério de aceite: ao empurrar o stick direito para frente, visualPitch inclina negativamente e retorna a zero ao soltar',
        () {
      final physics = FlightPhysics();

      // 1. Empurra o stick direito para frente (pitch manual = 1.0)
      physics.setManualInput(0.0, 0.0, 1.0, 0.0);

      // Simula alguns frames a 60 FPS (dt = 0.016s)
      for (int i = 0; i < 10; i++) {
        physics.update(0.016);
      }

      // Deve inclinar negativamente
      expect(physics.state.visualPitch, lessThan(0.0));
      expect(physics.visualPitch, lessThan(0.0));

      // Continua empurrando para frente até convergir próximo do limite (-25.0°)
      for (int i = 0; i < 30; i++) {
        physics.update(0.016);
      }
      expect(physics.state.visualPitch, closeTo(-25.0, 2.0));

      // 2. Solta o stick direito (pitch manual volta a 0.0)
      physics.setManualInput(0.0, 0.0, 0.0, 0.0);

      // Suavização (lerp) reduz a inclinação progressivamente em direção a 0.0
      physics.update(0.016);
      final intermediatePitch = physics.state.visualPitch;
      expect(intermediatePitch, greaterThan(-25.0)); // Começou a retornar

      // Avança frames suficientes para auto-nivelamento completo
      for (int i = 0; i < 60; i++) {
        physics.update(0.016);
      }

      // Retorna exatamente a 0.0 (auto-nivelamento)
      expect(physics.state.visualPitch, 0.0);
      expect(physics.visualPitch, 0.0);
    });

    test('visualPitch e visualRoll reagem de forma análoga em voo ativo (após takeoff)', () {
      final physics = FlightPhysics();
      physics.takeoff();
      expect(physics.state.flightMode, FlightMode.hover);

      // Move stick para a frente e direita
      physics.setManualInput(0.0, 0.0, 1.0, 1.0);
      for (int i = 0; i < 20; i++) {
        physics.update(0.016);
      }

      expect(physics.state.visualPitch, lessThan(0.0));
      expect(physics.state.visualRoll, greaterThan(0.0));
      // pitch e roll em DroneState espelham visualPitch e visualRoll
      expect(physics.state.pitch, physics.state.visualPitch);
      expect(physics.state.roll, physics.state.visualRoll);

      // Solta ambos os sticks
      physics.setManualInput(0.0, 0.0, 0.0, 0.0);
      for (int i = 0; i < 60; i++) {
        physics.update(0.016);
      }

      expect(physics.state.visualPitch, 0.0);
      expect(physics.state.visualRoll, 0.0);
      expect(physics.state.pitch, 0.0);
      expect(physics.state.roll, 0.0);
    });

    test('visualRoll inclina negativamente ao mover stick para a esquerda e auto-nivela a zero', () {
      final physics = FlightPhysics();

      // Stick esquerdo/roll lateral negativo (-1.0)
      physics.setManualInput(0.0, 0.0, 0.0, -1.0);
      for (int i = 0; i < 20; i++) {
        physics.update(0.016);
      }
      expect(physics.state.visualRoll, lessThan(0.0));

      // Solta o stick
      physics.setManualInput(0.0, 0.0, 0.0, 0.0);
      for (int i = 0; i < 60; i++) {
        physics.update(0.016);
      }
      expect(physics.state.visualRoll, 0.0);
    });

    test('gimbalPitch é controlado e limitado estritamente entre 0.0° e -90.0°', () {
      final physics = FlightPhysics();

      // Inicial: 0.0 (olhando para o horizonte)
      expect(physics.gimbalPitch, 0.0);
      expect(physics.state.gimbalPitch, 0.0);

      // Ajusta para -45.0°
      physics.setGimbalPitch(-45.0);
      expect(physics.gimbalPitch, -45.0);
      expect(physics.state.gimbalPitch, -45.0);

      // Ajusta para -90.0° (olhando reto para o chão)
      physics.setGimbalPitch(-90.0);
      expect(physics.gimbalPitch, -90.0);
      expect(physics.state.gimbalPitch, -90.0);

      // Clamping inferior: valores menores que -90.0° são limitados a -90.0°
      physics.setGimbalPitch(-120.0);
      expect(physics.gimbalPitch, -90.0);
      expect(physics.state.gimbalPitch, -90.0);

      // Clamping superior: valores maiores que 0.0° são limitados a 0.0°
      physics.setGimbalPitch(30.0);
      expect(physics.gimbalPitch, 0.0);
      expect(physics.state.gimbalPitch, 0.0);

      // Teste incremental adjustGimbalPitch
      physics.adjustGimbalPitch(-30.0);
      expect(physics.gimbalPitch, -30.0);
      physics.adjustGimbalPitch(-40.0);
      expect(physics.gimbalPitch, -70.0);
      physics.adjustGimbalPitch(-50.0); // Ultrapassa -90 -> trava em -90
      expect(physics.gimbalPitch, -90.0);
      physics.adjustGimbalPitch(150.0); // Ultrapassa 0 -> trava em 0
      expect(physics.gimbalPitch, 0.0);
    });

    test('SimulatorController integra e sincroniza gimbalPitch, visualPitch e visualRoll', () {
      final controller = SimulatorController();

      expect(controller.gimbalPitch, 0.0);
      expect(controller.visualPitch, 0.0);
      expect(controller.visualRoll, 0.0);

      // Controle de gimbal via controller
      controller.setGimbalPitch(-60.0);
      expect(controller.gimbalPitch, -60.0);
      expect(controller.physics.state.gimbalPitch, -60.0);

      // Controle incremental de gimbal via controller
      controller.adjustGimbalPitch(-50.0);
      expect(controller.gimbalPitch, -90.0); // clamped

      // Empurra stick de pitch via controller
      controller.setManualInput(pitch: 1.0);
      for (int i = 0; i < 15; i++) {
        controller.update(0.016);
      }
      expect(controller.visualPitch, lessThan(0.0));

      // Solta stick e valida auto-nivelamento via controller
      controller.setManualInput(pitch: 0.0);
      for (int i = 0; i < 60; i++) {
        controller.update(0.016);
      }
      expect(controller.visualPitch, 0.0);
    });
  });
}
