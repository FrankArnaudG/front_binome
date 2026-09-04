import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Marque Binome : deux cœurs en aplat qui s'imbriquent, séparés par un
/// contour net plutôt qu'un fondu — voir la proposition de logo validée
/// (aplat, sans dégradé, couleurs AppColors.primary/secondary). Remplace
/// l'ancien rond dégradé + Icons.favorite_rounded utilisé sur l'écran de
/// démarrage.
class BinomeMark extends StatelessWidget {
  final double width;

  /// Couleur du contour entre les deux cœurs — doit correspondre au fond
  /// SUR LEQUEL la marque est posée (voir SplashScreen : AppColors.blush),
  /// sans quoi la séparation ne se fond pas proprement dans la page.
  final Color strokeColor;

  const BinomeMark({super.key, required this.width, this.strokeColor = Colors.white});

  // Proportions du symbole source (132×108) — voir la proposition validée.
  static const double _aspectRatio = 108 / 132;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, width * _aspectRatio),
      painter: _BinomeMarkPainter(strokeColor: strokeColor),
    );
  }
}

class _BinomeMarkPainter extends CustomPainter {
  final Color strokeColor;

  const _BinomeMarkPainter({required this.strokeColor});

  static Path _heartPath() {
    return Path()
      ..moveTo(66, 98)
      ..cubicTo(30, 74, 4, 50, 4, 27)
      ..cubicTo(4, 10, 17, -2, 33, -2)
      ..cubicTo(46, -2, 58, 6, 66, 20)
      ..cubicTo(74, 6, 86, -2, 99, -2)
      ..cubicTo(115, -2, 128, 10, 128, 27)
      ..cubicTo(128, 50, 102, 74, 66, 98)
      ..close();
  }

  static void _drawHeart(
    Canvas canvas,
    Path heart, {
    required double dx,
    required double dy,
    required double degrees,
    required Paint fill,
    Paint? stroke,
  }) {
    canvas.save();
    canvas.translate(dx, dy);
    canvas.translate(66, 50);
    canvas.rotate(degrees * math.pi / 180);
    canvas.translate(-66, -50);
    canvas.drawPath(heart, fill);
    if (stroke != null) canvas.drawPath(heart, stroke);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 132, size.height / 108);

    final heart = _heartPath();

    _drawHeart(
      canvas,
      heart,
      dx: 8,
      dy: 4,
      degrees: -8,
      fill: Paint()..color = AppColors.secondary,
    );

    _drawHeart(
      canvas,
      heart,
      dx: -8,
      dy: 10,
      degrees: 8,
      fill: Paint()..color = AppColors.primary,
      stroke: Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BinomeMarkPainter oldDelegate) => oldDelegate.strokeColor != strokeColor;
}
