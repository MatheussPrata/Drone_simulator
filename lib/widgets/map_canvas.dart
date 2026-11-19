import 'dart:math';
import 'package:flutter/material.dart';
import 'package:drone_simulator/core/utils/geo_math.dart';
import 'package:drone_simulator/models/flight_map.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';
import 'package:drone_simulator/models/world_obstacle.dart';
import 'package:drone_simulator/simulation/world_generator.dart';

/// Widget de exibição tática do mapa em 2D/top-down usando apenas recursos nativos do Flutter.
///
/// Desenha grade de referência, Geofence de 500m tracejado em vermelho, zonas no-fly
/// translúcidas, ponto H (home) na origem e o drone com sombra proporcional à altitude z.
class MapCanvas extends StatefulWidget {
  final double droneX;
  final double droneY;
  final double droneZ;
  final double yaw;
  final double pixelsPerMeter;
  final bool followDrone;
  final double geofenceRadius;
  final FlightMap? flightMap;
  final List<NoFlyZone>? noFlyZones;
  final SimulatorController? controller;
  final bool enableInteractivity;

  const MapCanvas({
    super.key,
    this.droneX = 0.0,
    this.droneY = 0.0,
    this.droneZ = 0.0,
    this.yaw = 0.0,
    this.pixelsPerMeter = 1.0,
    this.followDrone = true,
    this.geofenceRadius = 500.0,
    this.flightMap,
    this.noFlyZones,
    this.controller,
    this.enableInteractivity = true,
  });

  @override
  State<MapCanvas> createState() => _MapCanvasState();
}

class _MapCanvasState extends State<MapCanvas> {
  Offset _panOffset = Offset.zero;
  late double _currentScale;

  @override
  void initState() {
    super.initState();
    _currentScale = widget.pixelsPerMeter;
    widget.controller?.addListener(_onControllerUpdate);
  }

  @override
  void didUpdateWidget(MapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerUpdate);
      widget.controller?.addListener(_onControllerUpdate);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final double curX = ctrl != null ? ctrl.x : widget.droneX;
    final double curY = ctrl != null ? ctrl.y : widget.droneY;
    final double curZ = ctrl != null ? ctrl.z : widget.droneZ;
    final double curYaw = ctrl != null ? (ctrl.yaw != 0.0 ? ctrl.yaw : ctrl.physics.state.heading) : widget.yaw;
    final activeMap = widget.flightMap ?? ctrl?.physics.activeMap ?? FlightMap.dronePark;
    final nfzList = widget.noFlyZones ?? activeMap.noFlyZones;

    Widget canvasWidget = SizedBox.expand(
      child: ClipRect(
        child: CustomPaint(
          painter: MapCanvasPainter(
            droneX: curX,
            droneY: curY,
            droneZ: curZ,
            yaw: curYaw,
            pixelsPerMeter: _currentScale,
            followDrone: widget.followDrone,
            geofenceRadius: widget.geofenceRadius,
            flightMap: activeMap,
            noFlyZones: nfzList,
            obstacles: WorldGenerator.generateFor(activeMap),
            panOffset: _panOffset,
          ),
        ),
      ),
    );

    if (widget.enableInteractivity) {
      return GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _panOffset += details.delta;
          });
        },
        child: canvasWidget,
      );
    }

    return canvasWidget;
  }
}

/// CustomPainter que renderiza o mapa, limites, zonas de exclusão e drone visto de cima.
class MapCanvasPainter extends CustomPainter {
  final double droneX;
  final double droneY;
  final double droneZ;
  final double yaw;
  final double pixelsPerMeter;
  final bool followDrone;
  final double geofenceRadius;
  final FlightMap flightMap;
  final List<NoFlyZone> noFlyZones;
  final List<WorldObstacle> obstacles;
  final Offset panOffset;

