import 'dart:math';
import 'package:flutter/material.dart';

/// Widget de Joystick Virtual analógico para pilotagem sobre o mapa.
///
/// Utiliza [GestureDetector] com `onPanStart`, `onPanUpdate` e `onPanEnd`
/// para capturar o toque e arrasto do usuário. Desenha um círculo externo (base)
/// e uma bolinha interna (knob), emitindo um [Offset] normalizado
/// entre -1.0 e 1.0 (onde dx vai de -1.0 à esquerda a +1.0 à direita,
/// e dy vai de -1.0 para cima a +1.0 para baixo).
///
/// Ao soltar o toque, a bolinha retorna automaticamente para (0, 0).
class VirtualJoystick extends StatefulWidget {
  /// Raio do círculo externo em pixels lógicos
  final double radius;

  /// Raio da bolinha interna (knob)
  final double stickRadius;

  /// Callback chamado com o [Offset] normalizado entre (-1.0, -1.0) e (1.0, 1.0)
  final ValueChanged<Offset>? onPositionChanged;

  /// Alias de conveniência para [onPositionChanged]
  final ValueChanged<Offset>? onChanged;

  /// Callback adicional opcional com parâmetros descompactados (dx, dy)
  final void Function(double dx, double dy)? onChange;

  /// Cor de fundo do círculo externo
  final Color outerColor;

  /// Cor da borda do círculo externo
  final Color borderColor;

  /// Cor da bolinha interna (knob)
  final Color innerColor;

  /// Rótulo opcional exibido no topo do joystick (ex.: "Altitude / Yaw")
  final String? label;

  /// Opacidade do widget do joystick (0.0 a 1.0) para sobreposição translúcida
  final double opacity;

  const VirtualJoystick({
    super.key,
    this.radius = 60.0,
    this.stickRadius = 22.0,
    this.onPositionChanged,
    this.onChanged,
    this.onChange,
    this.outerColor = const Color(0x66000000),
    this.borderColor = const Color(0x6600E5FF),
    this.innerColor = const Color(0xFF00E5FF),
    this.label,
    this.opacity = 1.0,
  });

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick> {
  Offset _stickPosition = Offset.zero;

  void _updatePosition(Offset localPosition) {
    final center = Offset(widget.radius, widget.radius);
    final delta = localPosition - center;
    final distance = delta.distance;
    final maxDistance = max(1.0, widget.radius - widget.stickRadius);

    Offset clampedDelta;
    if (distance > maxDistance) {
      clampedDelta = Offset(
        delta.dx / distance * maxDistance,
        delta.dy / distance * maxDistance,
      );
    } else {
      clampedDelta = delta;
    }

    final normalized = Offset(
      (clampedDelta.dx / maxDistance).clamp(-1.0, 1.0),
      (clampedDelta.dy / maxDistance).clamp(-1.0, 1.0),
    );

    setState(() {
      _stickPosition = clampedDelta;
    });

    widget.onPositionChanged?.call(normalized);
    widget.onChanged?.call(normalized);
    widget.onChange?.call(normalized.dx, normalized.dy);
  }

  void _resetPosition() {
    setState(() {
      _stickPosition = Offset.zero;
    });
    widget.onPositionChanged?.call(Offset.zero);
    widget.onChanged?.call(Offset.zero);
    widget.onChange?.call(0.0, 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final diameter = widget.radius * 2;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: widget.borderColor.withOpacity(0.4)),
            ),
            child: Text(
              widget.label!,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
        GestureDetector(
          key: const Key('virtual_joystick_gesture'),
          onPanStart: (details) => _updatePosition(details.localPosition),
          onPanUpdate: (details) => _updatePosition(details.localPosition),
          onPanEnd: (_) => _resetPosition(),
          onPanCancel: _resetPosition,
          child: CustomPaint(
            size: Size(diameter, diameter),
            painter: _JoystickPainter(
              radius: widget.radius,
              stickRadius: widget.stickRadius,
              stickOffset: _stickPosition,
              outerColor: widget.outerColor,
              borderColor: widget.borderColor,
              innerColor: widget.innerColor,
            ),
          ),
        ),
      ],
    );

    if (widget.opacity < 1.0) {
      return Opacity(
        opacity: widget.opacity.clamp(0.0, 1.0),
        child: content,
      );
    }

    return content;
  }
}

class _JoystickPainter extends CustomPainter {
  final double radius;
  final double stickRadius;
  final Offset stickOffset;
  final Color outerColor;
  final Color borderColor;
  final Color innerColor;

  _JoystickPainter({
    required this.radius,
    required this.stickRadius,
    required this.stickOffset,
    required this.outerColor,
    required this.borderColor,
    required this.innerColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // 1. Círculo externo (Base de apoio)
    final outerPaint = Paint()
      ..color = outerColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, outerPaint);

    // Borda do círculo externo
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius, borderPaint);

    // Linhas guias centrais (mira suave)
    final guidePaint = Paint()
      ..color = borderColor.withOpacity(0.25)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(center.dx - radius * 0.45, center.dy),
      Offset(center.dx + radius * 0.45, center.dy),
      guidePaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius * 0.45),
      Offset(center.dx, center.dy + radius * 0.45),
      guidePaint,
    );

    // 2. Bolinha interna (Knob móvel)
    final knobCenter = center + stickOffset;

    // Sombra projetada do knob
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawCircle(knobCenter + const Offset(1, 2), stickRadius, shadowPaint);

    // Gradiente radial da bolinha
    final knobPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          innerColor,
          Color.lerp(innerColor, Colors.black, 0.35) ?? innerColor,
        ],
      ).createShader(Rect.fromCircle(center: knobCenter, radius: stickRadius));
    canvas.drawCircle(knobCenter, stickRadius, knobPaint);

    // Borda externa do knob
    final knobBorderPaint = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(knobCenter, stickRadius, knobBorderPaint);

    // Ponto de luz (reflexo 3D)
    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      knobCenter - Offset(stickRadius * 0.25, stickRadius * 0.25),
      stickRadius * 0.28,
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter oldDelegate) {
    return oldDelegate.stickOffset != stickOffset ||
        oldDelegate.radius != radius ||
        oldDelegate.stickRadius != stickRadius ||
        oldDelegate.outerColor != outerColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.innerColor != innerColor;
  }
}
