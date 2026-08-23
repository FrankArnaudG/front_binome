import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/theme_scope.dart';
import 'primary_button.dart';

/// État vide générique (timeline, packs, jeux...) : icône + message +
/// action optionnelle. Suit le thème personnel choisi (voir [ThemeScope],
/// monté globalement) plutôt qu'une palette fixe — sinon ce texte reste
/// sombre et illisible sur un fond de thème sombre (Boutique, Jeux...).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: theme.textOnBackgroundMuted),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(fontSize: 15, color: theme.textOnBackgroundMuted),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            PrimaryButton(label: actionLabel!, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}
