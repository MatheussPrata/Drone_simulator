import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:drone_simulator/core/utils/geo_math.dart';
import 'package:drone_simulator/models/waypoint.dart';

enum PoiType {
  gate,
  tower,
  obstacle,
  landingPad,
  windsock,
}

class MapPoi {
  final String id;
  final String name;
  final LatLng position;
  final PoiType type;
  final double altitudeMeters;
  final String? label;

  const MapPoi({
    required this.id,
    required this.name,
    required this.position,
    required this.type,
    this.altitudeMeters = 0.0,
    this.label,
  });
}

class NoFlyZone {
  final String id;
  final String name;
  final LatLng center;
  final double radiusMeters;
  final String reason;

  const NoFlyZone({
    required this.id,
    required this.name,
    required this.center,
    required this.radiusMeters,
    required this.reason,
  });
}

class PresetMission {
  final String id;
  final String name;
  final String description;
  final List<Waypoint> waypoints;

  const PresetMission({
    required this.id,
    required this.name,
    required this.description,
    required this.waypoints,
  });
}

class FlightMap {
  final String id;
  final String name;
  final String description;
  final LatLng center;
  final LatLng homePosition;
  final double radiusMeters;
  final double warningRadiusMeters;
  final double maxAltitudeMeters;
  final double initialZoom;
  final List<NoFlyZone> noFlyZones;
  final List<MapPoi> pois;
  final List<PresetMission> presetMissions;

  const FlightMap({
    required this.id,
    required this.name,
    required this.description,
    required this.center,
    required this.homePosition,
    this.radiusMeters = 500.0,
    this.warningRadiusMeters = 400.0,
    this.maxAltitudeMeters = 120.0,
    this.initialZoom = 16.5,
    this.noFlyZones = const [],
    this.pois = const [],
    this.presetMissions = const [],
  });

  LatLngBounds get bounds {
    final sw = GeoMath.offsetByMeters(center, -radiusMeters - 200, -radiusMeters - 200);
    final ne = GeoMath.offsetByMeters(center, radiusMeters + 200, radiusMeters + 200);
    return LatLngBounds(sw, ne);
  }

  // ────────────────────────────────────────────────────────────
  // Cenários modelados prontos com dimensões ideais de voo
  // ────────────────────────────────────────────────────────────

