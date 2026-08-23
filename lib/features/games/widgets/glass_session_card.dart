import 'package:flutter/material.dart';

import '../../../theme/theme_palette.dart';

/// L'écrin partagé par les écrans de session de jeu (prompt unique ou
/// multi-questions par boîte) : verre dépoli + bordure lumineuse dans la
/// couleur du thème actif, plutôt qu'un fond neutre par jeu.
class GlassSessionCard extends StatelessWidget {
  final ThemePalette theme;
  final Widget child;

  const GlassSessionCard({super.key, required this.theme, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 480),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
      decoration: BoxDecoration(
        color: theme.surface.withValues(alpha: theme.isDark ? 0.55 : 0.78),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.primary.withValues(alpha: 0.35), width: 1.2),
        boxShadow: [
          BoxShadow(color: theme.primary.withValues(alpha: 0.18), blurRadius: 32, offset: const Offset(0, 16)),
        ],
      ),
      child: Center(child: child),
    );
  }
}
