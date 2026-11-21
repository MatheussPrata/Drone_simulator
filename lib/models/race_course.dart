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

  Map<String, dynamic> toJson() => {
        'index': index,
        'x': double.parse(x.toStringAsFixed(2)),
        'y': double.parse(y.toStringAsFixed(2)),
        'z': double.parse(z.toStringAsFixed(2)),
        'yaw': double.parse(yawDeg.toStringAsFixed(1)),
        'radius': radius,
      };
}

/// Circuito determinístico de 10 portais para cada cenário.
class RaceCourse {
  final String mapId;
  final String name;
  final List<RaceGate> gates;

  const RaceCourse({
    required this.mapId,
    required this.name,
    required this.gates,
  });

  static final Map<String, RaceCourse> _cache = {};

  /// Circuito do mapa, com portais livres de obstáculos e alturas de 8m a 45m.
  static RaceCourse forMap(FlightMap map) {
    final cached = _cache[map.id];
    if (cached != null) return cached;

    final obstacles = WorldGenerator.generateFor(map);
    final scenario = WorldGenerator.scenarioFor(map);
    final course = switch (scenario) {
      WorldScenario.urban => _urban(map.id, obstacles),
      WorldScenario.forest => _forest(map.id, obstacles),
      WorldScenario.canyon => _canyon(map.id, obstacles),
    };
    _cache[map.id] = course;
    return course;
  }

  // ── Distrito Urbano: cruzamento das avenidas, alturas crescentes ──
  static RaceCourse _urban(String mapId, List<WorldObstacle> obstacles) {
    final candidates = <(double, double, double)>[
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
      gates: _buildGates(candidates, obstacles),
    );
  }

  // ── Parque Florestal: zigue-zague sobre as trilhas ──
  static RaceCourse _forest(String mapId, List<WorldObstacle> obstacles) {
    final candidates = <(double, double, double)>[
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
      gates: _buildGates(candidates, obstacles),
    );
  }

  // ── Cânion & Represa: travessia sobre a água e pilares ──
  static RaceCourse _canyon(String mapId, List<WorldObstacle> obstacles) {
    final candidates = <(double, double, double)>[
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
      gates: _buildGates(candidates, obstacles),
    );
  }

  /// Constrói os portais elevando o centro acima de qualquer obstáculo.
  static List<RaceGate> _buildGates(
    List<(double, double, double)> candidates,
    List<WorldObstacle> obstacles,
  ) {
    final gates = <RaceGate>[];
    for (var i = 0; i < candidates.length; i++) {
      final (baseX, baseY, baseZ) = candidates[i];
      var x = baseX;
      var y = baseY;
      var z = _freeHeight(x, y, baseZ, obstacles);

      // Se a altura necessária estourar o teto de 45 m, reposiciona o portal
      // sobre a via/trilha mais próxima (eixo livre de construções).
      if (z > 45.0) {
        if (x.abs() > y.abs()) {
          y = 0.0;
        } else {
          x = 0.0;
        }
        z = _freeHeight(x, y, baseZ, obstacles);
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
      ));
    }
    return gates;
  }

  /// Altura mínima que deixa o portal livre dos obstáculos próximos.
  static double _freeHeight(
    double x,
    double y,
    double baseZ,
    List<WorldObstacle> obstacles,
  ) {
    var z = baseZ;
    for (final obstacle in obstacles) {
      if (!obstacle.collidesAt(x, y, 6.0)) continue;
      final clearance = obstacle.height + 3.0;
      if (clearance > z) z = clearance;
    }
    return z;
  }

  /// Serializa o circuito para envio ao Three.js.
  String toJsonString() {
    final buffer = StringBuffer('{"mapId":"$mapId","name":"$name","gates":[');
    for (var i = 0; i < gates.length; i++) {
      if (i > 0) buffer.write(',');
      buffer.write(gates[i].toJson().toString());
    }
    buffer.write(']}');
    return buffer.toString();
  }
}
