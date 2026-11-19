import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'package:drone_simulator/core/utils/geo_math.dart';
import 'package:drone_simulator/models/flight_map.dart';

/// Resultado detalhado da avaliação de limites de geofence e zonas no-fly
class GeofenceValidationResult {
  final LatLng position;
  final double x; // metros a leste da origem (0,0)
  final double y; // metros ao norte da origem (0,0)
  final double distanceFromCenter;
  final double velocityX;
  final double velocityY;
  final bool isGeofenceWarning;
  final bool isGeofenceBreach;
  final bool inNoFlyZone;
  final bool isNoFlyWarning;
  final String? currentNfzName;
  final String? message;

  const GeofenceValidationResult({
    required this.position,
    required this.x,
    required this.y,
    required this.distanceFromCenter,
    required this.velocityX,
    required this.velocityY,
    required this.isGeofenceWarning,
    required this.isGeofenceBreach,
    required this.inNoFlyZone,
    required this.isNoFlyWarning,
    this.currentNfzName,
    this.message,
  });
}

/// Validador de Geofence e No-Fly Zones.
///
/// Avalia a cada tick se o drone ultrapassa o raio máximo (ex.: 500m a partir
/// da origem/centro), bloqueia o avanço radial para fora caso exceda,
/// e monitora a proximidade/entrada em Zonas Proibidas de Voo (No-Fly Zones).
class GeofenceValidator {
  static const double defaultMaxRadiusMeters = 500.0;
  static const double defaultWarningRadiusMeters = 400.0;

  /// Validação pura em coordenadas cartesianas (x, y) em metros relativas a (0, 0).
  ///
  /// Bloqueia o avanço radial para fora se r >= maxRadius e emite isGeofenceWarning.
  /// Detecta se (x, y) está dentro de alguma No-Fly Zone e emite isNoFlyWarning.
  static GeofenceValidationResult validateCartesian({
    required double x,
    required double y,
    double velocityX = 0.0,
    double velocityY = 0.0,
    double maxRadiusMeters = defaultMaxRadiusMeters,
    double warningRadiusMeters = defaultWarningRadiusMeters,
    List<NoFlyZone> noFlyZones = const [],
    LatLng? origin,
  }) {
    final double dist = sqrt(x * x + y * y);
    double clampedX = x;
    double clampedY = y;
    double clampedVx = velocityX;
    double clampedVy = velocityY;
    bool isWarning = false;
    bool isBreach = false;
    String? message;

    if (dist >= maxRadiusMeters) {
      isBreach = true;
      isWarning = true;
      message = 'Limite máximo de geofence (${maxRadiusMeters.toStringAsFixed(0)}m) atingido!';

      if (dist > 0) {
        final ux = x / dist;
        final uy = y / dist;

        // Reposiciona o drone exatamente na borda do geofence (500m)
        clampedX = ux * maxRadiusMeters;
        clampedY = uy * maxRadiusMeters;

        // Componente radial da velocidade: v_r = v . u_r
        final double radialVelocity = velocityX * ux + velocityY * uy;

        // Se a velocidade estiver apontando para FORA (radial > 0), bloqueia o avanço radial
        if (radialVelocity > 0) {
          // Remove a velocidade radial para fora, retendo apenas movimento tangencial/para dentro
          clampedVx = velocityX - radialVelocity * ux;
          clampedVy = velocityY - radialVelocity * uy;
        }
      }
    } else if (dist >= warningRadiusMeters) {
      isWarning = true;
      message = 'Aviso de aproximação do limite de geofence (${dist.toStringAsFixed(0)}m).';
    }

    final double finalDistance = sqrt(clampedX * clampedX + clampedY * clampedY);

    // Mapeia para LatLng se a origem geográfica for fornecida
    final LatLng finalPosition = origin != null
        ? GeoMath.offsetByMeters(origin, clampedX, clampedY)
        : const LatLng(0, 0);

    // Verificação de No-Fly Zones
    bool inNfz = false;
    String? nfzName;

    for (final nfz in noFlyZones) {
      double distToNfz;
      if (origin != null) {
        distToNfz = GeoMath.distanceMeters(finalPosition, nfz.center);
      } else {
        // Se sem coordenadas geográficas, assume nfz.center relativo a (0,0) via offset
        distToNfz = sqrt(pow(clampedX - nfz.center.longitude, 2) + pow(clampedY - nfz.center.latitude, 2));
      }

      if (distToNfz <= nfz.radiusMeters) {
        inNfz = true;
        nfzName = nfz.name;
        break;
      }
    }

    return GeofenceValidationResult(
      position: finalPosition,
      x: clampedX,
      y: clampedY,
      distanceFromCenter: finalDistance,
      velocityX: clampedVx,
      velocityY: clampedVy,
      isGeofenceWarning: isWarning,
      isGeofenceBreach: isBreach,
      inNoFlyZone: inNfz,
      isNoFlyWarning: inNfz,
      currentNfzName: nfzName,
      message: message,
    );
  }

  /// Validação geográfica completa integrada com os modelos de FlightMap
  static GeofenceValidationResult validate({
    required LatLng position,
    required FlightMap map,
    double velocityX = 0.0,
    double velocityY = 0.0,
    double altitude = 0.0,
  }) {
    final double distFromCenter = GeoMath.distanceMeters(position, map.center);
    final double bearingFromCenter = GeoMath.bearing(map.center, position);
    final double bearingRad = bearingFromCenter * pi / 180.0;

    // Converte posição para coordenadas relativas em metros
    final double x = sin(bearingRad) * distFromCenter;
    final double y = cos(bearingRad) * distFromCenter;

    final result = validateCartesian(
      x: x,
      y: y,
      velocityX: velocityX,
      velocityY: velocityY,
      maxRadiusMeters: map.radiusMeters,
      warningRadiusMeters: map.warningRadiusMeters,
      noFlyZones: map.noFlyZones,
      origin: map.center,
    );

    // Considera também aviso de teto de altitude se aplicável
    final bool altitudeWarning = altitude >= (map.maxAltitudeMeters - 15.0);
    final bool combinedWarning = result.isGeofenceWarning || altitudeWarning;

    return GeofenceValidationResult(
      position: result.position,
      x: result.x,
      y: result.y,
      distanceFromCenter: result.distanceFromCenter,
      velocityX: result.velocityX,
      velocityY: result.velocityY,
      isGeofenceWarning: combinedWarning,
      isGeofenceBreach: result.isGeofenceBreach,
      inNoFlyZone: result.inNoFlyZone,
      isNoFlyWarning: result.isNoFlyWarning,
      currentNfzName: result.currentNfzName,
      message: result.message,
    );
  }
}
