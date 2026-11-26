import 'dart:math';
import 'package:flutter/material.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';

/// Utilitários matemáticos para o OSD (bússola, atitude e navegação para Home)
class FpvOsdMath {
  /// Calcula o rumo (bearing em graus [0, 360)) a partir da posição atual
  /// do drone (droneX, droneY) em direção à origem Home (homeX, homeY).
  ///
  /// Convenção: 0° = Norte (+Y), 90° = Leste (+X), 180° = Sul (-Y), 270° = Oeste (-X).
  static double calculateHomeBearing({
    required double droneX,
    required double droneY,
    double homeX = 0.0,
    double homeY = 0.0,
  }) {
    final dx = homeX - droneX;
    final dy = homeY - droneY;

    if (dx.abs() < 0.001 && dy.abs() < 0.001) return 0.0;

    final rad = atan2(dx, dy);
    return (rad * 180.0 / pi + 360.0) % 360.0;
  }

  /// Calcula o ângulo relativo de um alvo (ex: Home) em relação ao rumo frontal (yaw) do drone.
  /// Retorna valor normalizado em graus entre [-180.0, 180.0]:
  /// - 0°: exatamente à frente
  /// - > 0°: à direita do drone
  /// - < 0°: à esquerda do drone
  /// - ±180°: diretamente atrás do drone
  static double calculateRelativeAngle({
    required double targetBearing,
    required double currentYaw,
  }) {
    double diff = (targetBearing - currentYaw) % 360.0;
    if (diff > 180.0) diff -= 360.0;
    if (diff < -180.0) diff += 360.0;
    return diff;
  }

  /// Converte um ângulo cardeal para rótulo legível (N, NE, L, SE, S, SO, O, NO)
  static String headingToCardinal(double headingDeg) {
    final h = (headingDeg % 360.0 + 360.0) % 360.0;
    if (h >= 337.5 || h < 22.5) return 'N';
    if (h < 67.5) return 'NE';
    if (h < 112.5) return 'L';
    if (h < 157.5) return 'SE';
    if (h < 202.5) return 'S';
    if (h < 247.5) return 'SO';
    if (h < 292.5) return 'O';
    return 'NO';
  }

  /// Calcula o pitch efetivo da câmera FPV considerando atitude, gimbal e uptilt FPV.
  static double effectiveCameraPitchDeg({
    required double visualPitchDeg,
    required double gimbalPitchDeg,
    double fpvUptiltDeg = 0.0,
  }) =>
      visualPitchDeg + gimbalPitchDeg + fpvUptiltDeg;
}

/// Widget de Retícula de Voo e OSD estilo DJI / FPV.
///
/// Exibe:
/// 1. **Mira central de horizonte artificial**: boresight, indicador de roll e escada de graus de pitch (pitch ladder).
/// 2. **Bússola superior horizontal**: fita deslizante que acompanha o yaw em tempo real com marcações e pontos cardeais (N/L/S/O).
/// 3. **Marcador H flutuante**: indica a direção e distância exata para o ponto de decolagem (origem 0,0),
///    tanto na fita da bússola quanto no campo visual ou nas bordas da tela.
class FpvOsdOverlay extends StatefulWidget {
  final SimulatorController? controller;
  final CameraViewMode? cameraMode;
  final double yaw;
  final double visualPitch;
  final double visualRoll;
  final double gimbalPitch;
  final double fpvUptiltDeg;
  final double? verticalSpeedMs;
  final double? altitudeAgl;
  final double? nextGateX;
  final double? nextGateY;
  final double? nextGateZ;
  final int? nextGateNumber;
  final double droneX;
  final double droneY;
  final double droneZ;
  final double homeX;
  final double homeY;
  final bool showHorizonLadder;
  final bool showTopCompass;
  final bool showHomeMarker;

