import 'dart:math';
import 'package:flutter/material.dart';
import 'package:drone_simulator/models/drone_state.dart';
import 'package:drone_simulator/simulation/simulator_controller.dart';

/// Overlay que renderiza o modelo vetorial 3D do Drone em visão de 3ª Pessoa (Chase Cam).
///
/// Posicionado no terço inferior da tela, logo acima dos joysticks virtuais, com:
/// - Chassi em fibra de carbono / grafite escuro com detalhes aerodinâmicos
/// - 4 braços em configuração X com perspectiva cônica de profundidade
/// - Motores brushless e hélices (discos translúcidos em rotação quando armado / lâminas estáticas pousado)
/// - LED de cauda com status dinâmico (Verde = voo normal, Âmbar/Vermelho piscante = RTH/Alerta, Azul = desarmado)
/// - Física de atitude (inclinação de roll e perspectiva de pitch)
/// - Sombra dinâmica no chão que suaviza e desaparece conforme a altitude aumenta (> 15m)
class ChaseDroneOverlay extends StatelessWidget {
  final SimulatorController? controller;
  final double altitude;
  final double pitch;
  final double roll;
  final FlightMode flightMode;
  final double speedKmh;
  final bool isGeofenceWarning;
  final bool isNoFlyWarning;
  final double batteryPercent;
  final double? customCenterYFactor;

  const ChaseDroneOverlay({
    super.key,
    this.controller,
    this.altitude = 0.0,
    this.pitch = 0.0,
    this.roll = 0.0,
    this.flightMode = FlightMode.disarmed,
    this.speedKmh = 0.0,
    this.isGeofenceWarning = false,
    this.isNoFlyWarning = false,
    this.batteryPercent = 100.0,
    this.customCenterYFactor,
  });

  @override
  Widget build(BuildContext context) {
    if (controller != null) {
      return AnimatedBuilder(
        animation: controller!,
        builder: (context, _) {
          final state = controller!.state;
          return _buildPainter(
            altitude: state.altitude,
            pitch: state.visualPitch,
            roll: state.visualRoll,
            flightMode: state.flightMode,
            speedKmh: state.speedKmh,
            isGeofenceWarning: state.isGeofenceWarning || state.isGeofenceBreach,
            isNoFlyWarning: state.isNoFlyWarning || state.inNoFlyZone,
            batteryPercent: state.batteryPercent,
          );
        },
      );
    }

    return _buildPainter(
      altitude: altitude,
      pitch: pitch,
      roll: roll,
      flightMode: flightMode,
      speedKmh: speedKmh,
      isGeofenceWarning: isGeofenceWarning,
      isNoFlyWarning: isNoFlyWarning,
      batteryPercent: batteryPercent,
    );
  }

  Widget _buildPainter({
    required double altitude,
    required double pitch,
    required double roll,
    required FlightMode flightMode,
    required double speedKmh,
    required bool isGeofenceWarning,
    required bool isNoFlyWarning,
    required double batteryPercent,
  }) {
    return IgnorePointer(
      key: const Key('chase_drone_overlay_pointer'),
      child: CustomPaint(
        size: Size.infinite,
        painter: ChaseDronePainter(
          altitude: altitude,
          pitch: pitch,
          roll: roll,
          flightMode: flightMode,
          speedKmh: speedKmh,
          isGeofenceWarning: isGeofenceWarning,
          isNoFlyWarning: isNoFlyWarning,
          batteryPercent: batteryPercent,
          centerYFactor: customCenterYFactor ?? 0.68,
        ),
      ),
    );
  }
}

/// CustomPainter de alto desempenho que desenha o drone quadcopter vetorial em 3ª pessoa.
class ChaseDronePainter extends CustomPainter {
  final double altitude;
  final double pitch;
  final double roll;
  final FlightMode flightMode;
  final double speedKmh;
  final bool isGeofenceWarning;
  final bool isNoFlyWarning;
  final double batteryPercent;
  final double centerYFactor;

  ChaseDronePainter({
    required this.altitude,
    required this.pitch,
    required this.roll,
    required this.flightMode,
    required this.speedKmh,
    required this.isGeofenceWarning,
    required this.isNoFlyWarning,
    required this.batteryPercent,
    this.centerYFactor = 0.68,
  });

  bool get isArmed => flightMode != FlightMode.disarmed;

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2.0;
    final centerY = size.height * centerYFactor;

