import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/emoji_story_stats.dart';
import '../../../theme/theme_palette.dart';

/// Score "façon match" des deux membres du couple pour un jeu
/// `session_type = 'quiz'` (voir GameCardController::stats) — ouvert en
/// tapant sur le badge compact de l'AppBar (voir GameBoxesScreen). Copie
/// conforme de showEmojiStoryMatchScoreboard/_MatchScoreboardSheet
/// (jusqu'aux modèles réutilisés : la forme des stats est identique) —
/// seul [gameName] change le titre affiché.
Future<void> showQuizMatchScoreboard(
  BuildContext context, {
  required ThemePalette theme,
  required EmojiStoryMatchStats stats,
  required String myUserId,
  required String gameName,
}) {
  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _QuizScoreboardSheet(theme: theme, stats: stats, myUserId: myUserId, gameName: gameName),
  );
}

class _QuizScoreboardSheet extends StatelessWidget {
  final ThemePalette theme;
  final EmojiStoryMatchStats stats;
  final String myUserId;
  final String gameName;

  const _QuizScoreboardSheet({required this.theme, required this.stats, required this.myUserId, required this.gameName});

  @override
  Widget build(BuildContext context) {
    final players = stats.players;
    // Classement au % premier coup — seulement entre joueur·ses ayant au
    // moins une carte résolue (un pourcentage à 0/0 ne veut rien dire).
    final ranked = players.where((p) => p.resolvedTotal > 0).toList()
      ..sort((a, b) => b.firstTryPercentage.compareTo(a.firstTryPercentage));
    final leaderId = ranked.length >= 2 && ranked[0].firstTryPercentage > ranked[1].firstTryPercentage
        ? ranked[0].userId
        : (ranked.length == 1 ? ranked[0].userId : null);

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
              'Match — $gameName',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w800, color: theme.textOnBackground),
            ),
            const SizedBox(height: 4),
            Text(
              'Classement au % de bonnes réponses du premier coup',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
            ),
            const SizedBox(height: 20),
            if (players.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Pas encore de devinette proposée.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
                ),
              )
            else
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < players.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(
                        child: _PlayerMatchCard(
                          theme: theme,
                          player: players[i],
                          isMe: players[i].userId == myUserId,
                          isLeader: players[i].userId == leaderId,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlayerMatchCard extends StatelessWidget {
  final ThemePalette theme;
  final EmojiStoryPlayerStats player;
  final bool isMe;
  final bool isLeader;

  const _PlayerMatchCard({
    required this.theme,
    required this.player,
    required this.isMe,
    required this.isLeader,
  });

  @override
  Widget build(BuildContext context) {
    final name = isMe ? 'Toi' : (player.prenom ?? 'Ton/ta partenaire');

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
                backgroundImage: (player.avatar != null && player.avatar!.isNotEmpty)
                    ? NetworkImage(player.avatar!)
                    : null,
                child: (player.avatar == null || player.avatar!.isEmpty)
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
            player.resolvedTotal > 0 ? '${player.firstTryPercentage.toStringAsFixed(0)}%' : '—',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w800, color: theme.primary),
          ),
          Text(
            player.resolvedTotal > 0
                ? '${player.firstTry}/${player.resolvedTotal} premier coup'
                : 'Aucune carte résolue',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(fontSize: 10.5, color: theme.textOnBackgroundMuted),
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: theme.primary.withValues(alpha: 0.12)),
          const SizedBox(height: 10),
          _StatRow(theme: theme, icon: Icons.send_rounded, label: 'Proposées', value: player.proposed),
          _StatRow(theme: theme, icon: Icons.bolt_rounded, label: 'Premier coup', value: player.firstTry),
          _StatRow(theme: theme, icon: Icons.replay_rounded, label: 'Après une chance', value: player.afterFirstTry),
          _StatRow(theme: theme, icon: Icons.close_rounded, label: 'Jamais trouvé', value: player.missed),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final ThemePalette theme;
  final IconData icon;
  final String label;
  final int value;

  const _StatRow({required this.theme, required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 13, color: theme.textOnBackgroundMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.nunito(fontSize: 11, color: theme.textOnBackgroundMuted),
            ),
          ),
          Text(
            '$value',
            style: GoogleFonts.nunito(fontSize: 11.5, fontWeight: FontWeight.w800, color: theme.textOnBackground),
          ),
        ],
      ),
    );
  }
}
