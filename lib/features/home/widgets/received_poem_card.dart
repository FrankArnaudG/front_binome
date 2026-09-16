import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../models/send.dart';
import '../../../theme/theme_scope.dart';

/// Affiche le contenu du poème reçu aujourd'hui (Rituel du Soir) — à ne pas
/// confondre avec [SendThoughtCta], qui incite à *envoyer* un poème (et
/// bascule elle-même vers un texte "rituel du soir" une fois l'heure
/// passée). Les deux peuvent coexister : recevoir n'empêche pas d'envoyer
/// le sien.
class ReceivedPoemCard extends StatelessWidget {
  final Send poem;
  final VoidCallback onTap;

  const ReceivedPoemCard({super.key, required this.poem, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return Material(
      color: theme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.primary.withValues(alpha: 0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.mark_email_unread_rounded, color: theme.primary, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('poem_received_title', {'name': poem.sender?.prenom ?? ''}),
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: theme.textOnBackground),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      poem.slide?.textFor(LocaleScope.of(context).current.code) ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.textOnBackgroundMuted),
            ],
          ),
        ),
      ),
    );
  }
}
