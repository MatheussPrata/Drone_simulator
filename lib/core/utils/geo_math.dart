import 'dart:math';
import 'package:latlong2/latlong.dart';

class GeoMath {
  static const double _earthRadius = 6371000.0;

  /// Haversine distance in meters between two coordinates.
  static double distanceMeters(LatLng a, LatLng b) {
    final dLat = _toRad(b.latitude - a.latitude);
    final dLon = _toRad(b.longitude - a.longitude);
    final lat1 = _toRad(a.latitude);
    final lat2 = _toRad(b.latitude);

    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(h), sqrt(1 - h));
    return _earthRadius * c;
  }

  /// Bearing in degrees (0-360) from point a to point b.
  static double bearing(LatLng a, LatLng b) {
    final dLon = _toRad(b.longitude - a.longitude);
    final lat1 = _toRad(a.latitude);
    final lat2 = _toRad(b.latitude);

    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    final theta = atan2(y, x);
    return (_toDeg(theta) + 360) % 360;
  }

  /// Offset a LatLng by meters in North/South (dy) and East/West (dx).
  static LatLng offsetByMeters(LatLng origin, double dxMeters, double dyMeters) {
    final dLat = dyMeters / _earthRadius;
    final dLon = dxMeters / (_earthRadius * cos(_toRad(origin.latitude)));
    return LatLng(
      origin.latitude + _toDeg(dLat),
      origin.longitude + _toDeg(dLon),
    );
  }

  static double _toRad(double deg) => deg * pi / 180.0;
  static double _toDeg(double rad) => rad * 180.0 / pi;
}
