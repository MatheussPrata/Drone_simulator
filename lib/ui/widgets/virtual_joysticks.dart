import 'package:flutter/material.dart';
import 'dart:math';

class VirtualJoystick extends StatefulWidget {
  final double size;
  final Function(double x, double y)? onChange;
  final Function()? onTouchDown;
  final Function()? onTouchUp;
  final bool returnToCenter;
  final String? labelTop;
  final String? labelBottom;
  final String? labelLeft;
  final String? labelRight;

  const VirtualJoystick({
    super.key,
    this.size = 140,
    this.onChange,
    this.onTouchDown,
    this.onTouchUp,
    this.returnToCenter = true,
    this.labelTop,
    this.labelBottom,
    this.labelLeft,
    this.labelRight,
  });

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick>
    with SingleTickerProviderStateMixin {
  Offset _stickPosition = Offset.zero;
  late AnimationController _returnController;
  Offset _returnFrom = Offset.zero;

  @override
  void initState() {
    super.initState();
    _returnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        setState(() {
          _stickPosition = Offset.lerp(
            _returnFrom,
            Offset.zero,
            Curves.easeOut.transform(_returnController.value),
          )!;
          widget.onChange?.call(_stickPosition.dx, _stickPosition.dy);
        });
      });
  }

  @override
  void dispose() {
    _returnController.dispose();
    super.dispose();
  }

  void _handlePanStart(DragStartDetails details) {
    _returnController.stop();
    widget.onTouchDown?.call();
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final halfSize = widget.size / 2;
    final maxRadius = halfSize * 0.75;

    final box = context.findRenderObject() as RenderBox;
    final localPos = box.globalToLocal(details.globalPosition);
    double dx = (localPos.dx - halfSize) / maxRadius;
    double dy = (localPos.dy - halfSize) / maxRadius;

    // Clamp to circle
    final distance = sqrt(dx * dx + dy * dy);
    if (distance > 1.0) {
      dx /= distance;
      dy /= distance;
    }

    setState(() {
      _stickPosition = Offset(dx, dy);
    });
    widget.onChange?.call(dx, dy);
  }

  void _handlePanEnd(DragEndDetails details) {
    widget.onTouchUp?.call();
    if (widget.returnToCenter) {
      _returnFrom = _stickPosition;
      _returnController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        children: [
          // Labels
          if (widget.labelTop != null)
            Positioned(
              top: 2,
              left: 0,
              right: 0,
              child: Text(
                widget.labelTop!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 8,
                ),
              ),
            ),
          if (widget.labelBottom != null)
            Positioned(
              bottom: 2,
              left: 0,
              right: 0,
              child: Text(
                widget.labelBottom!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 8,
                ),
              ),
            ),
          if (widget.labelLeft != null)
            Positioned(
              left: 2,
              top: 0,
              bottom: 0,
              child: Center(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Text(
                    widget.labelLeft!,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 8,
                    ),
                  ),
                ),
              ),
            ),
          if (widget.labelRight != null)
            Positioned(
              right: 2,
              top: 0,
              bottom: 0,
              child: Center(
                child: RotatedBox(
                  quarterTurns: 1,
                  child: Text(
                    widget.labelRight!,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 8,
                    ),
                  ),
                ),
              ),
            ),
          // Joystick
          GestureDetector(
            onPanStart: _handlePanStart,
            onPanUpdate: _handlePanUpdate,
            onPanEnd: _handlePanEnd,
            child: CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _JoystickPainter(
                stickPosition: _stickPosition,
                maxRadius: widget.size / 2 * 0.75,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JoystickPainter extends CustomPainter {
  final Offset stickPosition;
  final double maxRadius;

  _JoystickPainter({
    required this.stickPosition,
    required this.maxRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2 - 4;
    final thumbRadius = outerRadius * 0.22;

    // Outer circle background
    final outerPaint = Paint()..color = const Color(0xFF222222);
    canvas.drawCircle(center, outerRadius, outerPaint);

    // Outer circle border
    final borderPaint = Paint()
      ..color = const Color(0xFF444444)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, outerRadius, borderPaint);

    // Crosshairs
    final crossPaint = Paint()
      ..color = const Color(0xFF333333)
      ..strokeWidth = 0.8;
    canvas.drawLine(
      Offset(center.dx, center.dy - outerRadius + 8),
      Offset(center.dx, center.dy + outerRadius - 8),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx - outerRadius + 8, center.dy),
      Offset(center.dx + outerRadius - 8, center.dy),
      crossPaint,
    );

    // Inner zone indicator
    final zonePaint = Paint()
      ..color = const Color(0xFF2A2A2A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawCircle(center, maxRadius, zonePaint);

    // Thumb position
    final thumbCenter = Offset(
      center.dx + stickPosition.dx * maxRadius,
      center.dy + stickPosition.dy * maxRadius,
    );

    // Thumb shadow
    canvas.drawCircle(
      thumbCenter + const Offset(1, 2),
      thumbRadius,
      Paint()..color = Colors.black.withOpacity(0.4),
    );

    // Thumb gradient
    final thumbPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.cyan.shade300,
          Colors.cyan.shade700,
        ],
      ).createShader(Rect.fromCircle(center: thumbCenter, radius: thumbRadius));
    canvas.drawCircle(thumbCenter, thumbRadius, thumbPaint);

    // Thumb highlight
    canvas.drawCircle(
      thumbCenter - Offset(thumbRadius * 0.2, thumbRadius * 0.2),
      thumbRadius * 0.4,
      Paint()..color = Colors.white.withOpacity(0.2),
    );

    // Thumb border
    final thumbBorderPaint = Paint()
      ..color = Colors.cyan.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(thumbCenter, thumbRadius, thumbBorderPaint);
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter oldDelegate) {
    return oldDelegate.stickPosition != stickPosition;
  }
}

class DualJoysticks extends StatelessWidget {
  final Function(double throttle, double yaw)? onLeftChanged;
  final Function(double pitch, double roll)? onRightChanged;
  final Function()? onTouchDown;
  final Function()? onTouchUp;

  const DualJoysticks({
    super.key,
    this.onLeftChanged,
    this.onRightChanged,
    this.onTouchDown,
    this.onTouchUp,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: VirtualJoystick(
            size: 130,
            labelTop: '▲ Altitude',
            labelBottom: '▼ Descend',
            labelLeft: '◄ Yaw',
            labelRight: 'Yaw ►',
            onTouchDown: onTouchDown,
            onTouchUp: onTouchUp,
            onChange: (x, y) {
              onLeftChanged?.call(-y, x); // y inverted: up = positive throttle
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: VirtualJoystick(
            size: 130,
            labelTop: '▲ Forward',
            labelBottom: '▼ Backward',
            labelLeft: '◄ Roll',
            labelRight: 'Roll ►',
            onTouchDown: onTouchDown,
            onTouchUp: onTouchUp,
            onChange: (x, y) {
              onRightChanged?.call(y, x); // y = pitch (forward/back), x = roll
            },
          ),
        ),
      ],
    );
  }
}