  /// 1. Drone Park (Campo de Treinamento Oficial - 500m de raio / 1 km²)
  static final FlightMap dronePark = () {
    const center = LatLng(-23.5475, -46.7230);
    final g1 = GeoMath.offsetByMeters(center, 0, 160);
    final g2 = GeoMath.offsetByMeters(center, 180, 0);
    final g3 = GeoMath.offsetByMeters(center, 0, -160);
    final g4 = GeoMath.offsetByMeters(center, -180, 0);
    final nfzCenter = GeoMath.offsetByMeters(center, 120, -280);
    final towerPos = GeoMath.offsetByMeters(center, -220, 180);
    final windsockPos = GeoMath.offsetByMeters(center, 40, 40);

    return FlightMap(
      id: 'drone_park',
      name: 'Drone Park (Campo Aberto)',
      description: 'Área aberta de 1 km² ideal para treino geral, acrobacias e missões autônomas.',
      center: center,
      homePosition: center,
      radiusMeters: 500.0,
      warningRadiusMeters: 400.0,
      maxAltitudeMeters: 120.0,
      initialZoom: 16.5,
      noFlyZones: [
        NoFlyZone(
          id: 'nfz_substation',
          name: 'Subestação Elétrica',
          center: nfzCenter,
          radiusMeters: 75.0,
          reason: 'Cabos de alta tensão e interferência de RF.',
        ),
      ],
      pois: [
        MapPoi(id: 'g1', name: 'Gate 1 (Norte)', position: g1, type: PoiType.gate, altitudeMeters: 15, label: 'G1'),
        MapPoi(id: 'g2', name: 'Gate 2 (Leste)', position: g2, type: PoiType.gate, altitudeMeters: 15, label: 'G2'),
        MapPoi(id: 'g3', name: 'Gate 3 (Sul)', position: g3, type: PoiType.gate, altitudeMeters: 15, label: 'G3'),
        MapPoi(id: 'g4', name: 'Gate 4 (Oeste)', position: g4, type: PoiType.gate, altitudeMeters: 15, label: 'G4'),
        MapPoi(id: 'tower', name: 'Torre de Rádio', position: towerPos, type: PoiType.tower, altitudeMeters: 45, label: 'Torre'),
        MapPoi(id: 'windsock', name: 'Biruta de Vento', position: windsockPos, type: PoiType.windsock, altitudeMeters: 5, label: 'Biruta'),
      ],
      presetMissions: [
        PresetMission(
          id: 'circuit_4gates',
          name: 'Circuito dos 4 Gates',
          description: 'Navegação sequencial pelos quatro portões de treinamento.',
          waypoints: [
            Waypoint(id: 1, position: g1, targetAltitude: 20.0, hoverSeconds: 2.0),
            Waypoint(id: 2, position: g2, targetAltitude: 20.0, hoverSeconds: 2.0),
            Waypoint(id: 3, position: g3, targetAltitude: 20.0, hoverSeconds: 2.0),
            Waypoint(id: 4, position: g4, targetAltitude: 20.0, hoverSeconds: 2.0),
            Waypoint(id: 5, position: center, targetAltitude: 5.0, hoverSeconds: 3.0),
          ],
        ),
        PresetMission(
          id: 'perimeter_scan',
          name: 'Varredura Perimetral 360°',
          description: 'Patrulha perimetral nos limites seguros da área autorizada.',
          waypoints: [
            Waypoint(id: 1, position: GeoMath.offsetByMeters(center, 0, 320), targetAltitude: 35.0, hoverSeconds: 1.5),
            Waypoint(id: 2, position: GeoMath.offsetByMeters(center, 280, 200), targetAltitude: 35.0, hoverSeconds: 1.5),
            Waypoint(id: 3, position: GeoMath.offsetByMeters(center, 280, -200), targetAltitude: 35.0, hoverSeconds: 1.5),
            Waypoint(id: 4, position: GeoMath.offsetByMeters(center, 0, -320), targetAltitude: 35.0, hoverSeconds: 1.5),
            Waypoint(id: 5, position: GeoMath.offsetByMeters(center, -280, -200), targetAltitude: 35.0, hoverSeconds: 1.5),
            Waypoint(id: 6, position: GeoMath.offsetByMeters(center, -280, 200), targetAltitude: 35.0, hoverSeconds: 1.5),
            Waypoint(id: 7, position: center, targetAltitude: 10.0, hoverSeconds: 2.0),
          ],
        ),
      ],
    );
  }();

  /// 2. Aeroclube & Pista (600m de raio / 1.4 km²)
  static final FlightMap aeroclube = () {
    const center = LatLng(-23.5080, -46.6380);
    final p1 = GeoMath.offsetByMeters(center, -300, 0);
    final p2 = GeoMath.offsetByMeters(center, 300, 0);
    final nfzRunway = GeoMath.offsetByMeters(center, 0, -350);

    return FlightMap(
      id: 'aeroclube',
      name: 'Aeroclube & Pistas',
      description: 'Pista estendida para testes de alta velocidade e trajetórias longas.',
      center: center,
      homePosition: center,
      radiusMeters: 600.0,
      warningRadiusMeters: 500.0,
      maxAltitudeMeters: 120.0,
      initialZoom: 16.0,
      noFlyZones: [
        NoFlyZone(
          id: 'nfz_commercial',
          name: 'Pista Comercial Ativa',
          center: nfzRunway,
          radiusMeters: 120.0,
          reason: 'Aproximação de aeronaves tripuladas.',
        ),
      ],
      pois: [
        MapPoi(id: 'rw_09', name: 'Cabeceira 09', position: p1, type: PoiType.landingPad, altitudeMeters: 0, label: '09'),
        MapPoi(id: 'rw_27', name: 'Cabeceira 27', position: p2, type: PoiType.landingPad, altitudeMeters: 0, label: '27'),
        MapPoi(id: 'hangar', name: 'Hangar Principal', position: GeoMath.offsetByMeters(center, 0, 150), type: PoiType.obstacle, altitudeMeters: 18, label: 'Hangar'),
      ],
      presetMissions: [
        PresetMission(
          id: 'runway_run',
          name: 'Voo Longitudinal da Pista',
          description: 'Passagem baixa pelas cabeceiras da pista de testes.',
          waypoints: [
            Waypoint(id: 1, position: p1, targetAltitude: 15.0, hoverSeconds: 2.0),
            Waypoint(id: 2, position: p2, targetAltitude: 15.0, hoverSeconds: 2.0),
            Waypoint(id: 3, position: center, targetAltitude: 8.0, hoverSeconds: 2.0),
          ],
        ),
      ],
    );
  }();

