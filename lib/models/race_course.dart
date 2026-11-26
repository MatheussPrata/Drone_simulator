import 'dart:convert';
import 'dart:math' as math;

import 'package:drone_simulator/models/flight_map.dart';
import 'package:drone_simulator/models/world_obstacle.dart';
import 'package:drone_simulator/simulation/world_generator.dart';

/// Portal (anel) de um circuito de corrida.
class RaceGate {
  final int index;

  /// Centro do portal em metros (x = leste, y = norte).
  final double x;
  final double y;

  /// Altura do centro do portal (m).
  final double z;

  /// Orientação do portal em graus (0 = virado para o norte).
  final double yawDeg;

  /// Raio de detecção/passagem (m).
  final double radius;

  const RaceGate({
    required this.index,
    required this.x,
    required this.y,
    required this.z,
    required this.yawDeg,
    this.radius = 4.5,
  });

  /// Normal unitária horizontal do plano do portal (convenção ENU: 0° = Norte +Y, 90° = Leste +X).
  (double nx, double ny) get planeNormal {
    final rad = yawDeg * math.pi / 180.0;
    return (math.sin(rad), math.cos(rad));
  }

  /// Distância com sinal do ponto ([px], [py]) ao plano vertical do portal.
  double signedPlaneDistance(double px, double py) {
    final (nx, ny) = planeNormal;
    return (px - x) * nx + (py - y) * ny;
  }

  /// Distância radial dentro do plano do portal até o centro do anel.
  double inPlaneRadius(double px, double py, double pz) {
    final (nx, ny) = planeNormal;
    final rx = px - x;
    final ry = py - y;
    final rz = pz - z;
    final tangential = rx * ny - ry * nx;
    return math.sqrt(tangential * tangential + rz * rz);
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'x': double.parse(x.toStringAsFixed(2)),
        'y': double.parse(y.toStringAsFixed(2)),
        'z': double.parse(z.toStringAsFixed(2)),
        'yaw': double.parse(yawDeg.toStringAsFixed(1)),
        'radius': radius,
      };
}

/// Nível de dificuldade do circuito de corrida.
enum CourseDifficulty { easy, medium, pro }

/// Direção do circuito de corrida.
enum CourseDirection { standard, reverse }

/// Circuito determinístico de 10 portais para cada cenário.
class RaceCourse {
  final String mapId;
  final String name;
  final List<RaceGate> gates;
  final CourseDifficulty difficulty;
  final CourseDirection direction;

  const RaceCourse({
    required this.mapId,
    required this.name,
    required this.gates,
    this.difficulty = CourseDifficulty.medium,
    this.direction = CourseDirection.standard,
  });

  String get variantKey => '${difficulty.name}_${direction.name}';

  String get displayName {
    if (difficulty == CourseDifficulty.medium &&
        direction == CourseDirection.standard) {
      return name;
    }
    final parts = <String>[name];
    if (direction == CourseDirection.reverse) {
      parts.add('Reverso');
    }
    if (difficulty == CourseDifficulty.easy) {
      parts.add('Fácil');
    } else if (difficulty == CourseDifficulty.pro) {
      parts.add('Pro');
    }
    return parts.join(' · ');
  }

  static final Map<String, RaceCourse> _cache = {};

  /// Circuito do mapa, com portais livres de obstáculos e alturas de 8m a 45m.
  static RaceCourse forMap(
    FlightMap map, {
    CourseDifficulty difficulty = CourseDifficulty.medium,
    CourseDirection direction = CourseDirection.standard,
  }) {
    final key = '${map.id}:${difficulty.name}:${direction.name}';
    final cached = _cache[key];
    if (cached != null) return cached;

    final obstacles = WorldGenerator.generateFor(map);
    final scenario = WorldGenerator.scenarioFor(map);
    final course = switch (scenario) {
      WorldScenario.urban =>
        _urban(map.id, obstacles, difficulty: difficulty, direction: direction),
      WorldScenario.forest =>
        _forest(map.id, obstacles, difficulty: difficulty, direction: direction),
      WorldScenario.canyon =>
        _canyon(map.id, obstacles, difficulty: difficulty, direction: direction),
    };
    _cache[key] = course;
    return course;
  }

  // ── Distrito Urbano: cruzamento das avenidas, alturas crescentes ──
  static RaceCourse _urban(
    String mapId,
    List<WorldObstacle> obstacles, {
    required CourseDifficulty difficulty,
    required CourseDirection direction,
  }) {
    final baseCandidates = <(double, double, double)>[
      (0, 70, 12),
      (0, 130, 18),
      (0, 190, 26),
      (0, 250, 34),
      (70, 250, 40),
      (140, 250, 45),
      (140, 180, 38),
      (140, 110, 30),
      (70, 55, 22),
      (0, 20, 14),
    ];
    return RaceCourse(
      mapId: mapId,
      name: 'Circuito do Distrito',
      difficulty: difficulty,
      direction: direction,
      gates: _buildVariantGates(
        baseCandidates,
        obstacles,
        difficulty: difficulty,
        direction: direction,
      ),
    );
  }

