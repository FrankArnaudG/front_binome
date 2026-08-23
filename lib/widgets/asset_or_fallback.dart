import 'package:flutter/material.dart';

/// Affiche un asset image s'il existe, sinon retombe sur [fallback].
/// Permet de brancher les futures illustrations générées (personnages)
/// sans casser l'écran tant qu'elles ne sont pas encore livrées.
class AssetOrFallback extends StatelessWidget {
  final String assetPath;
  final Widget fallback;
  final BoxFit fit;

  const AssetOrFallback({
    super.key,
    required this.assetPath,
    required this.fallback,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}
