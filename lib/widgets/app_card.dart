import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Conteneur arrondi réutilisé pour les tuiles (packs, cadeaux, jeux,
/// commandes, entrées de timeline...) sur les écrans à fond clair (blush).
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.blushCard,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );

    if (onTap == null && onDoubleTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: content,
      ),
    );
  }
}
