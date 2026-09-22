import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../tic_tac_toe/tic_tac_toe_transport.dart';

/// Score de fin de partie pour "Morpion à Deux" — copie structurelle de
/// showMemoryGameMatchScoreboard, adaptée à un résultat gagnant/nul plutôt
/// qu'un score partagé (voir TicTacToeBoardState.winnerUserId/isDraw).
Future<bool?> showTicTacToeMatchScoreboard(
  BuildContext context, {
  required TicTacToeBoardState state,
  required Map<String, String> playerNames,
  required Map<String, String?> playerAvatars,
  bool allowRematch = false,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TicTacToeScoreboardSheet(
      state: state,
      playerNames: playerNames,
      playerAvatars: playerAvatars,
      allowRematch: allowRematch,
    ),
  );
}

class _TicTacToeScoreboardSheet extends StatelessWidget {
  final TicTacToeBoardState state;
  final Map<String, String> playerNames;
  final Map<String, String?> playerAvatars;
  final bool allowRematch;

  const _TicTacToeScoreboardSheet({
    required this.state,
    required this.playerNames,
    required this.playerAvatars,
    required this.allowRematch,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final players = playerNames.keys.toList();

    final minutes = state.startedAt != null ? DateTime.now().difference(state.startedAt!).inSeconds ~/ 60 : 0;
    final seconds = state.startedAt != null ? DateTime.now().difference(state.startedAt!).inSeconds % 60 : 0;

    // Un abandon ne déclare jamais de gagnant — `winnerUserId` reste `null`
    // sans que `isDraw` soit posé pour autant (voir TicTacToeController::abandon).
    // Si les deux scores sont malgré tout à égalité à ce moment-là, l'écran
    // doit lire "Nul" plutôt que "Perdu" pour les deux à la fois.
    final effectiveTie = state.isDraw ||
        (state.winnerUserId == null && state.scoreFor(players[0]) == state.scoreFor(players[1]));

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
            Icon(effectiveTie ? Icons.handshake_rounded : Icons.emoji_events_rounded, size: 40, color: theme.primary),
            const SizedBox(height: 10),
            Text(
              effectiveTie
                  ? LocaleScope.t(context, 'dot_squares_score_tie')
                  : LocaleScope.t(context, 'ttt_score_winner', {
                      'name': playerNames[state.winnerUserId] ?? LocaleScope.t(context, 'memory_score_player_fallback'),
                    }),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w800, color: theme.textOnBackground),
            ),
            const SizedBox(height: 4),
            Text(
              '$minutes:${seconds.toString().padLeft(2, '0')} • ${state.movesCount} ${LocaleScope.t(context, 'memory_score_moves')}',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
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
                        isWinner: players[i] == state.winnerUserId,
                        isTie: effectiveTie,
                        score: state.scoreFor(players[i]),
                        targetScore: state.targetScore,
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
  final bool isWinner;
  final bool isTie;
  final int score;
  final int targetScore;

  const _PlayerResultCard({
    required this.theme,
    required this.name,
    required this.avatar,
    required this.isWinner,
    required this.isTie,
    required this.score,
    required this.targetScore,
  });

  @override
  Widget build(BuildContext context) {
    final highlighted = isWinner || isTie;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highlighted ? theme.primary.withValues(alpha: 0.45) : theme.primary.withValues(alpha: 0.12),
          width: highlighted ? 1.4 : 1,
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
            '$score/$targetScore',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: theme.textOnBackgroundMuted),
          ),
          const SizedBox(height: 4),
          Text(
            isTie
                ? LocaleScope.t(context, 'dot_squares_score_tie_short')
                : (isWinner ? LocaleScope.t(context, 'ttt_score_won') : LocaleScope.t(context, 'ttt_score_lost')),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w800, color: theme.primary),
          ),
        ],
      ),
    );
  }
}
