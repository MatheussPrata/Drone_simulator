import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:drone_simulator/models/flight_map.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';

/// Projetor matemático 3D em perspectiva cônica (pinhole camera).
///
/// Transforma coordenadas do mundo cartesiano (Leste: +X, Norte: +Y, Altitude: +Z)
/// para coordenadas de tela 2D em pixels no canvas, simulando uma câmera FPV.
class FpvCameraProjector {
  final double droneX;
  final double droneY;
  final double droneZ;
  final double yawDeg;
  final double visualPitchDeg;
  final double gimbalPitchDeg;
  final double visualRollDeg;
  final Size screenSize;
  final double vFovDeg;

  late final double effectiveDroneZ;
  late final double effectivePitchRad;
  late final double yawRad;
  late final double rollRad;
  late final double cosYaw;
  late final double sinYaw;
  late final double cosPitch;
  late final double sinPitch;
  late final double cosRoll;
  late final double sinRoll;
  late final double focalLength;
  late final double cx;
  late final double cy;

  FpvCameraProjector({
    required this.droneX,
    required this.droneY,
    required this.droneZ,
    required this.yawDeg,
    this.visualPitchDeg = 0.0,
    this.gimbalPitchDeg = 0.0,
    this.visualRollDeg = 0.0,
    required this.screenSize,
    this.vFovDeg = 60.0,
  }) {
    // Altitude mínima para a lente da câmera para nunca dividir por zero
    effectiveDroneZ = max(0.2, droneZ);

    yawRad = yawDeg * pi / 180.0;
    // visualPitch: inclinação dinâmica do drone (ex: acelerar para frente = pitch negativo)
    // gimbalPitch: inclinação do gimbal da câmera (0° horizonte até -90° para o chão)
    effectivePitchRad = (visualPitchDeg + gimbalPitchDeg) * pi / 180.0;
    rollRad = visualRollDeg * pi / 180.0;

    cosYaw = cos(yawRad);
    sinYaw = sin(yawRad);
    cosPitch = cos(effectivePitchRad);
    sinPitch = sin(effectivePitchRad);
    cosRoll = cos(rollRad);
    sinRoll = sin(rollRad);

    cx = screenSize.width / 2.0;
    cy = screenSize.height / 2.0;
    final halfFovRad = (vFovDeg / 2.0) * pi / 180.0;
    focalLength = cy / tan(halfFovRad);
  }

  /// Converte coordenadas de mundo para o espaço local da câmera:
  /// Retorna `[xCam, yCam, zCam]`:
  /// - `xCam`: lateral (positivo = direita, negativo = esquerda)
  /// - `yCam`: vertical (positivo = acima da lente, negativo = abaixo)
  /// - `zCam`: profundidade frontal (positivo = à frente da lente)
  List<double> toCameraSpace(double wx, double wy, double wz) {
    final dx = wx - droneX;
    final dy = wy - droneY;
    final dz = wz - effectiveDroneZ;

    // 1. Rotação de Yaw (Heading 0° = Norte (+Y), 90° = Leste (+X))
    final xBody = dx * cosYaw - dy * sinYaw;
    final yBody = dx * sinYaw + dy * cosYaw;
    final zBody = dz;

    // 2. Rotação de Pitch
    // Vetores da câmera relativos ao corpo:
    // Forward: (0, cosPitch, sinPitch)
    // Up:      (0, -sinPitch, cosPitch)
    // Right:   (1, 0, 0)
    final zCam = yBody * cosPitch + zBody * sinPitch;
    final yCam = -yBody * sinPitch + zBody * cosPitch;
    final xCam = xBody;

    return [xCam, yCam, zCam];
  }

  /// Projeta um ponto 3D para tela (Offset em pixels).
  /// Retorna `null` se o ponto estiver atrás do plano próximo de corte (`zCam < nearClip`).
  Offset? project(double wx, double wy, double wz, {double nearClip = 0.5}) {
    final cam = toCameraSpace(wx, wy, wz);
    final zCam = cam[2];
    if (zCam < nearClip) return null;

    final xCam = cam[0];
    final yCam = cam[1];

    // Projeção perspectiva sem roll
    final u = focalLength * (xCam / zCam);
    final v = -focalLength * (yCam / zCam); // Y cresce para baixo no canvas

    // Rotação de Roll da câmera (quando o drone rola para a direita, o mundo rotaciona no sentido anti-horário na tela)
    final uRolled = u * cosRoll + v * sinRoll;
    final vRolled = -u * sinRoll + v * cosRoll;

    return Offset(cx + uRolled, cy + vRolled);
  }

