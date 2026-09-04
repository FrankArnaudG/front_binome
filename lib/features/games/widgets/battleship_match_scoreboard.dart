import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../theme/theme_scope.dart';
import '../battleship/battleship_transport.dart';

/// Score de fin de partie pour "Bataille Navale" — pas d'égalité possible
/// (il y a toujours un vainqueur, celui qui coule la flotte adverse en
/// premier) — copie structurelle allégée de showConnectFourMatchScoreboard.
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

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final winnerName = playerNames[state.winnerUserId] ?? LocaleScope.t(context, 'memory_score_player_fallback');
    final avatar = playerAvatars[state.winnerUserId];

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
            CircleAvatar(
              radius: 32,
              backgroundColor: theme.primary.withValues(alpha: 0.16),
              backgroundImage: (avatar != null && avatar.isNotEmpty) ? NetworkImage(avatar) : null,
              child: (avatar == null || avatar.isEmpty)
                  ? Icon(Icons.emoji_events_rounded, size: 32, color: theme.primary)
                  : null,
            ),
            const SizedBox(height: 12),
            Text(
              LocaleScope.t(context, 'battleship_score_winner', {'name': winnerName}),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w800, color: theme.textOnBackground),
            ),
            const SizedBox(height: 4),
            Text(
              '$minutes:${seconds.toString().padLeft(2, '0')}',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
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
