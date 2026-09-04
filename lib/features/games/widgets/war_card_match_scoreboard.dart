import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../war_card/war_card_transport.dart';

/// Score de fin de partie pour "Bataille" — copie structurelle de
/// showNumberHuntMatchScoreboard, mais le "score" affiché par joueur est
/// le nombre de cartes détenues à la fin (52/0 en cas de victoire nette,
/// ou le partage au moment du plafond de manches — voir WarCardEngine).
Future<bool?> showWarCardMatchScoreboard(
  BuildContext context, {
  required WarCardBoardState state,
  required Map<String, String> playerNames,
  required Map<String, String?> playerAvatars,
  required Color Function(String userId) colorFor,
  bool allowRematch = false,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WarCardScoreboardSheet(
      state: state,
      playerNames: playerNames,
      playerAvatars: playerAvatars,
      colorFor: colorFor,
      allowRematch: allowRematch,
    ),
  );
}

class _WarCardScoreboardSheet extends StatelessWidget {
  final WarCardBoardState state;
  final Map<String, String> playerNames;
  final Map<String, String?> playerAvatars;
  final Color Function(String userId) colorFor;
  final bool allowRematch;

  const _WarCardScoreboardSheet({
    required this.state,
    required this.playerNames,
    required this.playerAvatars,
    required this.colorFor,
    required this.allowRematch,
  });

  int _cardsFor(String userId) => userId == state.creatorId ? state.pileCreator.length : state.pilePartner.length;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final players = playerNames.keys.toList();

    final minutes = state.startedAt != null ? DateTime.now().difference(state.startedAt!).inSeconds ~/ 60 : 0;
    final seconds = state.startedAt != null ? DateTime.now().difference(state.startedAt!).inSeconds % 60 : 0;

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
            Icon(state.isTie ? Icons.handshake_rounded : Icons.emoji_events_rounded, size: 40, color: theme.primary),
            const SizedBox(height: 10),
            Text(
              state.isTie
                  ? LocaleScope.t(context, 'war_card_score_tie')
                  : LocaleScope.t(context, 'war_card_score_winner', {
                      'name': playerNames[state.winnerUserId] ?? LocaleScope.t(context, 'memory_score_player_fallback'),
                    }),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w800, color: theme.textOnBackground),
            ),
            const SizedBox(height: 4),
            Text(
              '${LocaleScope.t(context, 'war_card_score_rounds', {'count': '${state.roundsCount}'})}  ·  $minutes:${seconds.toString().padLeft(2, '0')}',
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
                        color: colorFor(players[i]),
                        cardCount: _cardsFor(players[i]),
                        isWinner: players[i] == state.winnerUserId,
                        isTie: state.isTie,
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
  final Color color;
  final int cardCount;
  final bool isWinner;
  final bool isTie;

  const _PlayerResultCard({
    required this.theme,
    required this.name,
    required this.avatar,
    required this.color,
    required this.cardCount,
    required this.isWinner,
    required this.isTie,
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
          color: highlighted ? color.withValues(alpha: 0.45) : color.withValues(alpha: 0.15),
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
                backgroundColor: color.withValues(alpha: 0.16),
                backgroundImage: (avatar != null && avatar!.isNotEmpty) ? NetworkImage(avatar!) : null,
                child: (avatar == null || avatar!.isEmpty)
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: color, fontSize: 18),
                      )
                    : null,
              ),
              if (isWinner)
                Positioned(
                  top: -6,
                  right: 6,
                  child: Icon(Icons.emoji_events_rounded, size: 18, color: color),
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
            '$cardCount',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: color),
          ),
          Text(
            LocaleScope.t(context, 'war_card_cards_label'),
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(fontSize: 10, color: theme.textOnBackgroundMuted),
          ),
          const SizedBox(height: 4),
          Text(
            isTie
                ? LocaleScope.t(context, 'dot_squares_score_tie_short')
                : (isWinner ? LocaleScope.t(context, 'ttt_score_won') : LocaleScope.t(context, 'ttt_score_lost')),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}