  MapCanvasPainter({
    required this.droneX,
    required this.droneY,
    required this.droneZ,
    required this.yaw,
    required this.pixelsPerMeter,
    required this.followDrone,
    required this.geofenceRadius,
    required this.flightMap,
    required this.noFlyZones,
    this.obstacles = const [],
    required this.panOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Rect screenRect = Offset.zero & size;

    // Fundo escuro aeroespacial (Slate 950)
    final bgPaint = Paint()..color = const Color(0xFF0B1120);
    canvas.drawRect(screenRect, bgPaint);

    canvas.save();

    // Centraliza o centro da tela
    canvas.translate(size.width / 2, size.height / 2);

    // Ajuste de câmera: se followDrone = true, centra no drone; senão na origem (0,0)
    if (followDrone) {
      canvas.translate(
        -droneX * pixelsPerMeter + panOffset.dx,
        droneY * pixelsPerMeter + panOffset.dy,
      );
    } else {
      canvas.translate(panOffset.dx, panOffset.dy);
    }

    // 1. Grade de referência no chão
    _drawGroundGrid(canvas);

    // 1.1 Planta de obstáculos (idêntica à cena 3D e à colisão)
    _drawObstacles(canvas);

    // 2. Geofence circular tracejado de 500m
    _drawGeofence(canvas);

    // 3. Zonas No-Fly translúcidas
    _drawNoFlyZones(canvas);

    // 4. Ponto Home 'H' verde na origem (0,0)
    _drawHomePoint(canvas);

    // 5. Sombra do drone projetada no solo (deslocada proporcional à altitude z)
    _drawDroneShadow(canvas);

    // 6. Drone visto de cima com rotação por yaw
    _drawDrone(canvas);

    canvas.restore();

    // 7. Mini HUD de escala e telemetria básica no canto
    _drawScaleIndicator(canvas, size);
  }

  /// Planta de obstáculos do mapa, exatamente a mesma usada na colisão e no 3D.
  void _drawObstacles(Canvas canvas) {
    if (obstacles.isEmpty) return;

    final buildingPaint = Paint()..color = const Color(0xFF475569).withOpacity(0.85);
    final treePaint = Paint()..color = const Color(0xFF2F6B3A).withOpacity(0.85);
    final rockPaint = Paint()..color = const Color(0xFF6B7280).withOpacity(0.9);
    final towerPaint = Paint()..color = const Color(0xFFDC2626).withOpacity(0.9);
    final concretePaint = Paint()..color = const Color(0xFF94A3B8).withOpacity(0.9);

    for (final obstacle in obstacles) {
      final center =
          Offset(obstacle.x * pixelsPerMeter, -obstacle.y * pixelsPerMeter);

      switch (obstacle.type) {
        case ObstacleType.tree:
          canvas.drawCircle(
            center,
            max(obstacle.radius, 1.0) * pixelsPerMeter,
            treePaint,
          );
          break;
        case ObstacleType.tower:
          canvas.drawCircle(
            center,
            max(obstacle.radius, 1.5) * pixelsPerMeter,
            towerPaint,
          );
          break;
        case ObstacleType.rock:
          canvas.drawCircle(
            center,
            max(obstacle.radius, 1.0) * pixelsPerMeter,
            rockPaint,
          );
          break;
        case ObstacleType.building:
          canvas.drawRect(
            Rect.fromCenter(
              center: center,
              width: obstacle.width * pixelsPerMeter,
              height: obstacle.depth * pixelsPerMeter,
            ),
            buildingPaint,
          );
          break;
        case ObstacleType.dam:
        case ObstacleType.pillar:
        case ObstacleType.hangar:
          canvas.drawRect(
            Rect.fromCenter(
              center: center,
              width: obstacle.width * pixelsPerMeter,
              height: obstacle.depth * pixelsPerMeter,
            ),
            concretePaint,
          );
          break;
      }
    }
  }

  /// 1. Desenha a grade de referência a cada 50m e eixos cartesianos
  void _drawGroundGrid(Canvas canvas) {    const double stepMeters = 50.0;
    const double maxExtent = 700.0; // além do geofence
    final double stepPx = stepMeters * pixelsPerMeter;
    final int lineCount = (maxExtent / stepMeters).ceil();

    final gridPaint = Paint()
      ..color = const Color(0xFF1E293B) // Slate 800
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final majorGridPaint = Paint()
      ..color = const Color(0xFF334155) // Slate 700
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final axisPaint = Paint()
      ..color = const Color(0xFF0EA5E9).withOpacity(0.35) // Cyan sutil
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Linhas paralelas
    for (int i = -lineCount; i <= lineCount; i++) {
      final double pos = i * stepPx;
      final bool isMajor = (i % 2 == 0);
      final p = (i == 0) ? axisPaint : (isMajor ? majorGridPaint : gridPaint);

      // Linhas verticais (ao longo de Y)
      canvas.drawLine(
        Offset(pos, -lineCount * stepPx),
        Offset(pos, lineCount * stepPx),
        p,
      );

      // Linhas horizontais (ao longo de X)
      canvas.drawLine(
        Offset(-lineCount * stepPx, pos),
        Offset(lineCount * stepPx, pos),
        p,
      );
    }
  }

  /// 2. Desenha o círculo tracejado vermelho de Geofence de 500m
  void _drawGeofence(Canvas canvas) {
    final double rPx = geofenceRadius * pixelsPerMeter;

    final fencePaint = Paint()
      ..color = const Color(0xFFEF4444) // Red 500
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    // Círculo tracejado vermelho
    _drawDashedCircle(canvas, Offset.zero, rPx, fencePaint, dashCount: 80, dashRatio: 0.55);

    // Círculo de aviso amarelo aos 400m
    final double warningPx = (geofenceRadius * 0.8) * pixelsPerMeter;
    final warningPaint = Paint()
      ..color = const Color(0xFFF59E0B).withOpacity(0.5) // Amber 500
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    _drawDashedCircle(canvas, Offset.zero, warningPx, warningPaint, dashCount: 60, dashRatio: 0.4);
  }

  /// 3. Desenha polígonos/círculos vermelhos translúcidos para as zonas no-fly
  void _drawNoFlyZones(Canvas canvas) {
    final fillPaint = Paint()
      ..color = const Color(0xFFEF4444).withOpacity(0.22)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = const Color(0xFFEF4444).withOpacity(0.85)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (final nfz in noFlyZones) {
      // Converte coordenadas geográficas relativas ao centro do mapa para metros cartesianos
      final dist = GeoMath.distanceMeters(flightMap.center, nfz.center);
      final bearing = GeoMath.bearing(flightMap.center, nfz.center);
      final bearingRad = bearing * pi / 180.0;

      final double xMeters = sin(bearingRad) * dist;
      final double yMeters = cos(bearingRad) * dist;

      final Offset centerPx = Offset(
        xMeters * pixelsPerMeter,
        -yMeters * pixelsPerMeter, // North é negativo no Canvas
      );
      final double radiusPx = nfz.radiusMeters * pixelsPerMeter;

      // Círculo translúcido
      canvas.drawCircle(centerPx, radiusPx, fillPaint);

      // Borda tracejada
      _drawDashedCircle(canvas, centerPx, radiusPx, borderPaint, dashCount: 36, dashRatio: 0.6);

      // Rótulo da zona no-fly
      final textSpan = TextSpan(
        text: 'NFZ: ${nfz.name}',
        style: const TextStyle(
          color: Color(0xFFFCA5A5),
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(centerPx.dx - (textPainter.width / 2), centerPx.dy - (textPainter.height / 2)),
      );
    }
  }

  /// 4. Desenha o ponto H (Helipad) verde na origem (0,0)
  void _drawHomePoint(Canvas canvas) {
    const Offset homePos = Offset.zero;
    const double padRadius = 14.0;

    // Fundo do heliponto
    final padBg = Paint()
      ..color = const Color(0xFF10B981).withOpacity(0.25) // Emerald 500
      ..style = PaintingStyle.fill;
    canvas.drawCircle(homePos, padRadius, padBg);

    // Borda verde
    final ringPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(homePos, padRadius, ringPaint);

    // Letra 'H' em linhas brancas nítidas
    final hPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    const double hHalfW = 4.5;
    const double hHalfH = 6.0;

    // Barra vertical esquerda
    canvas.drawLine(
      const Offset(-hHalfW, -hHalfH),
      const Offset(-hHalfW, hHalfH),
      hPaint,
    );
    // Barra vertical direita
    canvas.drawLine(
      const Offset(hHalfW, -hHalfH),
      const Offset(hHalfW, hHalfH),
      hPaint,
    );
    // Barra horizontal central
    canvas.drawLine(
      const Offset(-hHalfW, 0),
      const Offset(hHalfW, 0),
      hPaint,
    );
  }

  /// 5. Sombra projetada do drone no solo proporcional à altitude z
  void _drawDroneShadow(Canvas canvas) {
    if (droneZ <= 0.05) return; // drone no chão não projeta sombra destacada

    // Deslocamento da sombra baseado na altitude (simulando luz solar a 45 graus)
    final double offsetDist = (droneZ * 0.35 * pixelsPerMeter).clamp(2.0, 60.0);
    final Offset shadowCenter = Offset(
      droneX * pixelsPerMeter + offsetDist,
      -droneY * pixelsPerMeter + offsetDist,
    );

    // Quanto mais alto, mais a sombra se difunde e diminui a opacidade
    final double opacity = (0.35 - (droneZ * 0.002)).clamp(0.12, 0.35);
    final double scale = (1.0 + (droneZ * 0.015)).clamp(1.0, 1.8);

    canvas.save();
    canvas.translate(shadowCenter.dx, shadowCenter.dy);
    canvas.rotate(yaw * pi / 180.0);
    canvas.scale(scale);

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(opacity)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, (droneZ * 0.15).clamp(2.0, 8.0));

    // Formato da sombra do drone
    final path = Path()
      ..moveTo(0, -12)
      ..lineTo(9, 10)
      ..lineTo(0, 6)
      ..lineTo(-9, 10)
      ..close();

    canvas.drawPath(path, shadowPaint);
    canvas.drawCircle(Offset.zero, 7.0, shadowPaint);

    canvas.restore();
  }

  /// 6. Desenha o drone visto de cima com rotação pelo yaw
  void _drawDrone(Canvas canvas) {
    final Offset dronePos = Offset(
      droneX * pixelsPerMeter,
      -droneY * pixelsPerMeter, // North é -Y
    );

    canvas.save();
    canvas.translate(dronePos.dx, dronePos.dy);
    // Rotação pelo yaw (0 deg = North/Up)
    canvas.rotate(yaw * pi / 180.0);

    // ── Braços do quadricóptero (X-Frame) ──
    final armPaint = Paint()
      ..color = const Color(0xFF64748B) // Slate 500
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    const double armSpan = 11.0;
    canvas.drawLine(const Offset(-armSpan, -armSpan), const Offset(armSpan, armSpan), armPaint);
    canvas.drawLine(const Offset(armSpan, -armSpan), const Offset(-armSpan, armSpan), armPaint);

    // ── Motores / Rotores nos 4 cantos ──
    final frontRotorPaint = Paint()..color = const Color(0xFF22C55E); // Green (frente)
    final rearRotorPaint = Paint()..color = const Color(0xFFEF4444);  // Red (traseira)

    canvas.drawCircle(const Offset(-armSpan, -armSpan), 3.8, frontRotorPaint);
    canvas.drawCircle(const Offset(armSpan, -armSpan), 3.8, frontRotorPaint);
    canvas.drawCircle(const Offset(-armSpan, armSpan), 3.8, rearRotorPaint);
    canvas.drawCircle(const Offset(armSpan, armSpan), 3.8, rearRotorPaint);

    // ── Corpo central / Triângulo aerodinâmico (Chevron) ──
    final bodyPaint = Paint()
      ..color = const Color(0xFF0EA5E9) // Sky Blue 500
      ..style = PaintingStyle.fill;

    final bodyBorder = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    final bodyPath = Path()
      ..moveTo(0, -13)      // Nariz (aponta para frente / norte)
      ..lineTo(8, 7)        // Asa direita
      ..lineTo(0, 3)        // Centro traseiro côncavo
      ..lineTo(-8, 7)       // Asa esquerda
      ..close();

    canvas.drawPath(bodyPath, bodyPaint);
    canvas.drawPath(bodyPath, bodyBorder);

    // Ponto central de fixação / LED de status
    final ledPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset.zero, 2.2, ledPaint);

    canvas.restore();
  }