  const FpvOsdOverlay({
    super.key,
    this.controller,
    this.cameraMode,
    this.yaw = 0.0,
    this.visualPitch = 0.0,
    this.visualRoll = 0.0,
    this.gimbalPitch = 0.0,
    this.fpvUptiltDeg = 0.0,
    this.verticalSpeedMs,
    this.altitudeAgl,
    this.nextGateX,
    this.nextGateY,
    this.nextGateZ,
    this.nextGateNumber,
    this.droneX = 0.0,
    this.droneY = 0.0,
    this.droneZ = 0.0,
    this.homeX = 0.0,
    this.homeY = 0.0,
    this.showHorizonLadder = true,
    this.showTopCompass = true,
    this.showHomeMarker = true,
  });

  @override
  State<FpvOsdOverlay> createState() => _FpvOsdOverlayState();
}

class _FpvOsdOverlayState extends State<FpvOsdOverlay> {
  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerTick);
  }

  @override
  void didUpdateWidget(FpvOsdOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerTick);
      widget.controller?.addListener(_onControllerTick);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerTick);
    super.dispose();
  }

  void _onControllerTick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final curYaw = ctrl != null
        ? (ctrl.yaw != 0.0 ? ctrl.yaw : ctrl.physics.state.heading)
        : widget.yaw;
    final curPitch = ctrl != null ? ctrl.visualPitch : widget.visualPitch;
    final curRoll = ctrl != null ? ctrl.visualRoll : widget.visualRoll;
    final curGimbal = ctrl != null ? ctrl.gimbalPitch : widget.gimbalPitch;
    final curUptilt = ctrl != null
        ? (ctrl.flightMode == FlightControlMode.acro ? ctrl.fpvUptiltDeg : 0.0)
        : widget.fpvUptiltDeg;
    final curVerticalSpeed =
        ctrl != null ? ctrl.state.verticalSpeedMs : widget.verticalSpeedMs;
    final curAgl = ctrl != null ? ctrl.altitudeAgl : widget.altitudeAgl;
    final activeGate =
        (ctrl != null && ctrl.isRaceMode) ? ctrl.raceManager?.activeGate : null;
    final curX = ctrl != null ? ctrl.x : widget.droneX;
    final curY = ctrl != null ? ctrl.y : widget.droneY;
    final curZ = ctrl != null ? ctrl.z : widget.droneZ;
    final cameraMode = widget.cameraMode ?? ctrl?.cameraMode ?? CameraViewMode.fpv;
    final isThirdPerson = cameraMode == CameraViewMode.thirdPerson;
    final effectiveShowLadder = widget.showHorizonLadder && !isThirdPerson;

    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: FpvOsdPainter(
          yaw: curYaw,
          visualPitch: curPitch,
          visualRoll: curRoll,
          gimbalPitch: curGimbal,
          fpvUptiltDeg: curUptilt,
          verticalSpeedMs: curVerticalSpeed,
          altitudeAgl: curAgl,
          nextGateX: activeGate?.x ?? widget.nextGateX,
          nextGateY: activeGate?.y ?? widget.nextGateY,
          nextGateZ: activeGate?.z ?? widget.nextGateZ,
          nextGateNumber:
              activeGate != null ? (ctrl!.raceGateIndex + 1) : widget.nextGateNumber,
          droneX: curX,
          droneY: curY,
          droneZ: curZ,
          homeX: widget.homeX,
          homeY: widget.homeY,
          showHorizonLadder: effectiveShowLadder,
          showTopCompass: widget.showTopCompass,
          showHomeMarker: widget.showHomeMarker,
        ),
      ),
    );
  }
}

/// CustomPainter que desenha os elementos gráficos da retícula de voo OSD
class FpvOsdPainter extends CustomPainter {
  final double yaw;
  final double visualPitch;
  final double visualRoll;
  final double gimbalPitch;
  final double fpvUptiltDeg;
  final double? verticalSpeedMs;
  final double? altitudeAgl;
  final double? nextGateX;
  final double? nextGateY;
  final double? nextGateZ;
  final int? nextGateNumber;
  final double droneX;
  final double droneY;
  final double droneZ;
  final double homeX;
  final double homeY;
  final bool showHorizonLadder;
  final bool showTopCompass;
  final bool showHomeMarker;

