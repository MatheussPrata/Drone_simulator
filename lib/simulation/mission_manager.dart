import 'dart:convert';
import 'dart:math' as math;

import 'package:drone_simulator/models/flight_map.dart';
import 'package:drone_simulator/models/world_obstacle.dart';
import 'package:drone_simulator/simulation/world_generator.dart';

/// Categorias de missão aérea jogáveis e autônomas.
enum MissionKind {
  waypointRoute,
  towerInspection,
  roofPrecisionLanding,
  noFlyPatrol,
}

/// Estado operacional de uma missão.
enum MissionStatus { ready, active, completed, failed }

/// Ponto de passagem ou pouso de precisão dentro de uma missão aérea.
class MissionCheckpoint {
  final int index;
  final String label;
  final double x;
  final double y;
  final double z;
  final double captureRadius;
  final double requiredHoverSec;
  final bool requireLanding;

  const MissionCheckpoint({
    required this.index,
    required this.label,
    required this.x,
    required this.y,
    required this.z,
    this.captureRadius = 6.5,
    this.requiredHoverSec = 0.0,
    this.requireLanding = false,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'label': label,
        'x': double.parse(x.toStringAsFixed(2)),
        'y': double.parse(y.toStringAsFixed(2)),
        'z': double.parse(z.toStringAsFixed(2)),
        'captureRadius': double.parse(captureRadius.toStringAsFixed(2)),
        'requiredHoverSec': double.parse(requiredHoverSec.toStringAsFixed(2)),
        'requireLanding': requireLanding,
      };
}

/// Definição determinística de uma missão aérea para determinado mapa.
class AerialMission {
  final String id;
  final String mapId;
  final String name;
  final String description;
  final MissionKind kind;
  final List<MissionCheckpoint> checkpoints;
  final bool forbidNoFlyZone;
  final bool supportsAutopilot;
  final double recommendedWindMultiplier;
  final double targetTimeSec;

  const AerialMission({
    required this.id,
    required this.mapId,
    required this.name,
    required this.description,
    required this.kind,
    required this.checkpoints,
    this.forbidNoFlyZone = false,
    this.supportsAutopilot = true,
    this.recommendedWindMultiplier = 1.0,
    this.targetTimeSec = 75.0,
  });

  String toJsonString({int activeIndex = 0, bool active = true}) => jsonEncode({
        'active': active,
        'id': id,
        'mapId': mapId,
        'name': name,
        'activeIndex': activeIndex,
        'checkpoints': checkpoints.map((c) => c.toJson()).toList(),
      });

  static final Map<String, List<AerialMission>> _cache = {};

  static List<AerialMission> forMap(FlightMap map) {
    final cached = _cache[map.id];
    if (cached != null) return cached;

    final obstacles = WorldGenerator.generateFor(map);
    final missions = <AerialMission>[];

    // 1. Converte as PresetMissions já definidas no FlightMap.
    for (final preset in map.presetMissions) {
      final cps = <MissionCheckpoint>[];
      for (var i = 0; i < preset.waypoints.length; i++) {
        final wp = preset.waypoints[i];
        final offset = FlightMap.latLngToMeters(wp.position, map.center);
        final safe = _safePositionAvoidingNfz(
          offset.dx,
          offset.dy,
          map,
          forbidNfz: preset.id == 'perimeter_scan',
        );
        final safeZ = _safeHeight(
          safe.$1,
          safe.$2,
          wp.targetAltitude.clamp(4.0, map.maxAltitudeMeters - 5.0),
          obstacles,
        );
        cps.add(MissionCheckpoint(
          index: i,
          label: 'WP ${i + 1}',
          x: safe.$1,
          y: safe.$2,
          z: safeZ,
          captureRadius: 7.0,
          requiredHoverSec: math.min(1.5, wp.hoverSeconds * 0.5),
        ));
      }
      missions.add(AerialMission(
        id: preset.id,
        mapId: map.id,
        name: preset.name,
        description: preset.description,
        kind: MissionKind.waypointRoute,
        checkpoints: cps,
        forbidNoFlyZone: preset.id == 'perimeter_scan',
        targetTimeSec: 60.0 + cps.length * 8.0,
      ));
    }

    // 2. Missão de Inspeção de Torre / Estrutura.
    missions.add(_buildTowerInspectionMission(map, obstacles));

    // 3. Missão de Pouso de Precisão em Telhado.
    missions.add(_buildRoofLandingMission(map));

    // 4. Patrulha Segura sem invadir No-Fly Zones.
    missions.add(_buildNoFlyPatrolMission(map, obstacles));

    final frozen = List<AerialMission>.unmodifiable(missions);
    _cache[map.id] = frozen;
    return frozen;
  }

