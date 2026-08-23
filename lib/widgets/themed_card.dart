import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';

/// Équivalent de [AppCard] mais suivant le thème personnel choisi (voir
/// [ThemeScope]) — réservé aux 4 écrans d'onglets, les écrans secondaires
/// continuent d'utiliser [AppCard] (palette par défaut fixe).
class ThemedCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const ThemedCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);

    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: (theme.isDark ? Colors.white : Colors.black).withValues(alpha: 0.06)),
        boxShadow: theme.isDark
            ? null
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: child,
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: content,
      ),
    );
  }
}
