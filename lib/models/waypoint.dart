import 'package:latlong2/latlong.dart';

class Waypoint {
  final int id;
  final LatLng position;
  final double targetAltitude;
  final double hoverSeconds;

  const Waypoint({
    required this.id,
    required this.position,
    this.targetAltitude = 30.0,
    this.hoverSeconds = 2.0,
  });

  Waypoint copyWith({
    int? id,
    LatLng? position,
    double? targetAltitude,
    double? hoverSeconds,
  }) {
    return Waypoint(
      id: id ?? this.id,
      position: position ?? this.position,
      targetAltitude: targetAltitude ?? this.targetAltitude,
      hoverSeconds: hoverSeconds ?? this.hoverSeconds,
    );
  }
}
