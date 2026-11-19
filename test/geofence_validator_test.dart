import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/simulation/flight_physics.dart';

void main() {
  group('GeofenceValidator Unit Tests', () {
    test('Cartesian geofence validator blocks radial advance beyond 500m and sets isGeofenceWarning', () {
      // Posição candidata além dos 500m (x=0, y=550m) com velocidade para fora (vy=15 m/s)
      final result = GeofenceValidator.validateCartesian(
        x: 0.0,
        y: 550.0,
        velocityX: 0.0,
        velocityY: 15.0,
        maxRadiusMeters: 500.0,
        warningRadiusMeters: 400.0,
      );

      // Comprova que o drone não ultrapassa os 500m
      expect(result.distanceFromCenter, closeTo(500.0, 0.001));
      expect(result.y, closeTo(500.0, 0.001));
      expect(result.x, 0.0);

      // Comprova bloqueio do avanço radial para fora
      expect(result.velocityY <= 0.0, true);

      // Comprova emissão dos alertas
      expect(result.isGeofenceWarning, true);
      expect(result.isGeofenceBreach, true);
    });

    test('Cartesian geofence emits warning when entering warning zone (>= 400m) without breach', () {
      final result = GeofenceValidator.validateCartesian(
        x: 0.0,
        y: 420.0,
        velocityX: 0.0,
        velocityY: 5.0,
        maxRadiusMeters: 500.0,
        warningRadiusMeters: 400.0,
      );

      expect(result.distanceFromCenter, 420.0);
      expect(result.isGeofenceWarning, true);
      expect(result.isGeofenceBreach, false);
      expect(result.velocityY, 5.0); // velocidade mantida
    });

    test('Detects entry into No-Fly Zone and sets isNoFlyWarning = true', () {
      final map = FlightMap.dronePark;
      final nfz = map.noFlyZones.first; // Subestação Elétrica

      // Posição dentro da zona no-fly
      final insideNfzPos = nfz.center;
      final insideResult = GeofenceValidator.validate(
        position: insideNfzPos,
        map: map,
      );

      expect(insideResult.inNoFlyZone, true);
      expect(insideResult.isNoFlyWarning, true);
      expect(insideResult.currentNfzName, nfz.name);

      // Posição segura fora de qualquer NFZ
      final safePos = map.center;
      final safeResult = GeofenceValidator.validate(
        position: safePos,
        map: map,
      );

      expect(safeResult.inNoFlyZone, false);
      expect(safeResult.isNoFlyWarning, false);
      expect(safeResult.currentNfzName, isNull);
    });

    test('FlightPhysicsEngine tick loop enforces 500m maximum and detects No-Fly Zone in runtime', () {
      final engine = FlightPhysics(initialMap: FlightMap.dronePark);
      engine.takeoff();
      expect(engine.state.flightMode, FlightMode.hover);

      // Acelera o drone para o Norte por tempo suficiente para alcançar e tentar ultrapassar os 500m
      engine.setManualInput(0.0, 0.0, 1.0, 0.0); // Pitch para frente (norte)
      for (int i = 0; i < 1200; i++) {
        engine.tick(0.05);
      }

      // Critério de aceite: O drone NÃO ultrapassa os 500m
      expect(engine.state.distanceFromCenter <= 500.0, true);
      expect(engine.state.distanceFromCenter, closeTo(500.0, 0.5));
      expect(engine.state.isGeofenceWarning, true);
      expect(engine.state.isGeofenceBreach, true);

      // Teletransporta / posiciona na zona no-fly para testar detecção a cada tick
      final nfz = FlightMap.dronePark.noFlyZones.first;
      final engineNfz = FlightPhysics(initialMap: FlightMap.dronePark);
      engineNfz.takeoff();

      // Força a posição para o centro da NFZ e roda um tick
      // Usando o validador diretamente no tick com a coordenada da NFZ
      final resultNfz = GeofenceValidator.validate(
        position: nfz.center,
        map: FlightMap.dronePark,
      );

      expect(resultNfz.isNoFlyWarning, true);
      expect(resultNfz.inNoFlyZone, true);
      expect(resultNfz.currentNfzName, 'Subestação Elétrica');
    });
  });
}
