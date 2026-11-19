import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:drone_simulator/models/drone_state.dart';
import 'package:drone_simulator/models/drone_profile.dart';
import 'package:drone_simulator/models/waypoint.dart';
import 'package:drone_simulator/engine/flight_physics_engine.dart';

class SimulationNotifier extends StateNotifier<DroneState> {
  final FlightPhysicsEngine _engine;
  final List<Waypoint> _waypoints = [];
  int _nextWaypointId = 1;

  SimulationNotifier()
      : _engine = FlightPhysicsEngine(LatLng(-23.5505, -46.6333)),
        super(DroneState(
          position: LatLng(-23.5505, -46.6333),
          homePosition: LatLng(-23.5505, -46.6333),
          activeProfile: DroneProfile.mini249g,
        )) {
    _engine.onStateChanged = (newState) {
      if (mounted) {
        state = newState;
      }
    };
    _engine.start();
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  void takeoff() => _engine.takeoff();
  void land() => _engine.land();

  void startMission() {
    _engine.startMission(_waypoints);
  }

  void triggerRTL() => _engine.triggerRTL();

  void setManualInput(double throttle, double yaw, double pitch, double roll) {
    _engine.setManualInput(throttle, yaw, pitch, roll);
  }

  void overrideToManual() => _engine.overrideToManual();

  void addWaypoint(LatLng position) {
    _waypoints.add(Waypoint(
      id: _nextWaypointId++,
      position: position,
    ));
  }

  void clearWaypoints() {
    _waypoints.clear();
    _nextWaypointId = 1;
  }

  void setWindSpeed(double kmh) => _engine.setWindSpeed(kmh);
  void toggleGps() => _engine.toggleGps();
  void selectProfile(DroneProfile profile) => _engine.selectProfile(profile);

  void resetBatteryAndDrone() => _engine.resetBattery();

  List<Waypoint> get waypoints => List.unmodifiable(_waypoints);
}

final simulationProvider =
    StateNotifierProvider<SimulationNotifier, DroneState>((ref) {
  return SimulationNotifier();
});
