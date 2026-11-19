import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/simulation/flight_physics.dart';

void main() {
  group('Etapa 1 — Física realista com inércia e arrasto', () {
    test('Acelera com inclinação e desacelera progressivamente ao soltar o stick',
        () {
      final physics = FlightPhysics();
      physics.takeoff();

      // Empurra o stick direito para frente (nariz para baixo)
      physics.setManualInput(0.0, 0.0, 1.0, 0.0);
      for (int i = 0; i < 180; i++) {
        physics.update(0.016);
      }

      final speedAfterAccel = physics.state.speedKmh;
      expect(speedAfterAccel, greaterThan(1.0),
          reason: 'O velocímetro deve sair de 0 km/h ao acelerar');

      // Solta o stick: o arrasto deve reduzir a velocidade gradualmente
      physics.setManualInput(0.0, 0.0, 0.0, 0.0);
      // A atitude leva alguns frames para voltar ao nível (inércia real),
      // por isso medimos a desaceleração depois desse transiente.
      for (int i = 0; i < 30; i++) {
        physics.update(0.016);
      }
      final speedAfterRelease = physics.state.speedKmh;
      expect(speedAfterRelease, lessThan(speedAfterAccel),
          reason: 'Deve desacelerar com o arrasto após soltar o stick');

      // Depois de alguns segundos a velocidade residual deve ser baixa
      for (int i = 0; i < 400; i++) {
        physics.update(0.016);
      }
      expect(physics.state.speedKmh, lessThan(3.0),
          reason: 'Arrasto deve frear o drone até quase parar');

      // A distância percorrida mostra o deslize (inércia) antes de parar
      final traveled = sqrt(pow(physics.eastMeters, 2) + pow(physics.northMeters, 2));
      expect(traveled, greaterThan(5.0),
          reason: 'O drone deve deslizar alguns metros após soltar o stick');
    });

    test('Subida ganha inércia e o hover mantém altitude com micro-oscilação',
        () {
      final physics = FlightPhysics();
      physics.takeoff();

      final initialAltitude = physics.state.altitude;
      physics.setManualInput(1.0, 0.0, 0.0, 0.0);
      for (int i = 0; i < 60; i++) {
        physics.update(0.016);
      }
      expect(physics.state.altitude, greaterThan(initialAltitude));
      expect(physics.state.verticalSpeedMs, greaterThan(0.0));

      // Solta o throttle: a subida perde inércia e a altitude estabiliza
      physics.setManualInput(0.0, 0.0, 0.0, 0.0);
      for (int i = 0; i < 300; i++) {
        physics.update(0.016);
      }
      final settled = physics.state.altitude;
      for (int i = 0; i < 120; i++) {
        physics.update(0.016);
      }
      expect((physics.state.altitude - settled).abs(), lessThan(0.2),
          reason: 'No neutro o drone deve pairar em torno da altitude estável');
    });

    test('Alerta de geofence só aparece perto dos 450m (não a 17m)', () {
      final physics = FlightPhysics();
      physics.takeoff();
      physics.syncExternal(east: 17.0, north: 0.0, altitude: 10.0, heading: 0.0);
      physics.update(0.016);
      expect(physics.state.isGeofenceWarning, false,
          reason: 'A 17m do Home não pode haver alerta de geofence');

      physics.syncExternal(east: 460.0, north: 0.0, altitude: 10.0, heading: 0.0);
      physics.update(0.016);
      expect(physics.state.isGeofenceWarning, true,
          reason: 'A partir de 450m o aviso deve aparecer');
    });
  });
}
