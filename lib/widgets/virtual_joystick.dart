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

  /// Se `true`, o eixo vertical (Y) retorna ao centro ao soltar; se `false`, mantém o throttle.
  final bool autoCenterY;

  /// Se `true`, permite tocar em qualquer ponto da zona lateral e centralizar o stick ali.
  final bool floating;

  /// Largura da área de toque quando [floating] é `true`.
  final double floatingWidth;

  /// Altura da área de toque quando [floating] é `true`.
  final double floatingHeight;

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
    this.autoCenterY = true,
    this.floating = false,
    this.floatingWidth = 210.0,
    this.floatingHeight = 142.0,
  });

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick> {
  Offset _stickPosition = Offset.zero;
  Offset? _dynamicOrigin;

  double get _maxDistance => max(1.0, widget.radius - widget.stickRadius);

  Offset get _restCenter {
    if (!widget.floating) {
      return Offset(widget.radius, widget.radius);
    }
    return Offset(widget.floatingWidth / 2, widget.floatingHeight / 2);
  }

  @override
  void didUpdateWidget(VirtualJoystick oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.autoCenterY && widget.autoCenterY) {
      _stickPosition = Offset.zero;
      _dynamicOrigin = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _emitNormalized(Offset.zero);
        }
      });
    }
  }

  void _emitNormalized(Offset normalized) {
    widget.onPositionChanged?.call(normalized);
    widget.onChanged?.call(normalized);
    widget.onChange?.call(normalized.dx, normalized.dy);
  }

  void _handlePanStart(Offset localPosition) {
    if (!widget.floating) {
      _updatePosition(localPosition);
      return;
    }

    final minX = widget.radius;
    final maxX = max(minX, widget.floatingWidth - widget.radius);
    final minY = widget.radius;
    final maxY = max(minY, widget.floatingHeight - widget.radius);

    final clampedOrigin = Offset(
      localPosition.dx.clamp(minX, maxX),
      localPosition.dy.clamp(minY, maxY),
    );

    if (!widget.autoCenterY) {
      final newOrigin = Offset(
        clampedOrigin.dx,
        (clampedOrigin.dy - _stickPosition.dy).clamp(minY, maxY),
      );
      setState(() {
        _dynamicOrigin = newOrigin;
      });
      _updatePosition(localPosition);
    } else {
      setState(() {
        _dynamicOrigin = clampedOrigin;
        _stickPosition = Offset.zero;
      });
      _emitNormalized(Offset.zero);
    }
  }

  void _updatePosition(Offset localPosition) {
    final center = widget.floating ? (_dynamicOrigin ?? _restCenter) : _restCenter;
    final delta = localPosition - center;
    final distance = delta.distance;
    final maxDistance = _maxDistance;

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

    _emitNormalized(normalized);
  }

  void _resetPosition() {
    final maxDistance = _maxDistance;
    final nextStick =
        widget.autoCenterY ? Offset.zero : Offset(0.0, _stickPosition.dy);
    final normalized = widget.autoCenterY
        ? Offset.zero
        : Offset(0.0, (nextStick.dy / maxDistance).clamp(-1.0, 1.0));

    setState(() {
      _stickPosition = nextStick;
      _dynamicOrigin = null;
    });
    _emitNormalized(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final diameter = widget.radius * 2;
    final canvasSize = widget.floating
        ? Size(widget.floatingWidth, widget.floatingHeight)
        : Size(diameter, diameter);
    final activeCenter =
        widget.floating ? (_dynamicOrigin ?? _restCenter) : _restCenter;

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
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) => _handlePanStart(details.localPosition),
          onPanUpdate: (details) => _updatePosition(details.localPosition),
          onPanEnd: (_) => _resetPosition(),
          onPanCancel: _resetPosition,
          child: CustomPaint(
            size: canvasSize,
            painter: _JoystickPainter(
              radius: widget.radius,
              stickRadius: widget.stickRadius,
              baseCenter: activeCenter,
              stickOffset: _stickPosition,
              outerColor: widget.outerColor,
              borderColor: widget.borderColor,
              innerColor: widget.innerColor,
              holdVerticalAxis: !widget.autoCenterY,
              isFloatingArea: widget.floating,
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
  final Offset baseCenter;
  final Offset stickOffset;
  final Color outerColor;
  final Color borderColor;
  final Color innerColor;
  final bool holdVerticalAxis;
  final bool isFloatingArea;

  _JoystickPainter({
    required this.radius,
    required this.stickRadius,
    required this.baseCenter,
    required this.stickOffset,
    required this.outerColor,
    required this.borderColor,
    required this.innerColor,
    this.holdVerticalAxis = false,
    this.isFloatingArea = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = baseCenter;

    if (isFloatingArea) {
      final zonePaint = Paint()
        ..color = borderColor.withOpacity(0.14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
          const Radius.circular(18),
        ),
        zonePaint,
      );
    }

    // 1. Círculo externo (Base de apoio)
    final outerPaint = Paint()
      ..color = outerColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, outerPaint);

    // Borda do círculo externo
    final borderPaint = Paint()
      ..color = holdVerticalAxis ? Colors.amberAccent.withOpacity(0.75) : borderColor
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

    if (holdVerticalAxis) {
      final holdLinePaint = Paint()
        ..color = Colors.amberAccent.withOpacity(0.65)
        ..strokeWidth = 1.6;
      final holdY = center.dy + stickOffset.dy;
      canvas.drawLine(
        Offset(center.dx - radius * 0.55, holdY),
        Offset(center.dx + radius * 0.55, holdY),
        holdLinePaint,
      );
    }

    // 2. Bolinha interna (Knob móvel)
    final knobCenter = center + stickOffset;

    // Sombra projetada do knob
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawCircle(knobCenter + const Offset(1, 2), stickRadius, shadowPaint);

    // Gradiente radial da bolinha
    final knobColor = holdVerticalAxis ? Colors.amberAccent : innerColor;
    final knobPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          knobColor,
          Color.lerp(knobColor, Colors.black, 0.35) ?? knobColor,
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
        oldDelegate.baseCenter != baseCenter ||
        oldDelegate.radius != radius ||
        oldDelegate.stickRadius != stickRadius ||
        oldDelegate.outerColor != outerColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.innerColor != innerColor ||
        oldDelegate.holdVerticalAxis != holdVerticalAxis ||
        oldDelegate.isFloatingArea != isFloatingArea;
  }
}
