import 'package:latlong2/latlong.dart';
import 'drone_profile.dart';

enum FlightMode { disarmed, hover, manual, autoMission, rtl, landing }

class DroneState {
  final LatLng position;
  final LatLng homePosition;
  final double altitude;
  final double speedKmh;
  final double verticalSpeedMs;
  final double heading;
  final double pitch;
  final double roll;
  final double batteryPercent;
  final double voltage;
  final FlightMode flightMode;
  final bool gpsLocked;
  final double windSpeedKmh;
  final double windDirectionDeg;
  final DroneProfile activeProfile;

  const DroneState({
    required this.position,
    required this.homePosition,
    this.altitude = 0.0,
    this.speedKmh = 0.0,
    this.verticalSpeedMs = 0.0,
    this.heading = 0.0,
    this.pitch = 0.0,
    this.roll = 0.0,
    this.batteryPercent = 100.0,
    this.voltage = 12.6,
    this.flightMode = FlightMode.disarmed,
    this.gpsLocked = true,
    this.windSpeedKmh = 0.0,
    this.windDirectionDeg = 0.0,
    required this.activeProfile,
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
    double? batteryPercent,
    double? voltage,
    FlightMode? flightMode,
    bool? gpsLocked,
    double? windSpeedKmh,
    double? windDirectionDeg,
    DroneProfile? activeProfile,
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
      batteryPercent: batteryPercent ?? this.batteryPercent,
      voltage: voltage ?? this.voltage,
      flightMode: flightMode ?? this.flightMode,
      gpsLocked: gpsLocked ?? this.gpsLocked,
      windSpeedKmh: windSpeedKmh ?? this.windSpeedKmh,
      windDirectionDeg: windDirectionDeg ?? this.windDirectionDeg,
      activeProfile: activeProfile ?? this.activeProfile,
    );
  }
}
