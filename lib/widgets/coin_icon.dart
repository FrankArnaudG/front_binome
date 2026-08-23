import 'package:flutter/material.dart';

import 'asset_or_fallback.dart';

/// Icône de la monnaie virtuelle ("pièces") — utilise l'illustration
/// `assets/images/shop/yeleen.png` par défaut, ou [assetPath] si fourni (ex.
/// un visuel propre à un pack de la Boutique, voir `CoinPack.imagePath`).
/// Retombe sur l'icône Material classique si l'asset n'existe pas encore
/// (même esprit que [AssetOrFallback] ailleurs dans l'app : rien ne casse).
class CoinIcon extends StatelessWidget {
  final double size;
  final Color? fallbackColor;
  final String? assetPath;

  const CoinIcon({super.key, this.size = 24, this.fallbackColor, this.assetPath});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: AssetOrFallback(
        assetPath: assetPath ?? 'assets/images/shop/yeleen.png',
        fit: BoxFit.contain,
        fallback: Icon(Icons.monetization_on_rounded, size: size, color: fallbackColor),
      ),
    );
  }
}
