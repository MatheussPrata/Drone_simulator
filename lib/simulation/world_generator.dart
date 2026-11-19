import 'dart:convert';
import 'dart:math';

import 'package:drone_simulator/models/flight_map.dart';
import 'package:drone_simulator/models/world_obstacle.dart';

/// Cenário geométrico/temático de um mapa de voo.
enum WorldScenario { urban, forest, canyon }

/// Gerador determinístico único da planta de obstáculos.
///
/// A lista produzida aqui é a **fonte da verdade**: a mesma estrutura é usada
/// pela colisão em Dart, pela cena Three.js (via JSON) e pelo minimapa.
class WorldGenerator {
  static const int _seed = 20261119;

  static final Map<String, List<WorldObstacle>> _cache = {};

  /// Identifica o cenário a partir do id/nome do mapa (aceita os ids antigos
  /// e os novos nomes temáticos).
  static WorldScenario scenarioFor(FlightMap map) {
    switch (map.id) {
      case 'distrito_urbano':
      case 'drone_park':
        return WorldScenario.urban;
      case 'parque_florestal':
      case 'aeroclube':
        return WorldScenario.forest;
      case 'canion_represa':
      case 'fpv_arena':
        return WorldScenario.canyon;
      default:
        return WorldScenario.urban;
    }
  }

  /// Retorna a planta de obstáculos do mapa (determinística e memoizada).
  static List<WorldObstacle> generateFor(FlightMap map) {
    final key = '${map.id}:${scenarioFor(map).name}';
    final cached = _cache[key];
    if (cached != null) return cached;

    final scenario = scenarioFor(map);
    final obstacles = switch (scenario) {
      WorldScenario.urban => _buildUrban(),
      WorldScenario.forest => _buildForest(),
      WorldScenario.canyon => _buildCanyon(),
    };

    _cache[key] = obstacles;
    return obstacles;
  }

  /// Serializa a planta + tema visual para envio ao WebView.
  static String obstaclesJson(FlightMap map) {
    final scenario = scenarioFor(map);
    final list = generateFor(map).map((o) => o.toJson()).toList();
    return jsonEncode({
      'scenario': scenario.name,
      'theme': themeFor(scenario),
      'obstacles': list,
    });
  }

  /// Paleta do terreno, céu e neblina de cada cenário.
  static Map<String, dynamic> themeFor(WorldScenario scenario) {
    switch (scenario) {
      case WorldScenario.urban:
        return {
          'sky': '#8cb5df',
          'fogDensity': 0.0015,
          'ground': '#ffffff',
          'water': false,
        };
      case WorldScenario.forest:
        return {
          'sky': '#9dc3d6',
          'fogDensity': 0.0024,
          'ground': '#cfe8bd',
          'water': false,
        };
      case WorldScenario.canyon:
        return {
          'sky': '#e2cdae',
          'fogDensity': 0.0018,
          'ground': '#c9b48c',
          'water': true,
        };
    }
  }

  // ────────────────────────────────────────────────────────────
  // Distrito Urbano — prédios altos, torre de rádio e heliponto
  // ────────────────────────────────────────────────────────────

  static List<WorldObstacle> _buildUrban() {
    final rand = _Mulberry32(_seed);
    final obstacles = <WorldObstacle>[];

    var placed = 0;
    for (var i = 0; i < 400 && placed < 70; i++) {
      final angle = rand.next() * pi * 2;
      final dist = 35 + rand.next() * 440;
      final bx = cos(angle) * dist;
      final by = sin(angle) * dist;

      // Heliponto central livre
      if (sqrt(bx * bx + by * by) < 26) continue;
      // Eixo das avenidas (cruzamento)
      if (bx.abs() < 16 || by.abs() < 16) continue;
      // Zona no-fly da subestação (x: 120, y: -280)
      if (sqrt(pow(bx - 120, 2) + pow(by + 280, 2)) < 85) continue;

      final width = 16 + rand.next() * 22;
      final depth = 16 + rand.next() * 22;
      final height = 20 + rand.next() * 65;

      obstacles.add(WorldObstacle(
        id: 'bld_$placed',
        type: ObstacleType.building,
        x: bx,
        y: by,
        width: width,
        depth: depth,
        height: height,
      ));
      placed++;
    }

    // Árvores dos quarteirões, evitando prédios e vias
    var trees = 0;
    for (var i = 0; i < 600 && trees < 140; i++) {
      final angle = rand.next() * pi * 2;
      final dist = 14 + rand.next() * 460;
      final tx = cos(angle) * dist;
      final ty = sin(angle) * dist;

      if (sqrt(tx * tx + ty * ty) < 9) continue;
      if (tx.abs() < 11 || ty.abs() < 11) continue;
      if (_overlapsAny(obstacles, tx, ty, 6.0)) continue;

      final scale = 0.75 + rand.next() * 0.6;
      obstacles.add(WorldObstacle(
        id: 'tree_$trees',
        type: ObstacleType.tree,
        x: tx,
        y: ty,
        height: 9.5 * scale,
        radius: 2.2 * scale,
      ));
      trees++;
    }

    // Torre de rádio (mesma posição do POI do mapa)
    obstacles.add(const WorldObstacle(
      id: 'radio_tower',
      type: ObstacleType.tower,
      x: -220,
      y: 180,
      height: 45,
      radius: 2.6,
    ));

    return obstacles;
  }