  /// Projeta um segmento de reta 3D entre (x1, y1, z1) e (x2, y2, z2),
  /// aplicando corte suave contra o plano próximo (`nearClip`).
  List<Offset>? projectLine(
    double x1,
    double y1,
    double z1,
    double x2,
    double y2,
    double z2, {
    double nearClip = 0.5,
  }) {
    final c1 = toCameraSpace(x1, y1, z1);
    final c2 = toCameraSpace(x2, y2, z2);

    final z1Cam = c1[2];
    final z2Cam = c2[2];

    if (z1Cam < nearClip && z2Cam < nearClip) return null;

    double p1x = c1[0], p1y = c1[1], p1z = z1Cam;
    double p2x = c2[0], p2y = c2[1], p2z = z2Cam;

    if (p1z < nearClip) {
      final t = (nearClip - p1z) / (p2z - p1z);
      p1x = p1x + t * (p2x - p1x);
      p1y = p1y + t * (p2y - p1y);
      p1z = nearClip;
    } else if (p2z < nearClip) {
      final t = (nearClip - p2z) / (p1z - p2z);
      p2x = p2x + t * (p1x - p2x);
      p2y = p2y + t * (p1y - p2y);
      p2z = nearClip;
    }

    final u1 = focalLength * (p1x / p1z);
    final v1 = -focalLength * (p1y / p1z);
    final u1R = u1 * cosRoll + v1 * sinRoll;
    final v1R = -u1 * sinRoll + v1 * cosRoll;

    final u2 = focalLength * (p2x / p2z);
    final v2 = -focalLength * (p2y / p2z);
    final u2R = u2 * cosRoll + v2 * sinRoll;
    final v2R = -u2 * sinRoll + v2 * cosRoll;

    return [
      Offset(cx + u1R, cy + v1R),
      Offset(cx + u2R, cy + v2R),
    ];
  }
}

/// Widget de visão principal FPV em primeira pessoa (Cockpit / Drone View).
///
/// Renderiza o mundo em perspectiva 3D através de um [CustomPainter] de alta performance:
/// céu em gradiente azul, horizonte inclinado por roll/pitch, solo em perspectiva com
/// grade dinâmica, pista, heliponto 'H', marcos 3D (gates, torre de rádio, prédios) e a
/// cúpula translúcida da Geofence de 500m e zonas no-fly.
class FpvCameraView extends StatefulWidget {
  final SimulatorController? controller;
  final double droneX;
  final double droneY;
  final double droneZ;
  final double yaw;
  final double visualPitch;
  final double visualRoll;
  final double gimbalPitch;
  final FlightMap? flightMap;
  final bool showOsd;
  final bool showGrid;
  final bool showGeofence;
  final bool showLandmarks;
  final bool showGroundMap;
  final bool transparentGround;

  const FpvCameraView({
    super.key,
    this.controller,
    this.droneX = 0.0,
    this.droneY = 0.0,
    this.droneZ = 0.0,
    this.yaw = 0.0,
    this.visualPitch = 0.0,
    this.visualRoll = 0.0,
    this.gimbalPitch = 0.0,
    this.flightMap,
    this.showOsd = true,
    this.showGrid = true,
    this.showGeofence = true,
    this.showLandmarks = true,
    this.showGroundMap = true,
    this.transparentGround = true,
  });

  @override
  State<FpvCameraView> createState() => _FpvCameraViewState();
}

