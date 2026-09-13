import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/theme_palette.dart';

/// Ouvre un modale qui sort du bas de l'écran pour afficher le texte
/// informatif d'un mode de jeu (voir demande utilisateur : remplace
/// l'ancien encart toujours visible sous "À distance" par une icône
/// discrète + une modale, appliquée aux 3 modes). [title] est affiché en
/// en-tête, sous la forme "Mode X" (voir demande utilisateur).
Future<void> showGameModeInfoSheet(BuildContext context, ThemePalette theme, String title, String text) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: theme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: theme.textOnBackgroundMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            title,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16, color: theme.textOnBackground),
          ),
          const SizedBox(height: 10),
          Text(
            text,
            style: GoogleFonts.nunito(fontSize: 14, color: theme.textOnBackground, height: 1.5),
          ),
        ],
      ),
    ),
  );
}

/// Petite icône d'information positionnée en haut à droite d'une tuile de
/// mode de jeu — au tap, ouvre [showGameModeInfoSheet] avec [title] et
/// [text].
class GameModeInfoIcon extends StatelessWidget {
  final ThemePalette theme;
  final String title;
  final String text;

  const GameModeInfoIcon({super.key, required this.theme, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      right: 8,
      child: Material(
        color: theme.surface.withValues(alpha: 0.9),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => showGameModeInfoSheet(context, theme, title, text),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(Icons.info_outline_rounded, size: 16, color: theme.primary),
          ),
        ),
      ),
    );
  }
}