  /// 3. FPV Racing Arena (Raio de 300m - Circuito Compacto de Alta Velocidade)
  static final FlightMap fpvArena = () {
    const center = LatLng(-23.5420, -46.7150);
    final g1 = GeoMath.offsetByMeters(center, -80, 60);
    final g2 = GeoMath.offsetByMeters(center, 80, 70);
    final g3 = GeoMath.offsetByMeters(center, 120, -20);
    final g4 = GeoMath.offsetByMeters(center, 40, -90);
    final g5 = GeoMath.offsetByMeters(center, -60, -80);
    final g6 = GeoMath.offsetByMeters(center, -110, -10);

    return FlightMap(
      id: 'fpv_arena',
      name: 'FPV Racing Arena',
      description: 'Arena compacta de 300m com gates técnicos para treino ágil de drones FPV.',
      center: center,
      homePosition: center,
      radiusMeters: 300.0,
      warningRadiusMeters: 240.0,
      maxAltitudeMeters: 60.0,
      initialZoom: 17.5,
      pois: [
        MapPoi(id: 'g1', name: 'Gate 1', position: g1, type: PoiType.gate, altitudeMeters: 8, label: '1'),
        MapPoi(id: 'g2', name: 'Gate 2', position: g2, type: PoiType.gate, altitudeMeters: 8, label: '2'),
        MapPoi(id: 'g3', name: 'Gate 3', position: g3, type: PoiType.gate, altitudeMeters: 8, label: '3'),
        MapPoi(id: 'g4', name: 'Gate 4', position: g4, type: PoiType.gate, altitudeMeters: 8, label: '4'),
        MapPoi(id: 'g5', name: 'Gate 5', position: g5, type: PoiType.gate, altitudeMeters: 8, label: '5'),
        MapPoi(id: 'g6', name: 'Gate 6', position: g6, type: PoiType.gate, altitudeMeters: 8, label: '6'),
      ],
      presetMissions: [
        PresetMission(
          id: 'fpv_slalom',
          name: 'Circuito FPV 6-Gates',
          description: 'Traçado técnico completo de velocidade pelos 6 portões.',
          waypoints: [
            Waypoint(id: 1, position: g1, targetAltitude: 10.0, hoverSeconds: 0.5),
            Waypoint(id: 2, position: g2, targetAltitude: 10.0, hoverSeconds: 0.5),
            Waypoint(id: 3, position: g3, targetAltitude: 10.0, hoverSeconds: 0.5),
            Waypoint(id: 4, position: g4, targetAltitude: 10.0, hoverSeconds: 0.5),
            Waypoint(id: 5, position: g5, targetAltitude: 10.0, hoverSeconds: 0.5),
            Waypoint(id: 6, position: g6, targetAltitude: 10.0, hoverSeconds: 0.5),
            Waypoint(id: 7, position: center, targetAltitude: 4.0, hoverSeconds: 1.0),
          ],
        ),
      ],
    );
  }();

  static const List<FlightMap> all = []; // will be filled via getter

  static List<FlightMap> get availableMaps => [dronePark, aeroclube, fpvArena];
}
