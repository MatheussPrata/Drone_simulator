import 'package:latlong2/latlong.dart';
import 'drone_profile.dart';
import 'flight_map.dart';

enum FlightMode { disarmed, hover, manual, autoMission, rtl, landing }

enum CameraViewMode { fpv, thirdPerson }

class DroneState {
  final LatLng position;
  final LatLng homePosition;
  final double altitude;
  final double speedKmh;
  final double verticalSpeedMs;
  final double heading;
  final double pitch;
  final double roll;
  final double gimbalPitch;
  final double visualPitch;
  final double visualRoll;
  final double batteryPercent;
  final double voltage;
  final FlightMode flightMode;
  final bool gpsLocked;
  final double windSpeedKmh;
  final double windDirectionDeg;
  final DroneProfile activeProfile;
  final FlightMap activeMap;
  final double distanceFromCenter;
  final bool isGeofenceWarning;
  final bool isGeofenceBreach;
  final bool inNoFlyZone;
  final bool isNoFlyWarning;
  final String? currentNfzName;
  final CameraViewMode cameraMode;

  const DroneState({
    required this.position,
    required this.homePosition,
    this.altitude = 0.0,
    this.speedKmh = 0.0,
    this.verticalSpeedMs = 0.0,
    this.heading = 0.0,
    this.pitch = 0.0,
    this.roll = 0.0,
    this.gimbalPitch = 0.0,
    this.visualPitch = 0.0,
    this.visualRoll = 0.0,
    this.batteryPercent = 100.0,
    this.voltage = 12.6,
    this.flightMode = FlightMode.disarmed,
    this.gpsLocked = true,
    this.windSpeedKmh = 0.0,
    this.windDirectionDeg = 0.0,
    required this.activeProfile,
    required this.activeMap,
    this.distanceFromCenter = 0.0,
    this.isGeofenceWarning = false,
    this.isGeofenceBreach = false,
    this.inNoFlyZone = false,
    this.isNoFlyWarning = false,
    this.currentNfzName,
    this.cameraMode = CameraViewMode.fpv,
  });

  DroneState copyWith({
    LatLng? position,
    LatLng? homePosition,
    double? altitude,
    double? speedKmh,
    double? verticalSpeedMs,
    double? heading,
    double? pitch,
    double? roll,
    double? gimbalPitch,
    double? visualPitch,
    double? visualRoll,
    double? batteryPercent,
    double? voltage,
    FlightMode? flightMode,
    bool? gpsLocked,
    double? windSpeedKmh,
    double? windDirectionDeg,
    DroneProfile? activeProfile,
    FlightMap? activeMap,
    double? distanceFromCenter,
    bool? isGeofenceWarning,
    bool? isGeofenceBreach,
    bool? inNoFlyZone,
    bool? isNoFlyWarning,
    String? currentNfzName,
    CameraViewMode? cameraMode,
  }) {
    return DroneState(
      position: position ?? this.position,
      homePosition: homePosition ?? this.homePosition,
      altitude: altitude ?? this.altitude,
      speedKmh: speedKmh ?? this.speedKmh,
      verticalSpeedMs: verticalSpeedMs ?? this.verticalSpeedMs,
      heading: heading ?? this.heading,
      pitch: pitch ?? this.pitch,
      roll: roll ?? this.roll,
      gimbalPitch: gimbalPitch ?? this.gimbalPitch,
      visualPitch: visualPitch ?? this.visualPitch,
      visualRoll: visualRoll ?? this.visualRoll,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      voltage: voltage ?? this.voltage,
      flightMode: flightMode ?? this.flightMode,
      gpsLocked: gpsLocked ?? this.gpsLocked,
      windSpeedKmh: windSpeedKmh ?? this.windSpeedKmh,
      windDirectionDeg: windDirectionDeg ?? this.windDirectionDeg,
      activeProfile: activeProfile ?? this.activeProfile,
      activeMap: activeMap ?? this.activeMap,
      distanceFromCenter: distanceFromCenter ?? this.distanceFromCenter,
      isGeofenceWarning: isGeofenceWarning ?? this.isGeofenceWarning,
      isGeofenceBreach: isGeofenceBreach ?? this.isGeofenceBreach,
      inNoFlyZone: inNoFlyZone ?? isNoFlyWarning ?? this.inNoFlyZone,
      isNoFlyWarning: isNoFlyWarning ?? inNoFlyZone ?? this.isNoFlyWarning,
      currentNfzName: currentNfzName ?? this.currentNfzName,
      cameraMode: cameraMode ?? this.cameraMode,
    );
  }
}
