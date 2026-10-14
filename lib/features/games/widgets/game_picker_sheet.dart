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
              const SizedBox(height: 14),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: games.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final game = games[index];
                    final description = game.descriptionFor(localeCode);
                    return Material(
                      color: theme.background,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => Navigator.of(context).pop(game),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color: theme.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: gameIcon(game, theme.primary),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      game.nameFor(localeCode),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: theme.textOnBackground),
                                    ),
                                    if (description != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        description,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded, color: theme.textOnBackgroundMuted),
                            ],
                          ),
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
