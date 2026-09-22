import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../memory_game/memory_game_transport.dart';

/// Score de fin de partie pour "Jeu de Mémoire" — copie structurelle
/// d'emoji_story_match_scoreboard.dart, adaptée au seul score qui a du
/// sens sur un plateau PARTAGÉ : le nombre de paires trouvées par chacun
/// (voir demande utilisateur) — pas de "temps/coups par joueur", affichés
/// en info secondaire au niveau de la partie, pas du joueur.
///
/// Calculé directement depuis [state] (déjà disponible client-side en
/// temps réel), jamais via un aller-retour réseau supplémentaire — les 3
/// modes affichent ce même popup de la même façon.
///
/// Retourne `true` si le joueur a tapé "Rejouer" (voir [allowRematch]) —
/// à l'appelant de relancer une partie via `startMemoryGameAndPush`,
/// jamais fait ici pour ne pas coupler ce widget à la logique de
/// démarrage d'une session.
Future<bool?> showMemoryGameMatchScoreboard(
  BuildContext context, {
  required MemoryGameBoardState state,
  required Map<String, String> playerNames,
  required Map<String, String?> playerAvatars,
  bool allowRematch = false,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MemoryScoreboardSheet(
      state: state,
      playerNames: playerNames,
      playerAvatars: playerAvatars,
      allowRematch: allowRematch,
    ),
  );
}

class _MemoryScoreboardSheet extends StatelessWidget {
  final MemoryGameBoardState state;
  final Map<String, String> playerNames;
  final Map<String, String?> playerAvatars;
  final bool allowRematch;

  const _MemoryScoreboardSheet({
    required this.state,
    required this.playerNames,
    required this.playerAvatars,
    required this.allowRematch,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);

    final pairsByUser = <String, int>{};
    for (final pair in state.matched) {
      pairsByUser[pair.userId] = (pairsByUser[pair.userId] ?? 0) + 1;
    }
    final players = playerNames.keys.toList();
    final leaderId = players.length >= 2 &&
            (pairsByUser[players[0]] ?? 0) != (pairsByUser[players[1]] ?? 0)
        ? (players..sort((a, b) => (pairsByUser[b] ?? 0).compareTo(pairsByUser[a] ?? 0))).first
        : null;

    final minutes = state.startedAt != null
        ? DateTime.now().difference(state.startedAt!).inSeconds ~/ 60
        : 0;
    final seconds = state.startedAt != null
        ? DateTime.now().difference(state.startedAt!).inSeconds % 60
        : 0;

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
            Text(
              LocaleScope.t(context, 'memory_score_title'),
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
                      child: _PlayerScoreCard(
                        theme: theme,
                        name: playerNames[players[i]] ?? LocaleScope.t(context, 'memory_score_player_fallback'),
                        avatar: playerAvatars[players[i]],
                        pairsFound: pairsByUser[players[i]] ?? 0,
                        isLeader: players[i] == leaderId,
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

class _PlayerScoreCard extends StatelessWidget {
  final ThemePalette theme;
  final String name;
  final String? avatar;
  final int pairsFound;
  final bool isLeader;

  const _PlayerScoreCard({
    required this.theme,
    required this.name,
    required this.avatar,
    required this.pairsFound,
    required this.isLeader,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLeader ? theme.primary.withValues(alpha: 0.45) : theme.primary.withValues(alpha: 0.12),
          width: isLeader ? 1.4 : 1,
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
              if (isLeader)
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
          const SizedBox(height: 10),
          Text(
            '$pairsFound',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w800, color: theme.primary),
          ),
          Text(
            LocaleScope.t(context, pairsFound > 1 ? 'memory_score_pairs_plural' : 'memory_score_pairs_singular'),
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(fontSize: 10.5, color: theme.textOnBackgroundMuted),
          ),
        ],
      ),
    );
  }
}
