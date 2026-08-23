import 'dart:math';

import 'package:flutter/material.dart';

/// Champ d'étoiles procédural — dessiné en code (graine fixe, donc stable
/// visuellement d'un affichage à l'autre), pas une image : quelques
/// kilo-octets de code contre des centaines de Ko pour un visuel équivalent
/// en PNG haute résolution.
class StarfieldPainter extends CustomPainter {
  final int seed;
  final int dotCount;
  final int sparkleCount;
  final Color dotColor;
  final Color sparkleColor;
  final double topFraction;
  final double bottomFraction;

  StarfieldPainter({
    required this.seed,
    this.dotCount = 90,
    this.sparkleCount = 0,
    this.dotColor = Colors.white,
    Color? sparkleColor,
    this.topFraction = 0.0,
    this.bottomFraction = 0.6,
  }) : sparkleColor = sparkleColor ?? dotColor;

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(seed);
    final top = size.height * topFraction;
    final bottom = size.height * bottomFraction;

    final dotPaint = Paint()..color = dotColor;
    for (var i = 0; i < dotCount; i++) {
      final dx = random.nextDouble() * size.width;
      final dy = top + random.nextDouble() * (bottom - top);
      final radius = 0.6 + random.nextDouble() * 1.6;
      final opacity = 0.35 + random.nextDouble() * 0.65;
      canvas.drawCircle(Offset(dx, dy), radius, dotPaint..color = dotColor.withValues(alpha: opacity));
    }

    for (var i = 0; i < sparkleCount; i++) {
      final dx = random.nextDouble() * size.width;
      final dy = top + random.nextDouble() * (bottom - top);
      final scale = 2.5 + random.nextDouble() * 2.5;
      _drawSparkle(canvas, Offset(dx, dy), scale);
    }
  }

  void _drawSparkle(Canvas canvas, Offset center, double scale) {
    // Halo doux (flou gaussien) derrière la pointe, façon étoile qui brille.
    final glowPaint = Paint()
      ..color = sparkleColor.withValues(alpha: 0.5)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, scale * 1.8);
    canvas.drawCircle(center, scale * 1.4, glowPaint);

    final corePaint = Paint()..color = sparkleColor.withValues(alpha: 0.95);
    canvas.drawCircle(center, scale * 0.5, corePaint);

    final linePaint = Paint()
      ..color = sparkleColor.withValues(alpha: 0.85)
      ..strokeWidth = scale * 0.28
      ..strokeCap = StrokeCap.round;
    final len = scale * 2.6;
    canvas.drawLine(center.translate(0, -len), center.translate(0, len), linePaint);
    canvas.drawLine(center.translate(-len, 0), center.translate(len, 0), linePaint);
  }

  @override
  bool shouldRepaint(covariant StarfieldPainter oldDelegate) =>
      oldDelegate.seed != seed || oldDelegate.dotCount != dotCount || oldDelegate.sparkleCount != sparkleCount;
}