  FpvOsdPainter({
    required this.yaw,
    required this.visualPitch,
    required this.visualRoll,
    required this.gimbalPitch,
    this.fpvUptiltDeg = 0.0,
    this.verticalSpeedMs,
    this.altitudeAgl,
    this.nextGateX,
    this.nextGateY,
    this.nextGateZ,
    this.nextGateNumber,
    required this.droneX,
    required this.droneY,
    required this.droneZ,
    this.homeX = 0.0,
    this.homeY = 0.0,
    this.showHorizonLadder = true,
    this.showTopCompass = true,
    this.showHomeMarker = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final cx = size.width / 2.0;
    final cy = size.height / 2.0;

    // Distância até Home e Rumo para Home
    final distToHome = sqrt(pow(homeX - droneX, 2) + pow(homeY - droneY, 2));
    final homeBearing = FpvOsdMath.calculateHomeBearing(
      droneX: droneX,
      droneY: droneY,
      homeX: homeX,
      homeY: homeY,
    );
    final homeRelativeAngle = FpvOsdMath.calculateRelativeAngle(
      targetBearing: homeBearing,
      currentYaw: yaw,
    );

    // ── 1. Bússola Superior (Heading Tape com pontos cardeais N/L/S/O) ──
    if (showTopCompass) {
      _drawTopCompassTape(canvas, size, cx, homeBearing);
    }

    // ── 2. Mira de Horizonte Artificial e Escada de Pitch ──
    if (showHorizonLadder) {
      _drawArtificialHorizon(canvas, size, cx, cy);
    }

    // ── 3. Marcador H Flutuante (Aponta sempre para a origem 0,0) ──
    if (showHomeMarker) {
      _drawFloatingHomeMarker(canvas, size, cx, cy, distToHome, homeRelativeAngle);
    }

    // ── 4. Seta lateral para próximo portal quando fora do campo de visão ──
    if (nextGateX != null && nextGateY != null) {
      _drawNextGateEdgeMarker(canvas, size, cy);
    }
  }

  /// Desenha a fita de bússola horizontal superior no estilo HUD aeronáutico/DJI
  void _drawTopCompassTape(Canvas canvas, Size size, double cx, double homeBearing) {
    const double compassTop = 64.0; // Logo abaixo da barra de telemetria
    const double tapeWidth = 320.0;
    const double tapeHeight = 32.0;
    const double pixelsPerDegree = 3.2; // 1° = 3.2 pixels
    const double halfWidth = tapeWidth / 2.0;

    final tapeRect = Rect.fromCenter(
      center: Offset(cx, compassTop + tapeHeight / 2.0),
      width: tapeWidth,
      height: tapeHeight,
    );

    // Fundo translúcido com cantos arredondados
    final bgPaint = Paint()
      ..color = Colors.black.withOpacity(0.55)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = const Color(0x6600E5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawRRect(RRect.fromRectAndRadius(tapeRect, const Radius.circular(6)), bgPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(tapeRect, const Radius.circular(6)), borderPaint);

    // Salva o canvas com clipping para a janela da fita da bússola
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(tapeRect, const Radius.circular(6)));

    final tickPaint = Paint()
      ..color = const Color(0xBB00E5FF)
      ..strokeWidth = 1.2;
    final cardTickPaint = Paint()
      ..color = const Color(0xFFFFD54F)
      ..strokeWidth = 2.0;

    // Renderiza marcas de -60° a +60° visíveis na janela
    final minDeg = (yaw - (halfWidth / pixelsPerDegree)).floor();
    final maxDeg = (yaw + (halfWidth / pixelsPerDegree)).ceil();

    for (int deg = minDeg; deg <= maxDeg; deg++) {
      final normDeg = (deg % 360 + 360) % 360;
      final xOffset = cx + (deg - yaw) * pixelsPerDegree;

      if (normDeg % 30 == 0) {
        // Marca principal a cada 30°
        final isCardinal = normDeg % 90 == 0;
        final p = isCardinal ? cardTickPaint : tickPaint;
        final tickH = isCardinal ? 10.0 : 8.0;

        canvas.drawLine(
          Offset(xOffset, compassTop + tapeHeight - tickH),
          Offset(xOffset, compassTop + tapeHeight),
          p,
        );

        // Texto do ponto cardeal ou valor numérico
        String label;
        if (normDeg == 0) {
          label = 'N';
        } else if (normDeg == 90) {
          label = 'L'; // Leste
        } else if (normDeg == 180) {
          label = 'S';
        } else if (normDeg == 270) {
          label = 'O'; // Oeste
        } else {
          label = normDeg.toString();
        }

        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: isCardinal ? const Color(0xFFFFD54F) : const Color(0xDD00E5FF),
              fontSize: isCardinal ? 10 : 8,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        tp.paint(canvas, Offset(xOffset - tp.width / 2.0, compassTop + 3.0));
      } else if (normDeg % 10 == 0) {
        // Marca intermediária a cada 10°
        canvas.drawLine(
          Offset(xOffset, compassTop + tapeHeight - 5.0),
          Offset(xOffset, compassTop + tapeHeight),
          tickPaint,
        );
      }
    }

    // Indicador de Home [H] na fita da bússola
    final homeDiff = FpvOsdMath.calculateRelativeAngle(
      targetBearing: homeBearing,
      currentYaw: yaw,
    );
    final homeTapeX = cx + homeDiff * pixelsPerDegree;
    if (homeTapeX >= cx - halfWidth && homeTapeX <= cx + halfWidth) {
      final hMarkerPaint = Paint()
        ..color = const Color(0xFFFFC107)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(homeTapeX, compassTop + tapeHeight - 14), 6.5, hMarkerPaint);

      final hText = TextPainter(
        text: const TextSpan(
          text: 'H',
          style: TextStyle(
            color: Colors.black,
            fontSize: 8.5,
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      hText.paint(canvas, Offset(homeTapeX - hText.width / 2.0, compassTop + tapeHeight - 14 - hText.height / 2.0));
    }

    canvas.restore();

    // ── Ponteiro / Marcador central fixo no topo da fita com leitura digital ──
    final pointerPaint = Paint()
      ..color = const Color(0xFFFFD54F)
      ..style = PaintingStyle.fill;

    final pointerPath = Path()
      ..moveTo(cx, compassTop + tapeHeight + 5)
      ..lineTo(cx - 5, compassTop + tapeHeight)
      ..lineTo(cx + 5, compassTop + tapeHeight)
      ..close();
    canvas.drawPath(pointerPath, pointerPaint);

    // Caixa de leitura digital do Heading atual (ex: 045° N)
    final yawNormalized = (yaw % 360.0 + 360.0) % 360.0;
    final cardinal = FpvOsdMath.headingToCardinal(yawNormalized);
    final headingString = '${yawNormalized.toStringAsFixed(0).padLeft(3, '0')}° $cardinal';

    final textHeading = TextPainter(
      text: TextSpan(
        text: headingString,
        style: const TextStyle(
          color: Color(0xFFFFD54F),
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final headingBoxRect = Rect.fromCenter(
      center: Offset(cx, compassTop + tapeHeight + 14),
      width: textHeading.width + 12,
      height: 16,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(headingBoxRect, const Radius.circular(3)), bgPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(headingBoxRect, const Radius.circular(3)), borderPaint);
    textHeading.paint(canvas, Offset(cx - textHeading.width / 2.0, compassTop + tapeHeight + 14 - textHeading.height / 2.0));
  }

  /// Desenha o retículo de mira de horizonte artificial e escada de graus de inclinação
  void _drawArtificialHorizon(Canvas canvas, Size size, double cx, double cy) {
    // 1. Mira / Boresight central fixo da aeronave (crosshair aeronáutico com asas estilizadas)
    final hudPaint = Paint()
      ..color = const Color(0xDD00E5FF)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // Círculo central com ponto
    canvas.drawCircle(Offset(cx, cy), 5.0, hudPaint);
    canvas.drawCircle(Offset(cx, cy), 1.0, Paint()..color = const Color(0xFF00E5FF)..style = PaintingStyle.fill);

    // Asas da mira de horizonte
    canvas.drawLine(Offset(cx - 36, cy), Offset(cx - 14, cy), hudPaint);
    canvas.drawLine(Offset(cx - 14, cy), Offset(cx - 14, cy + 6), hudPaint);
    canvas.drawLine(Offset(cx + 14, cy), Offset(cx + 36, cy), hudPaint);
    canvas.drawLine(Offset(cx + 14, cy), Offset(cx + 14, cy + 6), hudPaint);

    // 2. Escada de Pitch (rotacionada por roll e transladada por visualPitch + gimbalPitch)
    canvas.save();
    canvas.translate(cx, cy);
    final rollRad = visualRoll * pi / 180.0;
    canvas.rotate(-rollRad);

    final ladderPaint = Paint()
      ..color = const Color(0xAA00E5FF)
      ..strokeWidth = 1.4;
    final ladderDashPaint = Paint()
      ..color = const Color(0x99FFAB40) // Tom alaranjado para graus negativos de solo
      ..strokeWidth = 1.4;

    // Escala de pixels por grau de inclinação vertical (calibrado com fov 60°)
    const halfFovRad = 30.0 * pi / 180.0;
    final focalLength = cy / tan(halfFovRad);

    final pitchSteps = [-30.0, -20.0, -10.0, 0.0, 10.0, 20.0, 30.0];
    final effectivePitch = FpvOsdMath.effectiveCameraPitchDeg(
      visualPitchDeg: visualPitch,
      gimbalPitchDeg: gimbalPitch,
      fpvUptiltDeg: fpvUptiltDeg,
    );
    for (final deg in pitchSteps) {
      final totalPitch = (deg + effectivePitch) * pi / 180.0;
      final yOffset = focalLength * tan(totalPitch);

      if (yOffset.abs() > cy * 0.85) continue;

      if (deg == 0.0) {
        // Linha central do horizonte (0°)
        const double w0 = 70.0;
        const double gap = 45.0;
        final h0Paint = Paint()
          ..color = const Color(0xCC00E5FF)
          ..strokeWidth = 1.8;
        canvas.drawLine(Offset(-w0, yOffset), Offset(-gap, yOffset), h0Paint);
        canvas.drawLine(Offset(gap, yOffset), Offset(w0, yOffset), h0Paint);
      } else {
        final isPositive = deg > 0;
        final paintToUse = isPositive ? ladderPaint : ladderDashPaint;
        const double barW = 32.0;
        const double gap = 38.0;
        final double hookLen = isPositive ? 5.0 : -5.0;

        // Barra esquerda
        canvas.drawLine(Offset(-gap - barW, yOffset), Offset(-gap, yOffset), paintToUse);
        canvas.drawLine(Offset(-gap - barW, yOffset), Offset(-gap - barW, yOffset + hookLen), paintToUse);

        // Barra direita
        canvas.drawLine(Offset(gap, yOffset), Offset(gap + barW, yOffset), paintToUse);
        canvas.drawLine(Offset(gap + barW, yOffset), Offset(gap + barW, yOffset + hookLen), paintToUse);

        // Rótulo numérico do degrau
        final degStr = deg.abs().toInt().toString();
        final textDeg = TextPainter(
          text: TextSpan(
            text: degStr,
            style: TextStyle(
              color: isPositive ? const Color(0xCC00E5FF) : const Color(0xCCFFAB40),
              fontSize: 8.5,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        textDeg.paint(canvas, Offset(-gap - barW - textDeg.width - 4, yOffset - textDeg.height / 2.0));
        textDeg.paint(canvas, Offset(gap + barW + 4, yOffset - textDeg.height / 2.0));
      }
    }

    canvas.restore();

    if (altitudeAgl != null || verticalSpeedMs != null) {
      final parts = <String>[
        if (altitudeAgl != null) 'AGL ${altitudeAgl!.toStringAsFixed(1)}m',
        if (verticalSpeedMs != null)
          'V/S ${verticalSpeedMs! >= 0 ? '+' : ''}${verticalSpeedMs!.toStringAsFixed(1)}',
      ];
      final tpStats = TextPainter(
        text: TextSpan(
          text: parts.join(' · '),
          style: const TextStyle(
            color: Color(0xCC00E5FF),
            fontSize: 9.0,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tpStats.paint(canvas, Offset(cx - tpStats.width / 2.0, cy + 16.0));
    }
  }

  /// Desenha o marcador H flutuante que aponta com precisão para a origem Home (0,0)
  void _drawFloatingHomeMarker(
    Canvas canvas,
    Size size,
    double cx,
    double cy,
    double distToHome,
    double homeRelativeAngle,
  ) {
    const double hFov = 75.0; // Campo de visão horizontal aproximado
    const double halfHFov = hFov / 2.0;

    final markerBgPaint = Paint()
      ..color = Colors.black.withOpacity(0.8)
      ..style = PaintingStyle.fill;
    final markerBorderPaint = Paint()
      ..color = const Color(0xFFFFC107)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    final homeGlowPaint = Paint()
      ..color = const Color(0xFFFFC107)
      ..style = PaintingStyle.fill;

    // Se o ponto de Home estiver dentro do campo de visão frontal horizontal:
    if (homeRelativeAngle.abs() <= halfHFov) {
      final normX = homeRelativeAngle / halfHFov; // [-1.0, 1.0]
      final screenX = cx + normX * (cx * 0.75);

      // Posicionamento vertical dinâmico próximo ao horizonte
      const halfFovRad = 30.0 * pi / 180.0;
      final focalLength = cy / tan(halfFovRad);
      final effectivePitch = FpvOsdMath.effectiveCameraPitchDeg(
        visualPitchDeg: visualPitch,
        gimbalPitchDeg: gimbalPitch,
        fpvUptiltDeg: fpvUptiltDeg,
      );
      final horizonY = cy + focalLength * tan(effectivePitch * pi / 180.0);
      final screenY = horizonY.clamp(cy - 120.0, cy + 120.0);

      // Ícone flutuante Home [H]
      final padRect = Rect.fromCenter(center: Offset(screenX, screenY), width: 38, height: 26);
      canvas.drawRRect(RRect.fromRectAndRadius(padRect, const Radius.circular(6)), markerBgPaint);
      canvas.drawRRect(RRect.fromRectAndRadius(padRect, const Radius.circular(6)), markerBorderPaint);

      // Letra H em destaque dourado
      final hText = TextPainter(
        text: TextSpan(
          text: 'H',
          style: const TextStyle(
            color: Color(0xFFFFC107),
            fontSize: 12,
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
          ),
          children: [
            TextSpan(
              text: ' ${distToHome.toStringAsFixed(0)}m',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8.5,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      hText.paint(canvas, Offset(screenX - hText.width / 2.0, screenY - hText.height / 2.0));

      // Linha guia vertical sutil até o chão
      canvas.drawLine(
        Offset(screenX, screenY + 13),
        Offset(screenX, screenY + 22),
        markerBorderPaint..strokeWidth = 1.2,
      );
      canvas.drawCircle(Offset(screenX, screenY + 23), 2.0, homeGlowPaint);
    } else {
      // ── Quando Home estiver fora da tela (à esquerda, direita ou atrás) ──
      // Desenha um indicador fixado na borda lateral com seta de navegação
      final isRight = homeRelativeAngle > 0;
      final edgeX = isRight ? (size.width - 34.0) : 34.0;
      final edgeY = cy;

      final arrowPath = Path();
      if (isRight) {
        arrowPath.moveTo(edgeX + 10, edgeY);
        arrowPath.lineTo(edgeX, edgeY - 8);
        arrowPath.lineTo(edgeX, edgeY + 8);
      } else {
        arrowPath.moveTo(edgeX - 10, edgeY);
        arrowPath.lineTo(edgeX, edgeY - 8);
        arrowPath.lineTo(edgeX, edgeY + 8);
      }
      arrowPath.close();

      canvas.drawPath(arrowPath, homeGlowPaint);

      // Caixa de distância na borda
      final edgeBox = Rect.fromCenter(
        center: Offset(isRight ? edgeX - 22 : edgeX + 22, edgeY),
        width: 38,
        height: 22,
      );
      canvas.drawRRect(RRect.fromRectAndRadius(edgeBox, const Radius.circular(4)), markerBgPaint);
      canvas.drawRRect(RRect.fromRectAndRadius(edgeBox, const Radius.circular(4)), markerBorderPaint..strokeWidth = 1.0);

      final edgeText = TextPainter(
        text: TextSpan(
          text: 'H ${distToHome.toStringAsFixed(0)}m',
          style: const TextStyle(
            color: Color(0xFFFFC107),
            fontSize: 8,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      edgeText.paint(canvas, Offset(edgeBox.center.dx - edgeText.width / 2.0, edgeBox.center.dy - edgeText.height / 2.0));
    }
  }

  void _drawNextGateEdgeMarker(Canvas canvas, Size size, double cy) {
    final gx = nextGateX!;
    final gy = nextGateY!;
    final gz = nextGateZ ?? droneZ;
    final bearing = FpvOsdMath.calculateHomeBearing(
      droneX: droneX,
      droneY: droneY,
      homeX: gx,
      homeY: gy,
    );
    final relAngle = FpvOsdMath.calculateRelativeAngle(
      targetBearing: bearing,
      currentYaw: yaw,
    );
    if (relAngle.abs() <= 37.5) return;

    final dist = sqrt(pow(gx - droneX, 2) + pow(gy - droneY, 2) + pow(gz - droneZ, 2));
    final isRight = relAngle > 0;
    final edgeX = isRight ? (size.width - 34.0) : 34.0;
    final edgeY = cy - 34.0;

    final gateGlowPaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.fill;
    final arrowPath = Path();
    if (isRight) {
      arrowPath.moveTo(edgeX + 10, edgeY);
      arrowPath.lineTo(edgeX, edgeY - 7);
      arrowPath.lineTo(edgeX, edgeY + 7);
    } else {
      arrowPath.moveTo(edgeX - 10, edgeY);
      arrowPath.lineTo(edgeX, edgeY - 7);
      arrowPath.lineTo(edgeX, edgeY + 7);
    }
    arrowPath.close();
    canvas.drawPath(arrowPath, gateGlowPaint);

    final label = 'G${nextGateNumber ?? ''} ${dist.toStringAsFixed(0)}m';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFF00E5FF),
          fontSize: 8.5,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final box = Rect.fromCenter(
      center: Offset(isRight ? edgeX - 24 : edgeX + 24, edgeY),
      width: max(40.0, tp.width + 10),
      height: 20,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      Paint()..color = Colors.black.withOpacity(0.82),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      Paint()
        ..color = const Color(0xFF00E5FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    tp.paint(canvas, Offset(box.center.dx - tp.width / 2.0, box.center.dy - tp.height / 2.0));
  }

  @override
  bool shouldRepaint(covariant FpvOsdPainter oldDelegate) {
    return oldDelegate.yaw != yaw ||
        oldDelegate.visualPitch != visualPitch ||
        oldDelegate.visualRoll != visualRoll ||
        oldDelegate.gimbalPitch != gimbalPitch ||
        oldDelegate.fpvUptiltDeg != fpvUptiltDeg ||
        oldDelegate.verticalSpeedMs != verticalSpeedMs ||
        oldDelegate.altitudeAgl != altitudeAgl ||
        oldDelegate.nextGateX != nextGateX ||
        oldDelegate.nextGateY != nextGateY ||
        oldDelegate.nextGateZ != nextGateZ ||
        oldDelegate.nextGateNumber != nextGateNumber ||
        oldDelegate.droneX != droneX ||
        oldDelegate.droneY != droneY ||
        oldDelegate.droneZ != droneZ ||
        oldDelegate.homeX != homeX ||
        oldDelegate.homeY != homeY ||
        oldDelegate.showHorizonLadder != showHorizonLadder ||
        oldDelegate.showTopCompass != showTopCompass ||
        oldDelegate.showHomeMarker != showHomeMarker;
  }
}
