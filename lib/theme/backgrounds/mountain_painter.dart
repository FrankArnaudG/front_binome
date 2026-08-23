import 'dart:math';

import 'package:flutter/material.dart';

/// Une couche de silhouette de montagne — plusieurs couches superposées
/// (arrière-plan clair et brumeux → premier plan sombre) recréent l'effet
/// de profondeur des paysages de référence, en formes géométriques
/// simples plutôt qu'une image.
class MountainLayer {
  final Color color;
  final double heightFraction;
  final int seed;
  final int peakCount;

  const MountainLayer({
    required this.color,
    required this.heightFraction,
    required this.seed,
    this.peakCount = 6,
  });
}

class MountainSilhouettePainter extends CustomPainter {
  final List<MountainLayer> layers;

  MountainSilhouettePainter({required this.layers});

  @override
  void paint(Canvas canvas, Size size) {
    for (final layer in layers) {
      final random = Random(layer.seed);
      final path = Path()..moveTo(0, size.height);
      final baseY = size.height * (1 - layer.heightFraction);
      final segment = size.width / layer.peakCount;

      path.lineTo(0, baseY + random.nextDouble() * 20 - 10);
      for (var i = 1; i <= layer.peakCount; i++) {
        final x = segment * i;
        final peakVariance = random.nextDouble() * layer.heightFraction * size.height * 0.5;
        final y = baseY - peakVariance;
        final midX = x - segment / 2;
        path.quadraticBezierTo(midX, y - 10, x, baseY + random.nextDouble() * 16 - 8);
      }
      path.lineTo(size.width, size.height);
      path.close();

      canvas.drawPath(path, Paint()..color = layer.color);
    }
  }

  @override
  bool shouldRepaint(covariant MountainSilhouettePainter oldDelegate) => oldDelegate.layers != layers;
}