  static AerialMission _buildTowerInspectionMission(
    FlightMap map,
    List<WorldObstacle> obstacles,
  ) {
    WorldObstacle? target;
    for (final o in obstacles) {
      if (o.type == ObstacleType.tower) {
        target = o;
        break;
      }
    }
    target ??= obstacles.firstWhere(
      (o) => o.id == 'pillar_2',
      orElse: () => obstacles.first,
    );

    final isTower = target.type == ObstacleType.tower;
    final orbitR = isTower ? 18.0 : 16.0;
    final orbitZ = (target.height * 0.72).clamp(12.0, 50.0);
    final topZ = (target.height + 6.0).clamp(14.0, 65.0);

    final rawPoints = <(String, double, double, double)>[
      ('Sul', target.x, target.y - orbitR, orbitZ),
      ('Leste', target.x + orbitR, target.y, orbitZ),
      ('Norte', target.x, target.y + orbitR, orbitZ),
      ('Oeste', target.x - orbitR, target.y, orbitZ),
      ('Topo', target.x, target.y, topZ),
    ];

    final cps = <MissionCheckpoint>[];
    for (var i = 0; i < rawPoints.length; i++) {
      final (dirLabel, px, py, pz) = rawPoints[i];
      final safeZ = _safeHeight(px, py, pz, obstacles, radius: 5.0);
      cps.add(MissionCheckpoint(
        index: i,
        label: 'Inspeção $dirLabel',
        x: px,
        y: py,
        z: safeZ,
        captureRadius: 7.5,
        requiredHoverSec: 1.0,
      ));
    }

    return AerialMission(
      id: 'tower_inspection',
      mapId: map.id,
      name: isTower ? 'Inspeção da Torre' : 'Inspeção da Ponte',
      description: isTower
          ? 'Orbitar a torre em 4 pontos cardeais e validar o topo.'
          : 'Inspecionar o pilar central da ponte sobre a represa.',
      kind: MissionKind.towerInspection,
      checkpoints: cps,
      forbidNoFlyZone: map.noFlyZones.isNotEmpty,
      targetTimeSec: 85.0,
    );
  }

  static AerialMission _buildRoofLandingMission(FlightMap map) {
    final obstacles = WorldGenerator.generateFor(map);
    WorldObstacle? roof;
    for (final o in obstacles) {
      if (o.type == ObstacleType.hangar) {
        roof = o;
        break;
      }
    }
    roof ??= obstacles.firstWhere(
      (o) => o.isWalkableRoof,
      orElse: () => const WorldObstacle(
        id: 'fallback_pad',
        type: ObstacleType.hangar,
        x: 0,
        y: 60,
        width: 14,
        depth: 14,
        height: 8,
      ),
    );

    final minSpan = roof.isCylindrical
        ? roof.radius * 1.4
        : math.min(roof.width, roof.depth);
    final padRadius = (minSpan * 0.48).clamp(4.0, 9.0);

    return AerialMission(
      id: 'roof_precision_landing',
      mapId: map.id,
      name: 'Pouso em Telhado',
      description:
          'Aproxime do galpão com vento lateral e pouse no centro do telhado.',
      kind: MissionKind.roofPrecisionLanding,
      forbidNoFlyZone: map.noFlyZones.isNotEmpty,
      recommendedWindMultiplier: 1.35,
      targetTimeSec: 65.0,
      checkpoints: [
        MissionCheckpoint(
          index: 0,
          label: 'Aproximação',
          x: roof.x,
          y: roof.y,
          z: roof.height + 10.0,
          captureRadius: 8.0,
          requiredHoverSec: 0.0,
        ),
        MissionCheckpoint(
          index: 1,
          label: 'Pouso no Telhado',
          x: roof.x,
          y: roof.y,
          z: roof.height,
          captureRadius: padRadius,
          requiredHoverSec: 0.0,
          requireLanding: true,
        ),
      ],
    );
  }