    // ── 1. Sombra Dinâmica no Solo (Projeção quando altitude < 15m) ──
    _paintGroundShadow(canvas, centerX, centerY);

    // ── 2. Renderização do Drone com Roll e Perspectiva de Pitch ──
    canvas.save();
    canvas.translate(centerX, centerY);

    // Rotação de Roll (graus para radianos)
    final rollRad = roll * pi / 180.0;
    canvas.rotate(rollRad);

    // Offset vertical derivado do Pitch (-25° a +25°)
    // Pitch negativo (avançando/nariz para baixo) inclina o drone para a frente
    // revelando a parte superior do chassi. Pitch positivo revela a barriga.
    final double pitchNorm = (pitch / 25.0).clamp(-1.0, 1.0);
    final double pitchOffset = pitchNorm * 14.0;

    // Coordenadas dos 4 motores em configuração X (profundidade de perspectiva):
    // Braços dianteiros (mais distantes/menores):
    final frontLeft = Offset(-68.0, -32.0 + pitchOffset);
    final frontRight = Offset(68.0, -32.0 + pitchOffset);

    // Braços traseiros (mais próximos ao piloto/maiores):
    final rearLeft = Offset(-82.0, 28.0 - pitchOffset * 0.4);
    final rearRight = Offset(82.0, 28.0 - pitchOffset * 0.4);

    // ── A. Braços do Chassi (Fibra de Carbono) ──
    _paintArms(canvas, frontLeft, frontRight, rearLeft, rearRight);

    // ── B. Pés de Pouso / Skids Traseiros ──
    _paintLandingSkids(canvas, rearLeft, rearRight, pitchNorm);

    // ── C. Motores e Hélices Dianteiros (em perspectiva atrás do corpo se visto de cima) ──
    _paintMotorAndPropeller(canvas, frontLeft, isFront: true);
    _paintMotorAndPropeller(canvas, frontRight, isFront: true);

    // ── D. Corpo Central / Fuselagem Aerodinâmica ──
    _paintFuselage(canvas, pitchNorm);

    // ── E. Motores e Hélices Traseiros ──
    _paintMotorAndPropeller(canvas, rearLeft, isFront: false);
    _paintMotorAndPropeller(canvas, rearRight, isFront: false);

    // ── F. LEDs de Navegação e Cauda ──
    _paintLeds(canvas, rearLeft, rearRight, pitchNorm);

