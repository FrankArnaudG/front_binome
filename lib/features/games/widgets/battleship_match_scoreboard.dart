import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../battleship/battleship_engine.dart';
import '../battleship/battleship_transport.dart';

/// Score de fin de partie pour "Bataille Navale" — pas d'égalité possible
/// hors abandon (il y a toujours un vainqueur, celui qui coule la flotte
/// adverse en premier). Voir demande utilisateur : même mise en page à
/// deux joueurs que les autres jeux (showWarCardMatchScoreboard...), plutôt
/// qu'un unique avatar du·de la vainqueur·e — le score affiché est le
/// nombre de navires coulés par chacun·e.
Future<bool?> showBattleshipMatchScoreboard(
  BuildContext context, {
  required BattleshipBoardState state,
  required Map<String, String> playerNames,
  required Map<String, String?> playerAvatars,
  bool allowRematch = false,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _BattleshipScoreboardSheet(
      state: state,
      playerNames: playerNames,
      playerAvatars: playerAvatars,
      allowRematch: allowRematch,
    ),
  );
}

class _BattleshipScoreboardSheet extends StatelessWidget {
  final BattleshipBoardState state;
  final Map<String, String> playerNames;
  final Map<String, String?> playerAvatars;
  final bool allowRematch;

  const _BattleshipScoreboardSheet({
    required this.state,
    required this.playerNames,
    required this.playerAvatars,
    required this.allowRematch,
  });

  /// Navires coulés PAR [userId] : `opponentSunkShips` est déjà LES MIENS
  /// (ceux que j'ai coulés chez l'adversaire, voir doc de classe de
  /// BattleshipBoardState) ; pour l'adversaire, seul le nombre de MES
  /// navires marqués `isSunk` est connu (jamais le détail d'un navire
  /// adverse encore vivant, voir la même doc de classe).
  int _sunkBy(String userId) =>
      userId == state.myUserId ? state.opponentSunkShips.length : state.myFleet.where((s) => s.isSunk).length;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    // Un abandon (voir demande utilisateur) ne déclare jamais de gagnant —
    // `winnerUserId` reste `null` sans qu'aucun nul ne soit possible dans
    // cette partie autrement (voir BattleshipController::abandon).
    final noResult = state.abandoned && state.winnerUserId == null;
    final players = [state.myUserId, state.opponentUserId];
    final totalShips = BattleshipEngine.shipSizesFor(state.gridSize).length;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: theme.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(false),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, color: theme.textOnBackgroundMuted, size: 22),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.textOnBackgroundMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Icon(noResult ? Icons.block_rounded : Icons.emoji_events_rounded, size: 40, color: theme.primary),
            const SizedBox(height: 10),
            Text(
              // Aucune clé i18n existante ne couvre "abandon sans vainqueur"
              // pour Bataille Navale (contrairement à *_score_tie, qui ne
              // s'applique pas ici — ce jeu n'a pas de nul) — texte en dur,
              // comme ailleurs dans ces écrans de jeu.
              noResult
                  ? 'Partie interrompue — pas de vainqueur'
                  : LocaleScope.t(context, 'battleship_score_winner', {
                      'name': playerNames[state.winnerUserId] ?? LocaleScope.t(context, 'memory_score_player_fallback'),
                    }),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w800, color: theme.textOnBackground),
            ),
            const SizedBox(height: 20),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < players.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(
                      child: _PlayerResultCard(
                        theme: theme,
                        name: playerNames[players[i]] ?? LocaleScope.t(context, 'memory_score_player_fallback'),
                        avatar: playerAvatars[players[i]],
                        sunk: _sunkBy(players[i]),
                        total: totalShips,
                        isWinner: players[i] == state.winnerUserId,
                        noResult: noResult,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (allowRematch) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.replay_rounded),
                label: Text(LocaleScope.t(context, 'memory_score_rematch')),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ],
            // "Quitter" : referme le jeu et ramène au choix de la difficulté (voir demande
            // utilisateur) — taper à côté de la feuille revient au même (résultat null).
            SizedBox(height: allowRematch ? 10 : 20),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: Text(LocaleScope.t(context, 'game_score_quit')),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerResultCard extends StatelessWidget {
  final ThemePalette theme;
  final String name;
  final String? avatar;
  final int sunk;
  final int total;
  final bool isWinner;
  final bool noResult;

  const _PlayerResultCard({
    required this.theme,
    required this.name,
    required this.avatar,
    required this.sunk,
    required this.total,
    required this.isWinner,
    required this.noResult,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isWinner ? theme.primary.withValues(alpha: 0.45) : theme.primary.withValues(alpha: 0.12),
          width: isWinner ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: theme.primary.withValues(alpha: 0.16),
                backgroundImage: (avatar != null && avatar!.isNotEmpty) ? NetworkImage(avatar!) : null,
                child: (avatar == null || avatar!.isEmpty)
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.primary, fontSize: 18),
                      )
                    : null,
              ),
              if (isWinner)
                Positioned(
                  top: -6,
                  right: 6,
                  child: Icon(Icons.emoji_events_rounded, size: 18, color: theme.primary),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: theme.textOnBackground),
          ),
          const SizedBox(height: 6),
          Text(
            '$sunk/$total',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: theme.primary),
          ),
          Text(
            'navires coulés',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(fontSize: 10, color: theme.textOnBackgroundMuted),
          ),
          const SizedBox(height: 4),
          Text(
            noResult ? '—' : (isWinner ? LocaleScope.t(context, 'ttt_score_won') : LocaleScope.t(context, 'ttt_score_lost')),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w800, color: theme.primary),
          ),
        ],
      ),
    );
  }
}
