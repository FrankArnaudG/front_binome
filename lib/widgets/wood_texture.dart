import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Texture de bois procédurale (grain, nœuds, joints de planches) — voir
/// demande utilisateur, qui voulait du "vrai" bois plutôt qu'un dégradé
/// plat. Dessinée au lieu d'une photo bundlée : aucun asset à fournir, et
/// la teinte suit celle demandée par l'appelant (RomanPhotoLibraryScreen
/// l'utilise deux fois, fond du rayon et planche de chaque étagère, avec
/// deux couleurs différentes).
class WoodTexture extends StatelessWidget {
  final Color light;
  final Color dark;
  final int seed;
  final bool showPlankSeams;
  final double plankHeight;
  final BorderRadius? borderRadius;
  final Widget? child;

  const WoodTexture({
    super.key,
    required this.light,
    required this.dark,
    this.seed = 1,
    this.showPlankSeams = false,
    this.plankHeight = 46,
    this.borderRadius,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final painted = CustomPaint(
      painter: _WoodGrainPainter(
        light: light,
        dark: dark,
        seed: seed,
        showPlankSeams: showPlankSeams,
        plankHeight: plankHeight,
      ),
      child: child ?? const SizedBox.expand(),
    );
    if (borderRadius == null) return painted;
    return ClipRRect(borderRadius: borderRadius!, child: painted);
  }
}

class _WoodGrainPainter extends CustomPainter {
  final Color light;
  final Color dark;
  final int seed;
  final bool showPlankSeams;
  final double plankHeight;

  const _WoodGrainPainter({
    required this.light,
    required this.dark,
    required this.seed,
    required this.showPlankSeams,
    required this.plankHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final rect = Offset.zero & size;
    final rng = math.Random(seed);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [light, dark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(rect),
    );

    // Fibres du bois — traits horizontaux légèrement ondulés, à l'opacité
    // et l'épaisseur variables pour un rendu organique plutôt que des
    // rayures régulières.
    final grainCount = (size.height / 5).clamp(8, 60).toInt();
    for (var i = 0; i < grainCount; i++) {
      final y = rng.nextDouble() * size.height;
      final amplitude = 1.5 + rng.nextDouble() * 3.5;
      final phase = rng.nextDouble() * math.pi * 2;
      final opacity = 0.05 + rng.nextDouble() * 0.16;
      final path = Path()..moveTo(0, y);
      const segments = 8;
      for (var s = 1; s <= segments; s++) {
        final x = size.width * s / segments;
        final yy = y + math.sin(phase + s * 1.3) * amplitude;
        path.lineTo(x, yy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = dark.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8 + rng.nextDouble() * 1.4,
      );
    }

    // Nœuds épars — quelques cernes concentriques ovales, comme sur une
    // vraie planche.
    final knotCount = (size.width * size.height / 22000).clamp(0, 5).toInt();
    for (var k = 0; k < knotCount; k++) {
      final cx = rng.nextDouble() * size.width;
      final cy = rng.nextDouble() * size.height;
      final r = 4 + rng.nextDouble() * 6;
      for (var ring = 0; ring < 3; ring++) {
        final scale = 1 + ring * 0.65;
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx, cy),
            width: r * 2 * scale,
            height: r * 1.3 * scale,
          ),
          Paint()
            ..color = dark.withValues(alpha: (0.28 - ring * 0.07).clamp(0, 1))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1,
        );
      }
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: r, height: r * 0.7),
        Paint()..color = dark.withValues(alpha: 0.5),
      );
    }

    // Joints entre planches (ombre + liseré clair) — donne l'échelle d'un
    // vrai lambris plutôt qu'une seule planche géante.
    if (showPlankSeams) {
      var y = plankHeight;
      while (y < size.height) {
        canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.32)
            ..strokeWidth = 2,
        );
        canvas.drawLine(
          Offset(0, y + 1.6),
          Offset(size.width, y + 1.6),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.10)
            ..strokeWidth = 1,
        );
        y += plankHeight;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WoodGrainPainter oldDelegate) =>
      oldDelegate.light != light ||
      oldDelegate.dark != dark ||
      oldDelegate.seed != seed ||
      oldDelegate.showPlankSeams != showPlankSeams ||
      oldDelegate.plankHeight != plankHeight;
}
