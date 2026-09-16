import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/mood.dart';
import '../../theme/theme_scope.dart';

/// Modale "mignonne" affichant le conseil/défi personnalisé pour l'humeur
/// du binôme (voir demande utilisateur) — ouverte au tap sur son image
/// d'humeur dans la carte "Météo du couple" du Dashboard.
Future<void> showMoodSuggestionModal(
  BuildContext context, {
  required String moodKey,
  required String? gender,
  required String? name,
  required MoodSuggestion suggestion,
}) {
  final theme = ThemeScope.paletteOf(context);
  // Le texte brut ("Ma solution") alterne contexte / défi (souvent préfixé
  // d'un emoji) / encouragement, séparés par une ligne vide — on met le
  // paragraphe du défi en valeur dans sa propre carte plutôt que d'afficher
  // un seul bloc de texte plat.
  final parts = suggestion.solution.split('\n\n').where((p) => p.trim().isNotEmpty).toList();

  return showModalBottomSheet(
    context: context,
    backgroundColor: theme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: theme.textOnBackgroundMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 56,
                    height: 56,
                    color: theme.background,
                    child: Image.asset(moodAssetPath(moodKey, gender), fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  // Un seul titre, en gras (voir demande utilisateur) —
                  // remplace l'ancienne paire légende + besoin ("Pour
                  // combler Frank aujourd'hui" / "Être aimé").
                  child: Text(
                    name != null ? 'Pour combler $name aujourd\'hui' : 'Pour le/la combler aujourd\'hui',
                    style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: theme.textOnBackground),
                  ),
                ),
              ],
            ),
            if (suggestion.proposition != null) ...[
              const SizedBox(height: 14),
              Text(
                suggestion.proposition!,
                style: GoogleFonts.nunito(fontSize: 13, fontStyle: FontStyle.italic, color: theme.textOnBackgroundMuted),
              ),
            ],
            const SizedBox(height: 16),
            ...parts.asMap().entries.map((entry) {
              final isChallenge = entry.value.contains('Défi');
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: isChallenge
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: theme.primary.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          entry.value,
                          style: GoogleFonts.nunito(fontSize: 14.5, fontWeight: FontWeight.w600, color: theme.textOnBackground),
                        ),
                      )
                    : Text(
                        entry.value,
                        style: GoogleFonts.nunito(fontSize: 14, color: theme.textOnBackground, height: 1.4),
                      ),
              );
            }),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Fermer', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
