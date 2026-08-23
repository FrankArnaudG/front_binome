import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Un halo lumineux doux (soleil, lune) — un dégradé radial qui s'estompe
/// vers la transparence, pas besoin de flou d'image : le dégradé donne
/// déjà un bord doux.
class SoftGlow extends StatelessWidget {
  final double size;
  final Color color;

  const SoftGlow({super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.95), color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
    );
  }
}

/// Une "tache" de brume/nuage doux — même principe que [SoftGlow] mais
/// pensé pour être superposé en plusieurs exemplaires décalés, avec un
/// flou supplémentaire pour un rendu vraiment cotonneux (voir "Brume
/// Dorée").
class CloudBlob extends StatelessWidget {
  final double width;
  final double height;
  final Color color;

  const CloudBlob({super.key, required this.width, required this.height, required this.color});

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.9), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