  // ────────────────────────────────────────────────────────────
  // Parque Florestal — bosque denso, clareira e trilhas
  // ────────────────────────────────────────────────────────────

  static List<WorldObstacle> _buildForest() {
    final rand = _Mulberry32(_seed + 101);
    final obstacles = <WorldObstacle>[];

    var trees = 0;
    for (var i = 0; i < 900 && trees < 190; i++) {
      final angle = rand.next() * pi * 2;
      final dist = 18 + rand.next() * 460;
      final tx = cos(angle) * dist;
      final ty = sin(angle) * dist;

      // Clareira de decolagem no centro
      if (sqrt(tx * tx + ty * ty) < 30) continue;
      // Trilhas de terra em cruz
      if (tx.abs() < 10 || ty.abs() < 10) continue;

      final scale = 0.9 + rand.next() * 0.9;
      obstacles.add(WorldObstacle(
        id: 'forest_tree_$trees',
        type: ObstacleType.tree,
        x: tx,
        y: ty,
        height: 11.0 * scale,
        radius: 2.6 * scale,
      ));
      trees++;
    }

    return obstacles;
  }

  // ────────────────────────────────────────────────────────────
  // Cânion & Represa — água, barragem, pilares de ponte e rochas
  // ────────────────────────────────────────────────────────────

  static List<WorldObstacle> _buildCanyon() {
    final rand = _Mulberry32(_seed + 202);
    final obstacles = <WorldObstacle>[];

    // Barragem de concreto cortando o mapa a oeste
    obstacles.add(const WorldObstacle(
      id: 'dam_wall',
      type: ObstacleType.dam,
      x: -330,
      y: 0,
      width: 24,
      depth: 620,
      height: 34,
    ));

    // Pilares da ponte sobre a represa (alinhados em Y)
    for (var i = 0; i < 6; i++) {
      obstacles.add(WorldObstacle(
        id: 'pillar_$i',
        type: ObstacleType.pillar,
        x: -180.0 + i * 70.0,
        y: -60,
        width: 7,
        depth: 7,
        height: 26,
      ));
    }

    // Formação rochosa nas bordas (bloqueia aproximação do geofence)
    var rocks = 0;
    for (var i = 0; i < 200 && rocks < 26; i++) {
      final angle = rand.next() * pi * 2;
      final dist = 330 + rand.next() * 150;
      final rx = cos(angle) * dist;
      final ry = sin(angle) * dist;

      // Mantém o setor da barragem/ponte livre
      if (rx < -260) continue;

      final scale = 0.8 + rand.next() * 1.4;
      obstacles.add(WorldObstacle(
        id: 'rock_$rocks',
        type: ObstacleType.rock,
        x: rx,
        y: ry,
        height: 12.0 * scale,
        radius: 4.5 * scale,
      ));
      rocks++;
    }

    return obstacles;
  }

  static bool _overlapsAny(
    List<WorldObstacle> obstacles,
    double x,
    double y,
    double margin,
  ) {
    for (final o in obstacles) {
      if (o.isCylindrical) {
        if (sqrt(pow(x - o.x, 2) + pow(y - o.y, 2)) <
            o.radius + margin) {
          return true;
        }
      } else if ((x - o.x).abs() < o.width / 2 + margin &&
          (y - o.y).abs() < o.depth / 2 + margin) {
        return true;
      }
    }
    return false;
  }
}

/// PRNG determinístico (mulberry32) — mesma sequência em todas as plataformas.
class _Mulberry32 {
  int _state;

  _Mulberry32(int seed) : _state = seed & 0xFFFFFFFF;

  double next() {
    _state = (_state + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _state;
    t = _imul(t ^ (t >>> 15), 1 | t) & 0xFFFFFFFF;
    t = (t + _imul(t ^ (t >>> 7), 61 | t)) & 0xFFFFFFFF;
    return ((t ^ (t >>> 14)) & 0xFFFFFFFF) / 4294967296.0;
  }

  /// Multiplicação 32x32 sem sinal, exata mesmo com inteiros de 64 bits.
  static int _imul(int a, int b) {
    final aLow = a & 0xFFFF;
    final aHigh = (a >>> 16) & 0xFFFF;
    final bLow = b & 0xFFFF;
    final bHigh = (b >>> 16) & 0xFFFF;
    final low = aLow * bLow;
    final mid = ((aLow * bHigh) + (aHigh * bLow)) & 0xFFFF;
    return (low + (mid << 16)) & 0xFFFFFFFF;
  }
}
