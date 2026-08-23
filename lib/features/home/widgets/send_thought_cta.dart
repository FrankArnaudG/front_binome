import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../theme/theme_scope.dart';

/// Action rapide la plus visible du Dashboard : "Envoyer une pensée" ouvre
/// directement la bibliothèque de slides — mise en avant par rapport aux
/// autres actions (secondaires, en grille) pour guider l'usage quotidien.
class SendThoughtCta extends StatelessWidget {
  final VoidCallback onTap;

  const SendThoughtCta({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
          decoration: BoxDecoration(
            gradient: theme.accentGradient,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [BoxShadow(color: theme.primary.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
                child: const Icon(Icons.auto_stories_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('cta_send_thought'),
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t('cta_send_thought_hint'),
                      style: GoogleFonts.nunito(fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