  static AerialMission _buildNoFlyPatrolMission(
    FlightMap map,
    List<WorldObstacle> obstacles,
  ) {
    final raw = <(String, double, double, double)>[
      ('Setor Norte', 0.0, 210.0, 28.0),
      ('Setor Leste', 210.0, 40.0, 32.0),
      ('Setor Sul-Oeste', -120.0, -220.0, 30.0),
      ('Setor Oeste', -210.0, 60.0, 26.0),
      ('Retorno Base', 0.0, 0.0, 14.0),
    ];

    final cps = <MissionCheckpoint>[];
    for (var i = 0; i < raw.length; i++) {
      final (label, rx, ry, rz) = raw[i];
      final safe = _safePositionAvoidingNfz(rx, ry, map, forbidNfz: true);
      final safeZ = _safeHeight(safe.$1, safe.$2, rz, obstacles, radius: 6.0);
      cps.add(MissionCheckpoint(
        index: i,
        label: label,
        x: safe.$1,
        y: safe.$2,
        z: safeZ,
        captureRadius: 7.5,
        requiredHoverSec: 0.5,
      ));
    }

    return AerialMission(
      id: 'nfz_safe_patrol',
      mapId: map.id,
      name: 'Patrulha Sem NFZ',
      description:
          'Cumprir a ronda pelos setores sem invadir nenhuma zona restrita.',
      kind: MissionKind.noFlyPatrol,
      forbidNoFlyZone: true,
      targetTimeSec: 90.0,
      checkpoints: cps,
    );
  }

  static (double, double) _safePositionAvoidingNfz(
    double x,
    double y,
    FlightMap map, {
    required bool forbidNfz,
  }) {
    if (!forbidNfz || map.noFlyZones.isEmpty) return (x, y);
    var px = x;
    var py = y;
    for (final nfz in map.noFlyZones) {
      final nfzMeters = FlightMap.latLngToMeters(nfz.center, map.center);
      final dx = px - nfzMeters.dx;
      final dy = py - nfzMeters.dy;
      final dist = math.sqrt(dx * dx + dy * dy);
      final minAllowed = nfz.radiusMeters + 25.0;
      if (dist < minAllowed) {
        final nx = dist > 1e-3 ? dx / dist : 0.0;
        final ny = dist > 1e-3 ? dy / dist : 1.0;
        px = nfzMeters.dx + nx * minAllowed;
        py = nfzMeters.dy + ny * minAllowed;
      }
    }
    final r = math.sqrt(px * px + py * py);
    final maxR = map.warningRadiusMeters - 20.0;
    if (r > maxR && r > 1e-3) {
      px = px * (maxR / r);
      py = py * (maxR / r);
    }
    return (px, py);
  }

  static double _safeHeight(
    double x,
    double y,
    double baseZ,
    List<WorldObstacle> obstacles, {
    double radius = 5.5,
  }) {
    var z = baseZ;
    for (final o in obstacles) {
      if (o.collidesAt(x, y, radius)) {
        final clearance = o.height + 4.0;
        if (clearance > z) z = clearance;
      }
    }
    return z;
  }
}

/// Controlador de progresso de missões aéreas (waypoints, hover, pouso e NFZ).
class MissionManager {
  final AerialMission mission;
  final void Function(int checkpointIndex, int total)? onCheckpointReached;
  final void Function(MissionManager manager)? onFinished;
  final void Function(MissionManager manager, String reason)? onFailed;

  MissionStatus status = MissionStatus.ready;
  int currentCheckpointIndex = 0;
  int checkpointsCompleted = 0;
  double elapsedSeconds = 0.0;
  double currentHoverProgressSec = 0.0;
  double score = 0.0;
  String? failureReason;
  bool autopilotEnabled = false;

  MissionManager({
    required this.mission,
    this.onCheckpointReached,
    this.onFinished,
    this.onFailed,
  });