class _FpvCameraViewState extends State<FpvCameraView> {
  final MapController _groundMapController = MapController();

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerTick);
  }

  @override
  void didUpdateWidget(FpvCameraView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerTick);
      widget.controller?.addListener(_onControllerTick);
    }
    if (widget.controller == null && widget.showGroundMap) {
      _updateGroundMapManual();
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerTick);
    super.dispose();
  }

  void _onControllerTick() {
    if (!mounted) return;
    final ctrl = widget.controller;
    if (ctrl != null && widget.showGroundMap) {
      final activeMap = widget.flightMap ?? ctrl.physics.activeMap;
      final latLng = FlightMap.metersToLatLng(ctrl.x, ctrl.y, activeMap.center);
      final altitudeClamped = ctrl.z.clamp(0.0, 150.0);
      final double groundZoom = (19.5 - (altitudeClamped / 120.0) * 3.0).clamp(15.0, 20.0);
      try {
        _groundMapController.move(latLng, groundZoom);
      } catch (_) {}
    }
    setState(() {});
  }

  void _updateGroundMapManual() {
    final activeMap = widget.flightMap ?? FlightMap.dronePark;
    final latLng = FlightMap.metersToLatLng(widget.droneX, widget.droneY, activeMap.center);
    final altitudeClamped = widget.droneZ.clamp(0.0, 150.0);
    final double groundZoom = (19.5 - (altitudeClamped / 120.0) * 3.0).clamp(15.0, 20.0);
    try {
      _groundMapController.move(latLng, groundZoom);
    } catch (_) {}
  }

  Widget _buildGroundMap({
    required double curX,
    required double curY,
    required double curZ,
    required double curYaw,
    required double curPitch,
    required double curRoll,
    required double curGimbal,
    required FlightMap activeMap,
  }) {
    final droneLatLng = FlightMap.metersToLatLng(curX, curY, activeMap.center);
    final altitudeClamped = curZ.clamp(0.0, 150.0);
    // Zoom escalado suavemente pela altitude z: ~19.5 a z=0m até ~16.5 a z=120m
    final double groundZoom = (19.5 - (altitudeClamped / 120.0) * 3.0).clamp(15.0, 20.0);

    final double yawRad = curYaw * pi / 180.0;
    final double rollRad = curRoll * pi / 180.0;

    // Inclinação combinada (Pitch dinâmico do drone + Gimbal Pitch)
    // Gimbal varia entre 0.0° (horizonte) e -90.0° (Nadir)
    final double totalPitchDeg = (curPitch + curGimbal).clamp(-90.0, 20.0);
    // Nadir (-90°): nadirFactor = 0.0 -> tiltAngle = 0.0 (mapa plano visto de cima / top-down)
    // Horizonte (0°): nadirFactor = 1.0 -> tiltAngle = -65° (terreno em perspectiva fugindo para o horizonte)
    final double nadirFactor = ((totalPitchDeg + 90.0) / 90.0).clamp(0.0, 1.3);
    const double maxTiltRad = 65.0 * pi / 180.0;
    final double tiltAngle = -nadirFactor * maxTiltRad;

    // Matriz de Perspectiva 3D
    final perspectiveMatrix = Matrix4.identity()
      ..setEntry(3, 2, 0.0025)
      ..rotateZ(-rollRad)
      ..rotateX(tiltAngle);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        // Tamanho expandido para garantir cobertura completa do solo sob forte inclinação e rotação
        final mapDimension = max(w, h) * 2.2;

        return IgnorePointer(
          key: const Key('fpv_ground_map_layer'),
          child: Center(
            child: Transform(
              transform: perspectiveMatrix,
              alignment: Alignment.center,
              child: Transform.rotate(
                angle: -yawRad,
                child: SizedBox(
                  width: mapDimension,
                  height: mapDimension,
                  child: FlutterMap(
                    key: const ValueKey('fpv_ground_flutter_map'),
                    mapController: _groundMapController,
                    options: MapOptions(
                      initialCenter: droneLatLng,
                      initialZoom: groundZoom,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                        userAgentPackageName: 'com.dronesim.drone_simulator',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final curX = ctrl != null ? ctrl.x : widget.droneX;
    final curY = ctrl != null ? ctrl.y : widget.droneY;
    final curZ = ctrl != null ? ctrl.z : widget.droneZ;
    final curYaw = ctrl != null
        ? (ctrl.yaw != 0.0 ? ctrl.yaw : ctrl.physics.state.heading)
        : widget.yaw;
    final curPitch = ctrl != null ? ctrl.visualPitch : widget.visualPitch;
    final curRoll = ctrl != null ? ctrl.visualRoll : widget.visualRoll;
    final curGimbal = ctrl != null ? ctrl.gimbalPitch : widget.gimbalPitch;
    final activeMap = widget.flightMap ??
        ctrl?.physics.activeMap ??
        FlightMap.dronePark;

    return SizedBox.expand(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Camada de Projeção do Terreno Real (Satélite) em Perspectiva 3D
            if (widget.showGroundMap)
              _buildGroundMap(
                curX: curX,
                curY: curY,
                curZ: curZ,
                curYaw: curYaw,
                curPitch: curPitch,
                curRoll: curRoll,
                curGimbal: curGimbal,
                activeMap: activeMap,
              ),

            // Camada 3D vetorial (Céu, Grade, Pista, Heliponto H, Geofence, Marcos, OSD)
            CustomPaint(
              painter: FpvCameraPainter(
                droneX: curX,
                droneY: curY,
                droneZ: curZ,
                yaw: curYaw,
                visualPitch: curPitch,
                visualRoll: curRoll,
                gimbalPitch: curGimbal,
                flightMap: activeMap,
                showOsd: widget.showOsd,
                showGrid: widget.showGrid,
                showGeofence: widget.showGeofence,
                showLandmarks: widget.showLandmarks,
                transparentGround: widget.transparentGround,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CustomPainter de alta performance que desenha a cena 3D do FPV.
class FpvCameraPainter extends CustomPainter {
  final double droneX;
  final double droneY;
  final double droneZ;
  final double yaw;
  final double visualPitch;
  final double visualRoll;
  final double gimbalPitch;
  final FlightMap flightMap;
  final bool showOsd;
  final bool showGrid;
  final bool showGeofence;
  final bool showLandmarks;
  final bool transparentGround;

  FpvCameraPainter({
    required this.droneX,
    required this.droneY,
    required this.droneZ,
    required this.yaw,
    required this.visualPitch,
    required this.visualRoll,
    required this.gimbalPitch,
    required this.flightMap,
    this.showOsd = true,
    this.showGrid = true,
    this.showGeofence = true,
    this.showLandmarks = true,
    this.transparentGround = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final projector = FpvCameraProjector(
      droneX: droneX,
      droneY: droneY,
      droneZ: droneZ,
      yawDeg: yaw,
      visualPitchDeg: visualPitch,
      gimbalPitchDeg: gimbalPitch,
      visualRollDeg: visualRoll,
      screenSize: size,
      vFovDeg: 60.0,
    );

    // ── Camada 1: Céu e Solo separados pela Linha do Horizonte ──
    _drawSkyAndGround(canvas, size, projector);

    // ── Camada 2: Grade de Terreno em Perspectiva 3D ──
    if (showGrid) {
      _drawPerspectiveGrid(canvas, projector);
    }

    // ── Camada 3: Pista e Ponto H (Heliponto de Home) ──
    _drawRunwayAndHomePad(canvas, projector);

    // ── Camada 4: Geofence (Cúpula/Parede 500m) e Zonas No-Fly ──
    if (showGeofence) {
      _drawGeofenceAndNfz(canvas, projector);
    }

    // ── Camada 5: Marcos 3D e Obstáculos (Gates, Torre, Prédios) ──
    if (showLandmarks) {
      _drawLandmarks(canvas, projector);
    }

    // ── Camada 6: FPV OSD (Mira, Escada de Atitude e Dados de Voo) ──
    if (showOsd) {
      _drawFpvOsd(canvas, size, projector);
    }
  }

  /// Desenha céu acima do horizonte e solo abaixo com gradientes realistas
  void _drawSkyAndGround(
      Canvas canvas, Size size, FpvCameraProjector projector) {
    final cx = size.width / 2.0;
    final cy = size.height / 2.0;
    final diag = sqrt(size.width * size.width + size.height * size.height) * 1.5;

    // Deslocamento vertical do horizonte por pitch
    // effectivePitch < 0 (olhando para baixo) desloca o horizonte para cima
    final horizonPitchOffset = projector.focalLength * tan(projector.effectivePitchRad);

    canvas.save();
    canvas.translate(cx, cy);
    // Rotação de Roll: se o drone rola para a direita, a linha do horizonte inclina para a esquerda
    canvas.rotate(-projector.rollRad);
    canvas.translate(0, horizonPitchOffset);

    // Céu (acima de Y = 0)
    final skyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF0D253F), // Azul escuro zênite
          Color(0xFF1E88E5), // Azul atmosférico
          Color(0xFF90CAF9), // Névoa ciano no horizonte
        ],
        stops: [0.0, 0.65, 1.0],
      ).createShader(Rect.fromLTRB(-diag, -diag, diag, 0));
    canvas.drawRect(Rect.fromLTRB(-diag, -diag, diag, 0), skyPaint);

    // Solo (abaixo de Y = 0)
    if (!transparentGround) {
      final groundPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF263238), // Névoa distante no horizonte
            Color(0xFF1B2E1E), // Campo verde escuro/terra
            Color(0xFF111D13), // Terreno escuro em primeiro plano
          ],
          stops: [0.0, 0.2, 1.0],
        ).createShader(Rect.fromLTRB(-diag, 0, diag, diag));
      canvas.drawRect(Rect.fromLTRB(-diag, 0, diag, diag), groundPaint);
    } else {
      // Solo translúcido com névoa atmosférica sutil no horizonte para fusão natural com os tiles de satélite
      final groundHazePaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x6690CAF9), // Névoa azul ciano suave no horizonte
            Color(0x221B2E1E), // Tonalização suave de profundidade
            Colors.transparent,
          ],
          stops: [0.0, 0.15, 0.45],
        ).createShader(Rect.fromLTRB(-diag, 0, diag, diag * 0.45));
      canvas.drawRect(Rect.fromLTRB(-diag, 0, diag, diag * 0.45), groundHazePaint);
    }

    // Linha fina luminosa do horizonte
    final horizonLinePaint = Paint()
      ..color = const Color(0x66E0F7FA)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(-diag, 0), Offset(diag, 0), horizonLinePaint);

    canvas.restore();
  }

  /// Desenha a grade de solo em perspectiva infinita que se move com o drone
  void _drawPerspectiveGrid(Canvas canvas, FpvCameraProjector projector) {
    final gridPaint = Paint()
      ..color = const Color(0x2E4DD0E1)
      ..strokeWidth = 1.0;

    const double step = 25.0; // Metros por célula de grade
    const double radius = 250.0; // Extensão visual ao redor do drone

    final minX = ((droneX - radius) / step).floor() * step;
    final maxX = ((droneX + radius) / step).ceil() * step;
    final minY = ((droneY - radius) / step).floor() * step;
    final maxY = ((droneY + radius) / step).ceil() * step;

    // Linhas paralelas ao eixo Y (Norte-Sul)
    for (double x = minX; x <= maxX; x += step) {
      final seg = projector.projectLine(x, minY, 0.0, x, maxY, 0.0);
      if (seg != null) {
        canvas.drawLine(seg[0], seg[1], gridPaint);
      }
    }

    // Linhas paralelas ao eixo X (Leste-Oeste)
    for (double y = minY; y <= maxY; y += step) {
      final seg = projector.projectLine(minX, y, 0.0, maxX, y, 0.0);
      if (seg != null) {
        canvas.drawLine(seg[0], seg[1], gridPaint);
      }
    }
  }

  /// Desenha a pista de pouso central e o heliponto com o 'H' na origem (Home)
  void _drawRunwayAndHomePad(Canvas canvas, FpvCameraProjector projector) {
    // 1. Pista de asfalto (X entre -12m e +12m, Y entre -100m e +100m)
    final runwayPaint = Paint()
      ..color = const Color(0x33263238)
      ..style = PaintingStyle.fill;
    final runwayBorderPaint = Paint()
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = 1.5;

    // Quatro cantos da pista no chão
    final p1 = projector.project(-12.0, -100.0, 0.0);
    final p2 = projector.project(12.0, -100.0, 0.0);
    final p3 = projector.project(12.0, 100.0, 0.0);
    final p4 = projector.project(-12.0, 100.0, 0.0);

    if (p1 != null && p2 != null && p3 != null && p4 != null) {
      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy)
        ..lineTo(p4.dx, p4.dy)
        ..close();
      canvas.drawPath(path, runwayPaint);
      canvas.drawPath(path, runwayBorderPaint..style = PaintingStyle.stroke);
    }

    // Linha tracejada central da pista
    final dashPaint = Paint()
      ..color = const Color(0x66FFEB3B)
      ..strokeWidth = 2.0;
    for (double y = -90.0; y <= 90.0; y += 15.0) {
      final seg = projector.projectLine(0.0, y, 0.0, 0.0, y + 8.0, 0.0);
      if (seg != null) {
        canvas.drawLine(seg[0], seg[1], dashPaint);
      }
    }

    // 2. Heliponto Ponto 'H' na coordenada Home (0, 0)
    final homeCirclePaint = Paint()
      ..color = const Color(0xFFFFC107)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    // Círculo externo (raio 8 metros)
    const int circleSegments = 24;
    const double padRadius = 8.0;
    final List<Offset> circlePoints = [];
    for (int i = 0; i <= circleSegments; i++) {
      final angle = i * 2 * pi / circleSegments;
      final px = padRadius * cos(angle);
      final py = padRadius * sin(angle);
      final pt = projector.project(px, py, 0.0);
      if (pt != null) circlePoints.add(pt);
    }
    if (circlePoints.length >= 3) {
      final circlePath = Path()..moveTo(circlePoints[0].dx, circlePoints[0].dy);
      for (int i = 1; i < circlePoints.length; i++) {
        circlePath.lineTo(circlePoints[i].dx, circlePoints[i].dy);
      }
      canvas.drawPath(circlePath, homeCirclePaint);
    }

    // Desenho da letra 'H' no centro do heliponto
    final hPaint = Paint()
      ..color = const Color(0xFFFFD54F)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final leftBar = projector.projectLine(-2.5, -4.0, 0.0, -2.5, 4.0, 0.0);
    final rightBar = projector.projectLine(2.5, -4.0, 0.0, 2.5, 4.0, 0.0);
    final midBar = projector.projectLine(-2.5, 0.0, 0.0, 2.5, 0.0, 0.0);

    if (leftBar != null) canvas.drawLine(leftBar[0], leftBar[1], hPaint);
    if (rightBar != null) canvas.drawLine(rightBar[0], rightBar[1], hPaint);
    if (midBar != null) canvas.drawLine(midBar[0], midBar[1], hPaint);
  }

  /// Desenha a Geofence de 500m (parede/domo cilíndrico vermelho) e as Zonas No-Fly
  void _drawGeofenceAndNfz(Canvas canvas, FpvCameraProjector projector) {
    final double distToCenter = sqrt(droneX * droneX + droneY * droneY);
    final double geofenceR = flightMap.radiusMeters;
    final double maxAlt = flightMap.maxAltitudeMeters;

    // A intensidade e opacidade aumentam quando o drone se aproxima do limite (>= 350m)
    final double proximityFactor = ((distToCenter - 300.0) / (geofenceR - 300.0)).clamp(0.0, 1.0);
    final double alpha = 0.12 + proximityFactor * 0.55;

    final wallPaint = Paint()
      ..color = Color.fromRGBO(255, 23, 68, alpha)
      ..style = PaintingStyle.fill;
    final wirePaint = Paint()
      ..color = Color.fromRGBO(255, 61, 0, (alpha + 0.25).clamp(0.0, 1.0))
      ..strokeWidth = 1.5;

    // Cúpula / Parede cilíndrica da Geofence com 36 segmentos radiais
    const int segments = 36;
    for (int i = 0; i < segments; i++) {
      final a1 = (i * 360.0 / segments) * pi / 180.0;
      final a2 = ((i + 1) * 360.0 / segments) * pi / 180.0;

      final x1 = geofenceR * cos(a1);
      final y1 = geofenceR * sin(a1);
      final x2 = geofenceR * cos(a2);
      final y2 = geofenceR * sin(a2);

      // Linhas da base e do topo
      final bottomSeg = projector.projectLine(x1, y1, 0.0, x2, y2, 0.0);
      final topSeg = projector.projectLine(x1, y1, maxAlt, x2, y2, maxAlt);
      final colSeg = projector.projectLine(x1, y1, 0.0, x1, y1, maxAlt);

      if (bottomSeg != null) canvas.drawLine(bottomSeg[0], bottomSeg[1], wirePaint);
      if (topSeg != null) canvas.drawLine(topSeg[0], topSeg[1], wirePaint);
      if (colSeg != null) canvas.drawLine(colSeg[0], colSeg[1], wirePaint);

      // Painel translúcido de parede
      final pB1 = projector.project(x1, y1, 0.0);
      final pB2 = projector.project(x2, y2, 0.0);
      final pT2 = projector.project(x2, y2, maxAlt);
      final pT1 = projector.project(x1, y1, maxAlt);

      if (pB1 != null && pB2 != null && pT2 != null && pT1 != null) {
        final panelPath = Path()
          ..moveTo(pB1.dx, pB1.dy)
          ..lineTo(pB2.dx, pB2.dy)
          ..lineTo(pT2.dx, pT2.dy)
          ..lineTo(pT1.dx, pT1.dy)
          ..close();
        canvas.drawPath(panelPath, wallPaint);
      }
    }

    // ── Zonas No-Fly (Cilindros de advertência) ──
    final nfzPaint = Paint()
      ..color = const Color(0x33D50000)
      ..style = PaintingStyle.fill;
    final nfzWirePaint = Paint()
      ..color = const Color(0xFFFF1744)
      ..strokeWidth = 2.0;

    for (final nfz in flightMap.noFlyZones) {
      final offset = FlightMap.latLngToMeters(nfz.center, flightMap.center);
      final nX = offset.dx;
      final nY = offset.dy;
      final nR = nfz.radiusMeters;

      const int nSegs = 20;
      for (int i = 0; i < nSegs; i++) {
        final a1 = (i * 360.0 / nSegs) * pi / 180.0;
        final a2 = ((i + 1) * 360.0 / nSegs) * pi / 180.0;

        final px1 = nX + nR * cos(a1);
        final py1 = nY + nR * sin(a1);
        final px2 = nX + nR * cos(a2);
        final py2 = nY + nR * sin(a2);

        final bot = projector.projectLine(px1, py1, 0.0, px2, py2, 0.0);
        final top = projector.projectLine(px1, py1, 50.0, px2, py2, 50.0);
        final col = projector.projectLine(px1, py1, 0.0, px1, py1, 50.0);

        if (bot != null) canvas.drawLine(bot[0], bot[1], nfzWirePaint);
        if (top != null) canvas.drawLine(top[0], top[1], nfzWirePaint);
        if (col != null) canvas.drawLine(col[0], col[1], nfzWirePaint);

        final pB1 = projector.project(px1, py1, 0.0);
        final pB2 = projector.project(px2, py2, 0.0);
        final pT2 = projector.project(px2, py2, 50.0);
        final pT1 = projector.project(px1, py1, 50.0);

        if (pB1 != null && pB2 != null && pT2 != null && pT1 != null) {
          final panel = Path()
            ..moveTo(pB1.dx, pB1.dy)
            ..lineTo(pB2.dx, pB2.dy)
            ..lineTo(pT2.dx, pT2.dy)
            ..lineTo(pT1.dx, pT1.dy)
            ..close();
          canvas.drawPath(panel, nfzPaint);
        }
      }
    }
  }

  /// Desenha marcos 3D (Gates de corrida FPV, Torre de rádio, Hangares/Prédios)
  void _drawLandmarks(Canvas canvas, FpvCameraProjector projector) {
    // 1. Portões de Corrida FPV (Gates)
    final gatePaint = Paint()
      ..color = const Color(0xFFFF6D00)
      ..strokeWidth = 3.5;
    final gateBannerPaint = Paint()
      ..color = const Color(0x8800B0FF)
      ..style = PaintingStyle.fill;

    for (final poi in flightMap.pois) {
      final pos = FlightMap.latLngToMeters(poi.position, flightMap.center);
      final gx = pos.dx;
      final gy = pos.dy;

      if (poi.type == PoiType.gate) {
        // Portão com 10m de largura e 12m de altura
        final leftPost = projector.projectLine(gx - 5.0, gy, 0.0, gx - 5.0, gy, 12.0);
        final rightPost = projector.projectLine(gx + 5.0, gy, 0.0, gx + 5.0, gy, 12.0);
        final topCross = projector.projectLine(gx - 5.0, gy, 12.0, gx + 5.0, gy, 12.0);

        if (leftPost != null) canvas.drawLine(leftPost[0], leftPost[1], gatePaint);
        if (rightPost != null) canvas.drawLine(rightPost[0], rightPost[1], gatePaint);
        if (topCross != null) canvas.drawLine(topCross[0], topCross[1], gatePaint);

        // Faixa de topo do portão
        final p1 = projector.project(gx - 5.0, gy, 10.0);
        final p2 = projector.project(gx + 5.0, gy, 10.0);
        final p3 = projector.project(gx + 5.0, gy, 12.0);
        final p4 = projector.project(gx - 5.0, gy, 12.0);
        if (p1 != null && p2 != null && p3 != null && p4 != null) {
          final banner = Path()
            ..moveTo(p1.dx, p1.dy)
            ..lineTo(p2.dx, p2.dy)
            ..lineTo(p3.dx, p3.dy)
            ..lineTo(p4.dx, p4.dy)
            ..close();
          canvas.drawPath(banner, gateBannerPaint);
        }
      } else if (poi.type == PoiType.tower) {
        // Torre treliçada com 45m de altura e 4 pernas
        final towerPaint = Paint()
          ..color = const Color(0xFFCFD8DC)
          ..strokeWidth = 2.0;

        const double baseW = 5.0;
        final apex = projector.project(gx, gy, 45.0);
        final b1 = projector.project(gx - baseW, gy - baseW, 0.0);
        final b2 = projector.project(gx + baseW, gy - baseW, 0.0);
        final b3 = projector.project(gx + baseW, gy + baseW, 0.0);
        final b4 = projector.project(gx - baseW, gy + baseW, 0.0);

        if (apex != null) {
          if (b1 != null) canvas.drawLine(b1, apex, towerPaint);
          if (b2 != null) canvas.drawLine(b2, apex, towerPaint);
          if (b3 != null) canvas.drawLine(b3, apex, towerPaint);
          if (b4 != null) canvas.drawLine(b4, apex, towerPaint);

          // Luz de balizamento vermelha no topo da torre
          final lightPaint = Paint()..color = const Color(0xFFFF1744);
          canvas.drawCircle(apex, 4.0, lightPaint);
        }
      }
    }

    // 2. Prédio / Hangar Simples 3D em (80, 50)
    _drawBuilding3D(
      canvas,
      projector,
      centerX: 80.0,
      centerY: 50.0,
      width: 24.0,
      depth: 16.0,
      height: 10.0,
      color: const Color(0xFF37474F),
    );

    // 3. Torre de Controle / Prédio em (-60, -70)
    _drawBuilding3D(
      canvas,
      projector,
      centerX: -60.0,
      centerY: -70.0,
      width: 14.0,
      depth: 14.0,
      height: 22.0,
      color: const Color(0xFF455A64),
    );
  }

  /// Desenha um edifício em caixa 3D wireframe + faces sombreadas
  void _drawBuilding3D(
    Canvas canvas,
    FpvCameraProjector projector, {
    required double centerX,
    required double centerY,
    required double width,
    required double depth,
    required double height,
    required Color color,
  }) {
    final hw = width / 2.0;
    final hd = depth / 2.0;

    final b1 = projector.project(centerX - hw, centerY - hd, 0.0);
    final b2 = projector.project(centerX + hw, centerY - hd, 0.0);
    final b3 = projector.project(centerX + hw, centerY + hd, 0.0);
    final b4 = projector.project(centerX - hw, centerY + hd, 0.0);

    final t1 = projector.project(centerX - hw, centerY - hd, height);
    final t2 = projector.project(centerX + hw, centerY - hd, height);
    final t3 = projector.project(centerX + hw, centerY + hd, height);
    final t4 = projector.project(centerX - hw, centerY + hd, height);

    // Paredes
    final wallPaint = Paint()
      ..color = color.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    if (b1 != null && b2 != null && t2 != null && t1 != null) {
      final wallPath = Path()
        ..moveTo(b1.dx, b1.dy)
        ..lineTo(b2.dx, b2.dy)
        ..lineTo(t2.dx, t2.dy)
        ..lineTo(t1.dx, t1.dy)
        ..close();
      canvas.drawPath(wallPath, wallPaint);
    }
    if (b2 != null && b3 != null && t3 != null && t2 != null) {
      final wallPath = Path()
        ..moveTo(b2.dx, b2.dy)
        ..lineTo(b3.dx, b3.dy)
        ..lineTo(t3.dx, t3.dy)
        ..lineTo(t2.dx, t2.dy)
        ..close();
      canvas.drawPath(wallPath, wallPaint);
    }
    if (b3 != null && b4 != null && t4 != null && t3 != null) {
      final wallPath = Path()
        ..moveTo(b3.dx, b3.dy)
        ..lineTo(b4.dx, b4.dy)
        ..lineTo(t4.dx, t4.dy)
        ..lineTo(t3.dx, t3.dy)
        ..close();
      canvas.drawPath(wallPath, wallPaint);
    }
    if (b4 != null && b1 != null && t1 != null && t4 != null) {
      final wallPath = Path()
        ..moveTo(b4.dx, b4.dy)
        ..lineTo(b1.dx, b1.dy)
        ..lineTo(t1.dx, t1.dy)
        ..lineTo(t4.dx, t4.dy)
        ..close();
      canvas.drawPath(wallPath, wallPaint);
    }

    if (t1 != null && t2 != null && t3 != null && t4 != null) {
      // Teto
      final roofPath = Path()
        ..moveTo(t1.dx, t1.dy)
        ..lineTo(t2.dx, t2.dy)
        ..lineTo(t3.dx, t3.dy)
        ..lineTo(t4.dx, t4.dy)
        ..close();
      canvas.drawPath(
        roofPath,
        Paint()
          ..color = color.withOpacity(0.75)
          ..style = PaintingStyle.fill,
      );
    }

    // Arestas estruturais verticais e de contorno
    final edgePaint = Paint()
      ..color = const Color(0xFF90A4AE)
      ..strokeWidth = 1.5;

    final edges = [
      projector.projectLine(centerX - hw, centerY - hd, 0.0, centerX - hw, centerY - hd, height),
      projector.projectLine(centerX + hw, centerY - hd, 0.0, centerX + hw, centerY - hd, height),
      projector.projectLine(centerX + hw, centerY + hd, 0.0, centerX + hw, centerY + hd, height),
      projector.projectLine(centerX - hw, centerY + hd, 0.0, centerX - hw, centerY + hd, height),
      projector.projectLine(centerX - hw, centerY - hd, height, centerX + hw, centerY - hd, height),
      projector.projectLine(centerX + hw, centerY - hd, height, centerX + hw, centerY + hd, height),
      projector.projectLine(centerX + hw, centerY + hd, height, centerX - hw, centerY + hd, height),
      projector.projectLine(centerX - hw, centerY + hd, height, centerX - hw, centerY - hd, height),
    ];

    for (final edge in edges) {
      if (edge != null) {
        canvas.drawLine(edge[0], edge[1], edgePaint);
      }
    }
  }

  /// Desenha elementos do HUD/OSD (Crosshair de voo, escada de atitude, ângulo de gimbal)
  void _drawFpvOsd(Canvas canvas, Size size, FpvCameraProjector projector) {
    final cx = size.width / 2.0;
    final cy = size.height / 2.0;

    final osdPaint = Paint()
      ..color = const Color(0xBB00E5FF)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // 1. Retículo / Crosshair central da câmera
    canvas.drawCircle(Offset(cx, cy), 6.0, osdPaint);
    canvas.drawLine(Offset(cx - 16, cy), Offset(cx - 8, cy), osdPaint);
    canvas.drawLine(Offset(cx + 8, cy), Offset(cx + 16, cy), osdPaint);
    canvas.drawLine(Offset(cx, cy - 16), Offset(cx, cy - 8), osdPaint);
    canvas.drawLine(Offset(cx, cy + 8), Offset(cx, cy + 16), osdPaint);

    // 2. Escada de atitude / Linhas de pitch artificial (±10°, ±20°) rotacionadas por roll
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(-projector.rollRad);

    final pitchLadderPaint = Paint()
      ..color = const Color(0x8800E5FF)
      ..strokeWidth = 1.2;

    final pitchDegrees = [-20.0, -10.0, 10.0, 20.0];
    for (final deg in pitchDegrees) {
      final yOffset = projector.focalLength * tan((deg + visualPitch + gimbalPitch) * pi / 180.0);
      if (yOffset.abs() < cy * 0.9) {
        const double w = 24.0;
        // Marcação esquerda
        canvas.drawLine(Offset(-w - 12, yOffset), Offset(-12, yOffset), pitchLadderPaint);
        // Marcação direita
        canvas.drawLine(Offset(12, yOffset), Offset(w + 12, yOffset), pitchLadderPaint);
      }
    }
    canvas.restore();

    // 3. Indicador de inclinação do Gimbal no canto
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'CAM: ${gimbalPitch.toStringAsFixed(0)}°  YAW: ${yaw.toStringAsFixed(0)}°',
        style: const TextStyle(
          color: Color(0xCC00E5FF),
          fontSize: 11,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(24, size.height - 36));
  }

  @override
  bool shouldRepaint(covariant FpvCameraPainter oldDelegate) {
    return oldDelegate.droneX != droneX ||
        oldDelegate.droneY != droneY ||
        oldDelegate.droneZ != droneZ ||
        oldDelegate.yaw != yaw ||
        oldDelegate.visualPitch != visualPitch ||
        oldDelegate.visualRoll != visualRoll ||
        oldDelegate.gimbalPitch != gimbalPitch ||
        oldDelegate.flightMap != flightMap ||
        oldDelegate.showOsd != showOsd ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.showGeofence != showGeofence ||
        oldDelegate.showLandmarks != showLandmarks ||
        oldDelegate.transparentGround != transparentGround;
  }
}