    canvas.restore();
  }

  /// Desenha a sombra dinâmica projetada no solo
  void _paintGroundShadow(Canvas canvas, double cx, double cy) {
    if (altitude >= 15.0) return;

    // progressão da altitude de 0m a 15m (0.0 = colado no chão, 1.0 = desvanecido)
    final altFactor = (altitude / 15.0).clamp(0.0, 1.0);
    final opacity = (1.0 - altFactor) * 0.50;
    if (opacity <= 0.01) return;

    final shadowY = cy + 40.0 + altFactor * 35.0;
    final shadowWidth = 130.0 * (1.0 + altFactor * 0.4);
    final shadowHeight = 32.0 * (1.0 - altFactor * 0.3);

    final shadowRect = Rect.fromCenter(
      center: Offset(cx, shadowY),
      width: shadowWidth,
      height: shadowHeight,
    );

    final shadowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.black.withOpacity(opacity),
          Colors.black.withOpacity(opacity * 0.4),
          Colors.transparent,
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(shadowRect);

    canvas.drawOval(shadowRect, shadowPaint);
  }

  /// Braços estruturais em X
  void _paintArms(
    Canvas canvas,
    Offset fl,
    Offset fr,
    Offset rl,
    Offset rr,
  ) {
    final armPaint = Paint()
      ..color = const Color(0xFF1E2124)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final highlightPaint = Paint()
      ..color = const Color(0xFF383C42)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Braços traseiros (mais grossos por proximidade)
    armPaint.strokeWidth = 10.0;
    highlightPaint.strokeWidth = 2.0;
    canvas.drawLine(const Offset(-12, 10), rl, armPaint);
    canvas.drawLine(const Offset(12, 10), rr, armPaint);
    canvas.drawLine(const Offset(-12, 8), Offset(rl.dx * 0.9, rl.dy * 0.9), highlightPaint);
    canvas.drawLine(const Offset(12, 8), Offset(rr.dx * 0.9, rr.dy * 0.9), highlightPaint);

    // Braços dianteiros (mais finos por perspectiva)
    armPaint.strokeWidth = 8.0;
    canvas.drawLine(const Offset(-10, -8), fl, armPaint);
    canvas.drawLine(const Offset(10, -8), fr, armPaint);
    canvas.drawLine(const Offset(-10, -10), Offset(fl.dx * 0.9, fl.dy * 0.9), highlightPaint);
    canvas.drawLine(const Offset(10, -10), Offset(fr.dx * 0.9, fr.dy * 0.9), highlightPaint);
  }

  /// Pés de pouso sob os motores traseiros
  void _paintLandingSkids(Canvas canvas, Offset rl, Offset rr, double pitchNorm) {
    final skidPaint = Paint()
      ..color = const Color(0xFF121416)
      ..style = PaintingStyle.fill;

    const skidHeight = 12.0;
    const skidWidth = 5.0;

    // Esquerdo
    final leftRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(rl.dx - skidWidth / 2, rl.dy + 4, skidWidth, skidHeight),
      const Radius.circular(2),
    );
    canvas.drawRRect(leftRect, skidPaint);

    // Direito
    final rightRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(rr.dx - skidWidth / 2, rr.dy + 4, skidWidth, skidHeight),
      const Radius.circular(2),
    );
    canvas.drawRRect(rightRect, skidPaint);
  }

  /// Motores brushless cilíndricos e discos de hélice
  void _paintMotorAndPropeller(Canvas canvas, Offset pos, {required bool isFront}) {
    final motorRadius = isFront ? 9.0 : 11.0;
    final propRadius = isFront ? 34.0 : 42.0;

    // ── Disco Translúcido de Hélice (Spinning Prop Disc) ──
    if (isArmed) {
      final propRect = Rect.fromCircle(center: pos, radius: propRadius);
      final propPaint = Paint()
        ..style = PaintingStyle.fill
        ..shader = RadialGradient(
          colors: [
            Colors.cyanAccent.withOpacity(0.04),
            Colors.cyanAccent.withOpacity(0.20),
            Colors.white.withOpacity(0.35),
            Colors.transparent,
          ],
          stops: const [0.0, 0.70, 0.92, 1.0],
        ).createShader(propRect);

      canvas.drawOval(
        Rect.fromCenter(
          center: pos,
          width: propRadius * 2.0,
          height: propRadius * 1.2, // Elipse achatada pela perspectiva do plano horizontal
        ),
        propPaint,
      );

      // Aro externo sutil do disco de rotação
      final ringPaint = Paint()
        ..color = Colors.cyanAccent.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawOval(
        Rect.fromCenter(
          center: pos,
          width: propRadius * 1.95,
          height: propRadius * 1.15,
        ),
        ringPaint,
      );
    } else {
      // Hélices estáticas (3 pás em fibra) quando desarmado no chão
      final bladePaint = Paint()
        ..color = const Color(0xFF2C3238)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = isFront ? 3.0 : 4.0;

      for (int i = 0; i < 3; i++) {
        final angle = (i * 2.0 * pi / 3.0) + (isFront ? 0.3 : 0.8);
        final bladeEnd = Offset(
          pos.dx + cos(angle) * (propRadius * 0.85),
          pos.dy + sin(angle) * (propRadius * 0.55),
        );
        canvas.drawLine(pos, bladeEnd, bladePaint);
      }
    }

    // ── Motor Brushless (Campânula metálica com anel de topo) ──
    final bellPaint = Paint()
      ..color = const Color(0xFF2B2E33)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, motorRadius, bellPaint);

    final statorRingPaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(pos, motorRadius * 0.75, statorRingPaint);

    // Porca central de fixação / Eixo
    final nutPaint = Paint()
      ..color = const Color(0xFFD6D9E0)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, motorRadius * 0.35, nutPaint);
  }

  /// Fuselagem central estilizada e aerodinâmica
  void _paintFuselage(Canvas canvas, double pitchNorm) {
    // Dimensões do corpo
    const bodyWidth = 36.0;
    final bodyHeight = 56.0 + pitchNorm * 8.0;

    // Sombra interna do corpo
    final bodyShadowRect = Rect.fromCenter(
      center: Offset(0, 4.0 - pitchNorm * 3.0),
      width: bodyWidth + 4,
      height: bodyHeight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyShadowRect, const Radius.circular(14)),
      Paint()..color = Colors.black.withOpacity(0.40),
    );

    // Chassi principal (Canopy em policarbonato/fibra de carbono fosco)
    final bodyRect = Rect.fromCenter(
      center: Offset(0, -pitchNorm * 3.0),
      width: bodyWidth,
      height: bodyHeight,
    );

    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF32363D),
          Color(0xFF212429),
          Color(0xFF16181B),
        ],
        stops: [0.0, 0.6, 1.0],
      ).createShader(bodyRect);

    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(12)),
      bodyPaint,
    );

    // Friso aerodinâmico esportivo central (Racing Stripe ciano)
    final stripePaint = Paint()
      ..color = const Color(0xFF00E5FF).withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawLine(
      Offset(0, -bodyHeight * 0.38 - pitchNorm * 3.0),
      Offset(0, bodyHeight * 0.28 - pitchNorm * 3.0),
      stripePaint,
    );

    // FPV Câmera / Gimbal frontal (visível na ponta superior)
    final camPodPaint = Paint()
      ..color = const Color(0xFF0F1012)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, -bodyHeight * 0.45 - pitchNorm * 3.0),
          width: 16.0,
          height: 10.0,
        ),
        const Radius.circular(3),
      ),
      camPodPaint,
    );

    // Lente da câmera frontal
    final lensPaint = Paint()
      ..color = const Color(0xFF00B0FF)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(0, -bodyHeight * 0.45 - pitchNorm * 3.0),
      2.5,
      lensPaint,
    );
  }

  /// LEDs de cauda e sinalizadores nos braços traseiros
  void _paintLeds(Canvas canvas, Offset rl, Offset rr, double pitchNorm) {
    // Cor do LED principal traseiro baseada no estado de voo
    Color ledColor;
    if (flightMode == FlightMode.rtl) {
      // Âmbar pulsante em RTH
      ledColor = const Color(0xFFFF9100);
    } else if (isGeofenceWarning || isNoFlyWarning || batteryPercent < 15.0) {
      // Vermelho alerta
      ledColor = const Color(0xFFFF1744);
    } else if (isArmed) {
      // Verde voo normal
      ledColor = const Color(0xFF00E676);
    } else {
      // Azul desarmado / standby
      ledColor = const Color(0xFF00B0FF);
    }

    final ledCenter = Offset(0, 24.0 - pitchNorm * 3.0);

    // Brilho difuso (Glow)
    final glowPaint = Paint()
      ..color = ledColor.withOpacity(0.40)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(ledCenter, 9.0, glowPaint);

    // Núcleo do LED
    final corePaint = Paint()
      ..color = ledColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: ledCenter, width: 14.0, height: 5.0),
        const Radius.circular(2),
      ),
      corePaint,
    );

    // LEDs de navegação sob os motores traseiros (Vermelho à esquerda, Verde à direita - padrão aeronáutico)
    final navGlowPaint = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // Esquerda: Vermelho
    navGlowPaint.color = const Color(0xFFFF1744).withOpacity(0.5);
    canvas.drawCircle(Offset(rl.dx, rl.dy + 3), 4.5, navGlowPaint);
    canvas.drawCircle(Offset(rl.dx, rl.dy + 3), 2.0, Paint()..color = const Color(0xFFFF1744));

    // Direita: Verde
    navGlowPaint.color = const Color(0xFF00E676).withOpacity(0.5);
    canvas.drawCircle(Offset(rr.dx, rr.dy + 3), 4.5, navGlowPaint);
    canvas.drawCircle(Offset(rr.dx, rr.dy + 3), 2.0, Paint()..color = const Color(0xFF00E676));
  }

  @override
  bool shouldRepaint(covariant ChaseDronePainter oldDelegate) {
    return oldDelegate.altitude != altitude ||
        oldDelegate.pitch != pitch ||
        oldDelegate.roll != roll ||
        oldDelegate.flightMode != flightMode ||
        oldDelegate.speedKmh != speedKmh ||
        oldDelegate.isGeofenceWarning != isGeofenceWarning ||
        oldDelegate.isNoFlyWarning != isNoFlyWarning ||
        oldDelegate.batteryPercent != batteryPercent ||
        oldDelegate.centerYFactor != centerYFactor;
  }
}