  int get totalCheckpoints => mission.checkpoints.length;
  bool get isActive => status == MissionStatus.active;
  bool get isCompleted => status == MissionStatus.completed;
  bool get isFailed => status == MissionStatus.failed;

  MissionCheckpoint? get activeCheckpoint =>
      currentCheckpointIndex < mission.checkpoints.length
          ? mission.checkpoints[currentCheckpointIndex]
          : null;

  double get hoverProgressFraction {
    final cp = activeCheckpoint;
    if (cp == null || cp.requiredHoverSec <= 0.0) return 0.0;
    return (currentHoverProgressSec / cp.requiredHoverSec).clamp(0.0, 1.0);
  }

  double distanceToActiveCheckpoint(double x, double y, double z) {
    final cp = activeCheckpoint;
    if (cp == null) return 0.0;
    final dx = cp.x - x;
    final dy = cp.y - y;
    final dz = cp.z - z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  void start({bool autopilot = false}) {
    status = MissionStatus.active;
    currentCheckpointIndex = 0;
    checkpointsCompleted = 0;
    elapsedSeconds = 0.0;
    currentHoverProgressSec = 0.0;
    score = 0.0;
    failureReason = null;
    autopilotEnabled = autopilot && mission.supportsAutopilot;
  }

  void restart({bool? autopilot}) {
    start(autopilot: autopilot ?? autopilotEnabled);
  }

  void setAutopilot(bool enabled) {
    autopilotEnabled = enabled && mission.supportsAutopilot;
  }

  void update({
    required double dt,
    required double x,
    required double y,
    required double z,
    required bool isLanded,
    required bool isGrounded,
    required double groundHeightM,
    required bool crashed,
    required bool inNoFlyZone,
    required bool geofenceBreach,
  }) {
    if (status != MissionStatus.active) return;

    elapsedSeconds += dt;

    if (crashed) {
      _fail('Queda do drone durante a missão.');
      return;
    }

    if (mission.forbidNoFlyZone && inNoFlyZone) {
      _fail('Invasão de Zona de Exclusão Aérea (No-Fly Zone).');
      return;
    }

    if (mission.forbidNoFlyZone && geofenceBreach) {
      _fail('Violação do perímetro autorizado (Geofence).');
      return;
    }

    final cp = activeCheckpoint;
    if (cp == null) return;

    bool reached = false;
    if (cp.requireLanding) {
      final dx = x - cp.x;
      final dy = y - cp.y;
      final horizDist = math.sqrt(dx * dx + dy * dy);
      if (horizDist <= cp.captureRadius &&
          (isLanded || isGrounded) &&
          (z - cp.z).abs() <= 1.2 &&
          (groundHeightM - cp.z).abs() <= 1.2) {
        reached = true;
      }
    } else {
      final dist3d = distanceToActiveCheckpoint(x, y, z);
      if (dist3d <= cp.captureRadius) {
        if (cp.requiredHoverSec <= 0.0) {
          reached = true;
        } else {
          currentHoverProgressSec += dt;
          if (currentHoverProgressSec >= cp.requiredHoverSec) {
            reached = true;
          }
        }
      } else if (currentHoverProgressSec > 0.0) {
        currentHoverProgressSec =
            math.max(0.0, currentHoverProgressSec - dt * 1.5);
      }
    }

    if (!reached) return;

    score += cp.requireLanding ? 400.0 : 200.0;
    checkpointsCompleted++;
    final reachedIdx = currentCheckpointIndex;
    currentCheckpointIndex++;
    currentHoverProgressSec = 0.0;

    onCheckpointReached?.call(reachedIdx, totalCheckpoints);

    if (currentCheckpointIndex >= mission.checkpoints.length) {
      final timeBonus = math.max(0.0, mission.targetTimeSec - elapsedSeconds) * 5.0;
      score = (score + timeBonus).roundToDouble();
      status = MissionStatus.completed;
      autopilotEnabled = false;
      onFinished?.call(this);
    }
  }

  void _fail(String reason) {
    status = MissionStatus.failed;
    failureReason = reason;
    autopilotEnabled = false;
    onFailed?.call(this, reason);
  }
}
