import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_presets.dart';
import '../../../theme/theme_scope.dart';
import '../../../widgets/themed_card.dart';

/// Sélecteur de thème personnel — chaque personne du couple choisit le
/// sien, indépendamment de son/sa partenaire (préférence locale, pas
/// synchronisée). S'applique aux 4 écrans d'onglets uniquement.
class ThemePickerCard extends StatelessWidget {
  const ThemePickerCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final controller = ThemeScope.of(context);
    final t = LocaleScope.of(context).t;

    return ThemedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('theme_title'), style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: theme.textOnBackground)),
          const SizedBox(height: 4),
          Text(
            t('theme_subtitle'),
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
            itemCount: ThemePresets.all.length,
            itemBuilder: (context, index) {
              final preset = ThemePresets.all[index];
              return _ThemeSwatch(
                preset: preset,
                selected: preset.id == theme.id,
                onTap: () => controller.select(preset.id),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  final ThemePalette preset;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeSwatch({required this.preset, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ambientTheme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

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
              gradient: LinearGradient(colors: [preset.background, preset.primary, preset.secondary]),
              border: Border.all(
                color: selected ? preset.primary : Colors.transparent,
                width: 2.5,
              ),
              boxShadow: selected ? [BoxShadow(color: preset.primary.withValues(alpha: 0.4), blurRadius: 8)] : null,
            ),
            child: selected
                ? const Center(child: Icon(Icons.check_rounded, color: Colors.white, size: 18))
                : Center(child: Text(preset.emoji, style: const TextStyle(fontSize: 16))),
          ),
          const SizedBox(height: 4),
          Text(
            t('theme_name_${preset.id}'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.nunito(
              fontSize: 9.5,
              height: 1.15,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? preset.primary : ambientTheme.textOnBackgroundMuted,
            ),
          ),
        ],
      ),
    );
  }
}
