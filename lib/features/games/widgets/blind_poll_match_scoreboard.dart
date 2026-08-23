import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/theme_palette.dart';
import '../game_service.dart';

/// Score de complicité cumulé pour "Le Sondage Surprise" (voir
/// GameCardController::pollStats) — ouvert en tapant sur le badge compact de
/// l'AppBar (voir GameBoxesScreen). Contrairement à quiz_match_scoreboard,
/// un seul pourcentage pour le couple : être "raccord" n'a de sens
/// qu'ensemble, pas de classement individuel ici.
Future<void> showBlindPollMatchScoreboard(
  BuildContext context, {
  required ThemePalette theme,
  required BlindPollStats stats,
}) {
  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PollScoreboardSheet(theme: theme, stats: stats),
  );
}

class _PollScoreboardSheet extends StatelessWidget {
  final ThemePalette theme;
  final BlindPollStats stats;

  const _PollScoreboardSheet({required this.theme, required this.stats});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: theme.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
              'Score de complicité 💚',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w800, color: theme.textOnBackground),
            ),
            const SizedBox(height: 4),
            Text(
              'Part des sondages où vous êtes tombés d\'accord',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                '${stats.percentage.toStringAsFixed(0)}%',
                style: GoogleFonts.poppins(fontSize: 44, fontWeight: FontWeight.w800, color: theme.primary),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                '${stats.aligned}/${stats.totalResolved} sondages raccord',
                style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
