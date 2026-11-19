import 'dart:math';

/// Tipos de obstáculos sólidos compartilhados entre a física (Dart) e a
/// renderização 3D (Three.js).
///
/// A mesma lista gerada por [WorldGenerator] alimenta colisão, cena 3D e
/// minimapa, garantindo que o drone nunca atravesse algo que está visível.
enum ObstacleType {
  building,
  tree,
  tower,
  rock,
  dam,
  pillar,
  hangar,
}

/// Obstáculo sólido posicionado em metros relativos ao Home (0,0).
///
/// [x] cresce a leste e [y] cresce ao norte (mesma convenção do
/// `SimulatorController`). Obstáculos cilíndricos (árvores, torres, rochas)
/// usam [radius]; os demais usam [width] x [depth] (AABB alinhada aos eixos).
class WorldObstacle {
  final String id;
  final ObstacleType type;

  /// Centro do obstáculo em metros a leste do Home.
  final double x;

  /// Centro do obstáculo em metros ao norte do Home.
  final double y;

  /// Extensão em X (metros) para obstáculos em caixa.
  final double width;

  /// Extensão em Y (metros) para obstáculos em caixa.
  final double depth;

  /// Altura/ topo do obstáculo em metros (relativo ao solo).
  final double height;

  /// Raio de colisão para obstáculos cilíndricos. Zero = caixa.
  final double radius;

  const WorldObstacle({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    this.width = 0.0,
    this.depth = 0.0,
    required this.height,
    this.radius = 0.0,
  });

  bool get isCylindrical => radius > 0.0;

  /// Topo do obstáculo (usado para pouso em telhado).
  double get top => height;

  bool get isWalkableRoof =>
      type == ObstacleType.building ||
      type == ObstacleType.hangar ||
      type == ObstacleType.dam;

  /// Verifica se o ponto ([px], [py]) colide com o obstáculo considerando o
  /// raio do drone em [droneRadius].
  bool collidesAt(double px, double py, double droneRadius) {
    if (isCylindrical) {
      final dx = px - x;
      final dy = py - y;
      return sqrt(dx * dx + dy * dy) < (radius + droneRadius);
    }
    return (px - x).abs() < (width / 2 + droneRadius) &&
        (py - y).abs() < (depth / 2 + droneRadius);
  }

  /// Verifica se o ponto está sobre a projeção horizontal do obstáculo,
  /// sem margem (usado para pouso em telhado).
  bool coversPoint(double px, double py) {
    if (isCylindrical) {
      final dx = px - x;
      final dy = py - y;
      return sqrt(dx * dx + dy * dy) <= radius;
    }
    return (px - x).abs() <= width / 2 && (py - y).abs() <= depth / 2;
  }

  /// Empurra o ponto para fora do obstáculo, retornando a nova posição e a
  /// normal de impacto (usada para zerar a componente normal da velocidade).
  ({double x, double y, double normalX, double normalY}) resolve(
    double px,
    double py,
    double droneRadius,
  ) {
    if (isCylindrical) {
      final dx = px - x;
      final dy = py - y;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist <= 0.0001) {
        return (x: px, y: py + radius + droneRadius, normalX: 0.0, normalY: 1.0);
      }
      final nx = dx / dist;
      final ny = dy / dist;
      final targetDist = radius + droneRadius;
      return (
        x: x + nx * targetDist,
        y: y + ny * targetDist,
        normalX: nx,
        normalY: ny,
      );
    }

    // Caixa: resolve pelo eixo de menor penetração.
    final halfW = width / 2 + droneRadius;
    final halfD = depth / 2 + droneRadius;
    final penetrationX = halfW - (px - x).abs();
    final penetrationY = halfD - (py - y).abs();

    if (penetrationX < penetrationY) {
      final nx = (px - x) >= 0 ? 1.0 : -1.0;
      return (x: x + nx * halfW, y: py, normalX: nx, normalY: 0.0);
    }
    final ny = (py - y) >= 0 ? 1.0 : -1.0;
    return (x: px, y: y + ny * halfD, normalX: 0.0, normalY: ny);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'x': double.parse(x.toStringAsFixed(2)),
        'y': double.parse(y.toStringAsFixed(2)),
        'width': double.parse(width.toStringAsFixed(2)),
        'depth': double.parse(depth.toStringAsFixed(2)),
        'height': double.parse(height.toStringAsFixed(2)),
        'radius': double.parse(radius.toStringAsFixed(2)),
      };
}
