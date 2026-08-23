import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/app_locale.dart';
import '../../../l10n/locale_scope.dart';
import '../../../theme/theme_scope.dart';
import '../../../widgets/themed_card.dart';

/// Sélecteur de langue personnel — chaque personne du couple choisit la
/// sienne, indépendamment de son/sa partenaire (même principe que
/// [ThemePickerCard]). S'applique aux 4 écrans d'onglets uniquement.
class LanguagePickerCard extends StatelessWidget {
  const LanguagePickerCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final controller = LocaleScope.of(context);
    final t = controller.t;

    return ThemedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('language_title'), style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: theme.textOnBackground)),
          const SizedBox(height: 4),
          Text(
            t('language_subtitle'),
            style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 14,
              crossAxisSpacing: 8,
              childAspectRatio: 0.62,
            ),
            itemCount: AppLocale.all.length,
            itemBuilder: (context, index) {
              final locale = AppLocale.all[index];
              return _LocaleSwatch(
                locale: locale,
                selected: locale.code == controller.current.code,
                onTap: () => controller.select(locale.code),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LocaleSwatch extends StatelessWidget {
  final AppLocale locale;
  final bool selected;
  final VoidCallback onTap;

  const _LocaleSwatch({required this.locale, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.surface,
              border: Border.all(
                color: selected ? theme.primary : Colors.transparent,
                width: 2.5,
              ),
              boxShadow: selected ? [BoxShadow(color: theme.primary.withValues(alpha: 0.4), blurRadius: 8)] : null,
            ),
            child: selected
                ? Center(child: Icon(Icons.check_rounded, color: theme.primary, size: 18))
                : Center(child: Text(locale.flag, style: const TextStyle(fontSize: 18))),
          ),
          const SizedBox(height: 4),
          Text(
            locale.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.nunito(
              fontSize: 9.5,
              height: 1.15,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? theme.primary : theme.textOnBackgroundMuted,
            ),
          ),
        ],
      ),
    );
  }
}
