import 'package:flutter/material.dart';

import '../../theme/theme_palette.dart';

/// Icône/dégradé d'une catégorie de Poèmes-Slides, par slug — choix produit
/// volontairement fixé côté app (pas de sélecteur d'icône dans l'admin, voir
/// PackCategoryController côté backend). Le nom/l'accroche viennent de
/// l'admin, traduits dans les 12 langues (voir [PackCategory] et
/// ContentService.fetchPackCategories) — [PackCategoryVisual] ne porte plus
/// que l'apparence.
class PackCategoryVisual {
  final String assetName;
  final IconData icon;
  final Color Function(ThemePalette) colorStart;
  final Color Function(ThemePalette) colorEnd;

  const PackCategoryVisual(
    this.assetName,
    this.icon,
    this.colorStart,
    this.colorEnd,
  );

  List<Color> gradient(ThemePalette theme) => [colorStart(theme), colorEnd(theme)];
}

const Map<String, PackCategoryVisual> packCategoryVisuals = {
  'morning': PackCategoryVisual('category_morning.png', Icons.wb_sunny_rounded, _accent, _primary),
  'night': PackCategoryVisual('category_night.png', Icons.nightlight_round, _primaryDeep, _secondary),
  'distance': PackCategoryVisual('category_distance.png', Icons.flight_rounded, _secondary, _primary),
  'celebration': PackCategoryVisual('category_celebration.png', Icons.celebration_rounded, _primary, _accent),
  'reconciliation': PackCategoryVisual('category_reconciliation.png', Icons.volunteer_activism_rounded, _accent, _secondary),
  'humor': PackCategoryVisual('category_humor.png', Icons.emoji_emotions_rounded, _secondary, _accent),
  'gratitude': PackCategoryVisual('category_gratitude.png', Icons.spa_rounded, _primaryDeep, _accent),
  'flirt': PackCategoryVisual('category_flirt.png', Icons.local_fire_department_rounded, _primary, _secondary),
  'future': PackCategoryVisual('category_future.png', Icons.auto_awesome_rounded, _accent, _primaryDeep),
};

const _defaultVisual = PackCategoryVisual('category_default.png', Icons.favorite_rounded, _primary, _secondary);

PackCategoryVisual visualForCategory(String slug) => packCategoryVisuals[slug] ?? _defaultVisual;

Color _accent(ThemePalette t) => t.accent;
Color _primary(ThemePalette t) => t.primary;
Color _primaryDeep(ThemePalette t) => t.primaryDeep;
Color _secondary(ThemePalette t) => t.secondary;
