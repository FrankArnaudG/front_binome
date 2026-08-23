import 'dart:math';

import 'package:flutter/material.dart';

/// Reproduction simplifiée du logo "G" de Google (4 couleurs), dessinée en
/// vectoriel pour ne dépendre d'aucun asset externe.
class GoogleLogo extends StatelessWidget {
  final double size;

  const GoogleLogo({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = size.width * 0.22;

    final arcRect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    void drawArc(double startDeg, double sweepDeg, Color color) {
      paint.color = color;
      canvas.drawArc(arcRect, startDeg * pi / 180, sweepDeg * pi / 180, false, paint);
    }

    drawArc(-40, 100, _blue);
    drawArc(60, 80, _green);
    drawArc(140, 80, _yellow);
    drawArc(220, 100, _red);

    // Barre horizontale du "G"
    final barPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = _blue;
    canvas.drawRect(
      Rect.fromLTWH(center.dx, center.dy - strokeWidth / 2, radius - strokeWidth * 0.15, strokeWidth),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GoogleLogoPainter oldDelegate) => false;
}