  /// 7. Indicador de escala visual e informações de voo
  void _drawScaleIndicator(Canvas canvas, Size size) {
    // Barra de escala de 50 metros no canto inferior esquerdo
    final double barLengthPx = 50.0 * pixelsPerMeter;
    final Offset barOrigin = Offset(20, size.height - 25);

    final barPaint = Paint()
      ..color = Colors.white70
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.square;

    canvas.drawLine(barOrigin, Offset(barOrigin.dx + barLengthPx, barOrigin.dy), barPaint);
    canvas.drawLine(barOrigin, Offset(barOrigin.dx, barOrigin.dy - 5), barPaint);
    canvas.drawLine(
      Offset(barOrigin.dx + barLengthPx, barOrigin.dy),
      Offset(barOrigin.dx + barLengthPx, barOrigin.dy - 5),
      barPaint,
    );

    final scaleSpan = TextSpan(
      text: '50m | Alt: ${droneZ.toStringAsFixed(1)}m',
      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
    );
    final scalePainter = TextPainter(
      text: scaleSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    scalePainter.paint(canvas, Offset(barOrigin.dx, barOrigin.dy - 20));
  }

  /// Utilitário para desenhar arcos tracejados
  void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint, {
    int dashCount = 60,
    double dashRatio = 0.6,
  }) {
    final double step = (2 * pi) / dashCount;
    final double dashAngle = step * dashRatio;

    for (int i = 0; i < dashCount; i++) {
      final double startAngle = i * step;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        dashAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant MapCanvasPainter oldDelegate) {
    return oldDelegate.droneX != droneX ||
        oldDelegate.droneY != droneY ||
        oldDelegate.droneZ != droneZ ||
        oldDelegate.yaw != yaw ||
        oldDelegate.pixelsPerMeter != pixelsPerMeter ||
        oldDelegate.followDrone != followDrone ||
        oldDelegate.panOffset != panOffset ||
        oldDelegate.geofenceRadius != geofenceRadius;
  }
}
