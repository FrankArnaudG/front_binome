import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../models/game.dart';
import '../../../theme/theme_palette.dart';
import '../games_menu_screen.dart' show gameIcon;

/// Feuille de sélection du jeu pour défier un ami — voir demande
/// utilisateur (refonte) : "la liste des jeu bien représenté" — réutilise
/// les mêmes illustrations/icônes que le menu principal des jeux (voir
/// [gameIcon]) plutôt qu'une simple liste de texte. Partagée entre le choix
/// d'un ami déjà connu et l'ajout d'un nouvel ami par code.
Future<Game?> showGamePickerSheet({
  required BuildContext context,
  required String opponentLabel,
  required List<Game> games,
  required ThemePalette theme,
}) {
  return showModalBottomSheet<Game>(
    context: context,
    isScrollControlled: true,
    backgroundColor: theme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _GamePickerSheet(opponentLabel: opponentLabel, games: games, theme: theme),
  );
}

class _GamePickerSheet extends StatelessWidget {
  final String opponentLabel;
  final List<Game> games;
  final ThemePalette theme;

  const _GamePickerSheet({required this.opponentLabel, required this.games, required this.theme});

  @override
  Widget build(BuildContext context) {
    final localeCode = LocaleScope.of(context).current.code;

    return SafeArea(
      child: ConstrainedBox(
        // Voir demande utilisateur : 7 jeux à lister, ça dépasse une
        // feuille "mi-écran" par défaut — bornée puis scrollable plutôt
        // que de déborder silencieusement en bas.
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Défier $opponentLabel à :',
                style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: theme.textOnBackground),
              ),
              const SizedBox(height: 18),
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.05,
                  ),
                  itemCount: games.length,
                  itemBuilder: (context, index) {
                    final game = games[index];
                    return Material(
                      color: theme.background,
                      borderRadius: BorderRadius.circular(18),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(game),
                        child: Column(
                          children: [
                            Expanded(
                              child: Container(
                                width: double.infinity,
                                color: theme.primary.withValues(alpha: 0.12),
                                child: gameIcon(game, theme.primary),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                              child: Text(
                                game.nameFor(localeCode),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.nunito(fontWeight: FontWeight.w700, fontSize: 13, color: theme.textOnBackground),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
