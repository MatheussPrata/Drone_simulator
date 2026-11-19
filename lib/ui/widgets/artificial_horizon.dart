import 'package:flutter/material.dart';
import 'dart:math';

class ArtificialHorizon extends StatelessWidget {
  final double pitch;
  final double roll;
  final double heading;
  final double size;

  const ArtificialHorizon({
    super.key,
    required this.pitch,
    required this.roll,
    required this.heading,
    this.size = 150,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade600, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: CustomPaint(
          size: Size(size, size),
          painter: _ArtificialHorizonPainter(
            pitch: pitch,
            roll: roll,
            heading: heading,
          ),
        ),
      ),
    );
  }
}

class _ArtificialHorizonPainter extends CustomPainter {
  final double pitch;
  final double roll;
  final double heading;

  _ArtificialHorizonPainter({
    required this.pitch,
    required this.roll,
    required this.heading,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final pitchOffset = pitch * 2.0; // 2 pixels per degree

    // Clip to circle
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Translate to center and rotate by roll
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-roll * pi / 180.0);

    // Sky (blue)
    final skyPaint = Paint()..color = const Color(0xFF1565C0);
    canvas.drawRect(
      Rect.fromLTWH(-radius * 2, -radius * 2 + pitchOffset, radius * 4, radius * 2),
      skyPaint,
    );

    // Ground (brown)
    final groundPaint = Paint()..color = const Color(0xFF5D4037);
    canvas.drawRect(
      Rect.fromLTWH(-radius * 2, pitchOffset, radius * 4, radius * 2),
      groundPaint,
    );

    // Horizon line
    final horizonPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(-radius * 2, pitchOffset),
      Offset(radius * 2, pitchOffset),
      horizonPaint,
    );

    // Pitch ladder lines
    final ladderPaint = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..strokeWidth = 1.0;

    for (final deg in [10, 20, 30]) {
      final yUp = pitchOffset - deg * 2.0;
      final yDown = pitchOffset + deg * 2.0;
      final halfWidth = 15.0 + (deg == 10 ? 0 : deg == 20 ? 5 : 10);

      // Upper lines (nose up)
      canvas.drawLine(Offset(-halfWidth, yUp), Offset(halfWidth, yUp), ladderPaint);
      // Lower lines (nose down) - dashed style with shorter lines
      canvas.drawLine(Offset(-halfWidth * 0.7, yDown), Offset(-5, yDown), ladderPaint);
      canvas.drawLine(Offset(5, yDown), Offset(halfWidth * 0.7, yDown), ladderPaint);

      // Labels
      final textPainter = TextPainter(
        text: TextSpan(
          text: '$deg',
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 8),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(halfWidth + 3, yUp - 5));
      textPainter.paint(canvas, Offset(halfWidth * 0.7 + 3, yDown - 5));
    }

    // Restore from roll rotation
    canvas.restore();

    // Fixed aircraft reference symbol (center cross)
    final refPaint = Paint()
      ..color = Colors.orangeAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Left wing
    canvas.drawLine(
      Offset(center.dx - 30, center.dy),
      Offset(center.dx - 10, center.dy),
      refPaint,
    );
    // Right wing
    canvas.drawLine(
      Offset(center.dx + 10, center.dy),
      Offset(center.dx + 30, center.dy),
      refPaint,
    );
    // Center dot
    canvas.drawCircle(center, 3, Paint()..color = Colors.orangeAccent);

    // Roll indicator triangle at top
    final rollTrianglePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final trianglePath = Path()
      ..moveTo(center.dx, 8)
      ..lineTo(center.dx - 5, 2)
      ..lineTo(center.dx + 5, 2)
      ..close();
    canvas.drawPath(trianglePath, rollTrianglePaint);

    // Heading compass at bottom
    final headingText = 'HDG ${heading.toStringAsFixed(0)}°';
    final headingPainter = TextPainter(
      text: TextSpan(
        text: headingText,
        style: const TextStyle(
          color: Colors.greenAccent,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    headingPainter.paint(
      canvas,
      Offset(center.dx - headingPainter.width / 2, size.height - 18),
    );

    // Thin circular border
    final borderPaint = Paint()
      ..color = Colors.grey.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius - 1, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _ArtificialHorizonPainter oldDelegate) {
    return oldDelegate.pitch != pitch ||
        oldDelegate.roll != roll ||
        oldDelegate.heading != heading;
  }
}
