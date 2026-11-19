import 'package:flutter_test/flutter_test.dart';
import 'package:drone_simulator/models/flight_map.dart';
import 'package:drone_simulator/core/utils/geo_math.dart';
import 'package:drone_simulator/engine/flight_physics_engine.dart';
import 'package:drone_simulator/models/drone_state.dart';

void main() {
  group('FlightMap Modeling Tests', () {
    test('Drone Park default map has optimal 500m radius and 120m altitude ceiling', () {
      final map = FlightMap.dronePark;
      expect(map.radiusMeters, 500.0);
      expect(map.warningRadiusMeters, 400.0);
      expect(map.maxAltitudeMeters, 120.0);
      expect(map.pois.isNotEmpty, true);
      expect(map.noFlyZones.isNotEmpty, true);
      expect(map.presetMissions.isNotEmpty, true);

      // Verify bounds encompass center with safety margin
      final bounds = map.bounds;
      expect(bounds.north > map.center.latitude, true);
      expect(bounds.south < map.center.latitude, true);
      expect(bounds.east > map.center.longitude, true);
      expect(bounds.west < map.center.longitude, true);
    });

    test('Available maps list contains all three modeled arenas', () {
      final maps = FlightMap.availableMaps;
      expect(maps.length, 3);
      expect(maps.any((m) => m.id == 'drone_park'), true);
      expect(maps.any((m) => m.id == 'aeroclube'), true);
      expect(maps.any((m) => m.id == 'fpv_arena'), true);
    });

    test('FPV Arena is modeled as a compact fast-paced arena (300m)', () {
      final arena = FlightMap.fpvArena;
      expect(arena.radiusMeters, 300.0);
      expect(arena.maxAltitudeMeters, 60.0);
      expect(arena.pois.length, 6); // 6 gates
    });

    test('Physics engine enforces Geofence and altitude ceiling of active map', () {
      final engine = FlightPhysicsEngine(initialMap: FlightMap.dronePark);
      expect(engine.state.activeMap.id, 'drone_park');
      expect(engine.state.altitude, 0.0);
      expect(engine.state.isGeofenceBreach, false);

      // Takeoff
      engine.takeoff();
      expect(engine.state.flightMode, FlightMode.hover);
      expect(engine.state.altitude, 2.0);

      // Select another map
      engine.selectMap(FlightMap.fpvArena);
      expect(engine.state.activeMap.id, 'fpv_arena');
      expect(engine.state.activeMap.radiusMeters, 300.0);
    });

    test('GeoMath calculations for map scale are accurate', () {
      final center = FlightMap.dronePark.center;
      final northPoint = GeoMath.offsetByMeters(center, 0, 500);
      final dist = GeoMath.distanceMeters(center, northPoint);
      expect(dist, closeTo(500.0, 1.0));

      final bearing = GeoMath.bearing(center, northPoint);
      expect(bearing, closeTo(0.0, 1.0)); // North = 0 deg
    });
  });
}