  // ── Parque Florestal: zigue-zague sobre as trilhas ──
  static RaceCourse _forest(
    String mapId,
    List<WorldObstacle> obstacles, {
    required CourseDifficulty difficulty,
    required CourseDirection direction,
  }) {
    final baseCandidates = <(double, double, double)>[
      (0, 60, 10),
      (60, 110, 16),
      (0, 160, 22),
      (-60, 210, 28),
      (0, 260, 34),
      (80, 230, 40),
      (140, 170, 45),
      (100, 100, 36),
      (40, 45, 24),
      (0, 20, 12),
    ];
    return RaceCourse(
      mapId: mapId,
      name: 'Circuito do Bosque',
      difficulty: difficulty,
      direction: direction,
      gates: _buildVariantGates(
        baseCandidates,
        obstacles,
        difficulty: difficulty,
        direction: direction,
      ),
    );
  }

  // ── Cânion & Represa: travessia sobre a água e pilares ──
  static RaceCourse _canyon(
    String mapId,
    List<WorldObstacle> obstacles, {
    required CourseDifficulty difficulty,
    required CourseDirection direction,
  }) {
    final baseCandidates = <(double, double, double)>[
      (0, 80, 14),
      (70, 140, 20),
      (140, 200, 28),
      (210, 150, 36),
      (250, 70, 44),
      (200, -10, 45),
      (120, -60, 38),
      (30, -100, 30),
      (-60, -50, 22),
      (-120, 10, 16),
    ];
    return RaceCourse(
      mapId: mapId,
      name: 'Circuito da Represa',
      difficulty: difficulty,
      direction: direction,
      gates: _buildVariantGates(
        baseCandidates,
        obstacles,
        difficulty: difficulty,
        direction: direction,
      ),
    );
  }

  static List<RaceGate> _buildVariantGates(
    List<(double, double, double)> baseCandidates,
    List<WorldObstacle> obstacles, {
    required CourseDifficulty difficulty,
    required CourseDirection direction,
  }) {
    final ordered = direction == CourseDirection.reverse
        ? baseCandidates.reversed.toList()
        : baseCandidates;

    if (difficulty == CourseDifficulty.medium) {
      return _buildGates(ordered, obstacles, gateRadius: 4.5);
    }

    final gateRadius = difficulty == CourseDifficulty.easy ? 6.2 : 3.2;
    final adjusted = <(double, double, double)>[];
    for (var i = 0; i < ordered.length; i++) {
      final (bx, by, bz) = ordered[i];
      if (difficulty == CourseDifficulty.easy) {
        adjusted.add((bx, by, (bz + 3.5).clamp(8.0, 45.0)));
      } else {
        final slalom = i.isOdd ? 10.0 : 0.0;
        final sx = bx.abs() < 1e-3 ? bx + slalom : bx;
        final sy = bx.abs() >= 1e-3 ? by + (i % 4 == 1 ? 10.0 : -10.0) : by;
        adjusted.add((sx, sy, (bz - 3.0).clamp(8.0, 45.0)));
      }
    }
    return _buildGates(adjusted, obstacles, gateRadius: gateRadius);
  }

  /// Constrói os portais elevando o centro acima de qualquer obstáculo.
  static List<RaceGate> _buildGates(
    List<(double, double, double)> candidates,
    List<WorldObstacle> obstacles, {
    double gateRadius = 4.5,
  }) {
    final clearanceRadius = math.max(6.0, gateRadius + 1.5);
    final gates = <RaceGate>[];
    for (var i = 0; i < candidates.length; i++) {
      final (baseX, baseY, baseZ) = candidates[i];
      var x = baseX;
      var y = baseY;
      var z = _freeHeight(
        x,
        y,
        baseZ,
        obstacles,
        clearanceRadius: clearanceRadius,
      );

      // Se a altura necessária estourar o teto de 45 m, reposiciona o portal
      // sobre a via/trilha mais próxima (eixo livre de construções).
      if (z > 45.0) {
        if (x.abs() > y.abs()) {
          y = 0.0;
        } else {
          x = 0.0;
        }
        z = _freeHeight(
          x,
          y,
          baseZ,
          obstacles,
          clearanceRadius: clearanceRadius,
        );
      }
      if (z > 45.0) z = 45.0;

      final next = candidates[(i + 1) % candidates.length];
      final yaw = math.atan2(next.$1 - x, next.$2 - y) * 180.0 / math.pi;

      gates.add(RaceGate(
        index: i,
        x: x,
        y: y,
        z: z,
        yawDeg: (yaw + 360.0) % 360.0,
        radius: gateRadius,
      ));
    }
    return gates;
  }

  /// Altura mínima que deixa o portal livre dos obstáculos próximos.
  static double _freeHeight(
    double x,
    double y,
    double baseZ,
    List<WorldObstacle> obstacles, {
    double clearanceRadius = 6.0,
  }) {
    var z = baseZ;
    for (final obstacle in obstacles) {
      if (!obstacle.collidesAt(x, y, clearanceRadius)) continue;
      final clearance = obstacle.height + 3.0;
      if (clearance > z) z = clearance;
    }
    return z;
  }

  /// Serializa o circuito para envio ao Three.js (JSON válido).
  String toJsonString() => jsonEncode({
        'mapId': mapId,
        'name': name,
        'difficulty': difficulty.name,
        'direction': direction.name,
        'variantKey': variantKey,
        'gates': gates.map((g) => g.toJson()).toList(),
      });
}
