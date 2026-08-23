import 'package:flutter/material.dart';

import 'backgrounds/scene_backgrounds.dart';
import 'theme_palette.dart';

WidgetBuilder _scene(String id) => sceneBackgrounds.firstWhere((s) => s.id == id).builder;

/// 18 thèmes prêts à l'emploi, autour de différentes ambiances romantiques —
/// un mélange volontaire de clair/sombre et de tons chauds/froids, sans
/// présumer qui préfère quoi : chacun choisit le sien dans les Paramètres.
/// Les 10 derniers ont un fond illustré (dégradé + étoiles/montagnes/brume
/// procédurales, voir `backgrounds/scene_backgrounds.dart`) — leurs
/// couleurs de surface/texte/accent ont été choisies pour rester lisibles
/// et cohérentes par-dessus ce fond, pas juste reprises d'un thème plat.
class ThemePresets {
  ThemePresets._();

  static const douceurPoudree = ThemePalette(
    id: 'douceur_poudree',
    name: 'Douceur Poudrée',
    emoji: '🌸',
    background: Color(0xFFFFF1EC),
    surface: Color(0xFFFFFFFF),
    primary: Color(0xFFFF3B5C),
    primaryDeep: Color(0xFFE0294A),
    secondary: Color(0xFF7C6BFF),
    accent: Color(0xFFFFB199),
    textOnBackground: Color(0xFF241733),
    textOnBackgroundMuted: Color(0x99241733),
    isDark: false,
  );

  static const nuitEtoilee = ThemePalette(
    id: 'nuit_etoilee',
    name: 'Nuit Étoilée',
    emoji: '🌙',
    background: Color(0xFF14102B),
    surface: Color(0xFF211A3D),
    primary: Color(0xFFFF3B5C),
    primaryDeep: Color(0xFFE0294A),
    secondary: Color(0xFF7C6BFF),
    accent: Color(0xFFFFB199),
    textOnBackground: Color(0xFFFDF6FF),
    textOnBackgroundMuted: Color(0xB3FDF6FF),
    isDark: true,
  );

  static const coucherDeSoleil = ThemePalette(
    id: 'coucher_de_soleil',
    name: 'Coucher de Soleil',
    emoji: '🌅',
    background: Color(0xFFFFF4E6),
    surface: Color(0xFFFFFFFF),
    primary: Color(0xFFFF6B4A),
    primaryDeep: Color(0xFFE5502F),
    secondary: Color(0xFFFF9770),
    accent: Color(0xFFFFD166),
    textOnBackground: Color(0xFF3D2B1F),
    textOnBackgroundMuted: Color(0x993D2B1F),
    isDark: false,
  );

  static const romanceBordeaux = ThemePalette(
    id: 'romance_bordeaux',
    name: 'Romance Bordeaux',
    emoji: '🍷',
    background: Color(0xFF2B0E14),
    surface: Color(0xFF3D1620),
    primary: Color(0xFFC0294A),
    primaryDeep: Color(0xFF8F1F38),
    secondary: Color(0xFFD4AF37),
    accent: Color(0xFFE8B4B8),
    textOnBackground: Color(0xFFF5E6E8),
    textOnBackgroundMuted: Color(0xB3F5E6E8),
    isDark: true,
  );

  static const lavandeDouce = ThemePalette(
    id: 'lavande_douce',
    name: 'Lavande Douce',
    emoji: '💜',
    background: Color(0xFFF3EEFF),
    surface: Color(0xFFFFFFFF),
    primary: Color(0xFF9B7EDE),
    primaryDeep: Color(0xFF7B5BC4),
    secondary: Color(0xFFFF9FC7),
    accent: Color(0xFFC9B6FF),
    textOnBackground: Color(0xFF2E2447),
    textOnBackgroundMuted: Color(0x992E2447),
    isDark: false,
  );

  static const oceanTendresse = ThemePalette(
    id: 'ocean_tendresse',
    name: 'Océan Tendresse',
    emoji: '🌊',
    background: Color(0xFFEAF7F7),
    surface: Color(0xFFFFFFFF),
    primary: Color(0xFF2AA8A0),
    primaryDeep: Color(0xFF1E8A82),
    secondary: Color(0xFF5BA3D0),
    accent: Color(0xFF7FD8C8),
    textOnBackground: Color(0xFF0F3B3A),
    textOnBackgroundMuted: Color(0x990F3B3A),
    isDark: false,
  );

  static const doreElegance = ThemePalette(
    id: 'dore_elegance',
    name: 'Doré Élégance',
    emoji: '✨',
    background: Color(0xFF161310),
    surface: Color(0xFF231E17),
    primary: Color(0xFFD4AF37),
    primaryDeep: Color(0xFFA9862A),
    secondary: Color(0xFFB08D57),
    accent: Color(0xFFF0D590),
    textOnBackground: Color(0xFFF5EFDD),
    textOnBackgroundMuted: Color(0xB3F5EFDD),
    isDark: true,
  );

  static const emeraudePassion = ThemePalette(
    id: 'emeraude_passion',
    name: 'Émeraude Passion',
    emoji: '💚',
    background: Color(0xFF0E1F1A),
    surface: Color(0xFF16302A),
    primary: Color(0xFF2ECC91),
    primaryDeep: Color(0xFF1F9E70),
    secondary: Color(0xFFE8A0A0),
    accent: Color(0xFF7FE0BE),
    textOnBackground: Color(0xFFE8F5F0),
    textOnBackgroundMuted: Color(0xB3E8F5F0),
    isDark: true,
  );

  static final sunsetMountains = ThemePalette(
    id: 'sunset_mountains',
    name: 'Coucher de Soleil Montagnes',
    emoji: '🏔️',
    background: const Color(0xFFE8833A),
    surface: const Color(0xE6FFF3E0),
    primary: const Color(0xFFE8572E),
    primaryDeep: const Color(0xFF9C4E22),
    secondary: const Color(0xFF7A3818),
    accent: const Color(0xFFFDDFA0),
    textOnBackground: const Color(0xFF3A2410),
    textOnBackgroundMuted: const Color(0x993A2410),
    isDark: false,
    sceneBackground: _scene('sunset_mountains'),
  );

  static final sunsetMountainsPink = ThemePalette(
    id: 'sunset_mountains_pink',
    name: 'Crépuscule Rosé Montagnes',
    emoji: '🌄',
    background: const Color(0xFFC2528F),
    surface: const Color(0xE6FFF0F5),
    primary: const Color(0xFFC2528F),
    primaryDeep: const Color(0xFF9C3A6E),
    secondary: const Color(0xFF6E4560),
    accent: const Color(0xFFFDE4E0),
    textOnBackground: const Color(0xFF3E1E30),
    textOnBackgroundMuted: const Color(0x993E1E30),
    isDark: false,
    sceneBackground: _scene('sunset_mountains_pink'),
  );

  static final nightStarsSoft = ThemePalette(
    id: 'night_stars_soft',
    name: 'Nuit Étoilée Douce',
    emoji: '⭐',
    background: const Color(0xFF0C0E2E),
    surface: const Color(0xCC12183A),
    primary: const Color(0xFF6E8FD8),
    primaryDeep: const Color(0xFF4A63A8),
    secondary: const Color(0xFFB98CA0),
    accent: const Color(0xFFFFFFFF),
    textOnBackground: const Color(0xFFF5F0FA),
    textOnBackgroundMuted: const Color(0xB3F5F0FA),
    isDark: true,
    sceneBackground: _scene('night_stars_soft'),
  );

  static final nightStarsDense = ThemePalette(
    id: 'night_stars_dense',
    name: 'Nuit Étoilée Dense',
    emoji: '🌌',
    background: const Color(0xFF0C0E2E),
    surface: const Color(0xCC12183A),
    primary: const Color(0xFF6E8FD8),
    primaryDeep: const Color(0xFF4A63A8),
    secondary: const Color(0xFFB98CA0),
    accent: const Color(0xFFFFFFFF),
    textOnBackground: const Color(0xFFF5F0FA),
    textOnBackgroundMuted: const Color(0xB3F5F0FA),
    isDark: true,
    sceneBackground: _scene('night_stars_dense'),
  );

  static final nightSparkleTeal = ThemePalette(
    id: 'night_sparkle_teal',
    name: 'Nuit Scintillante',
    emoji: '✨',
    background: const Color(0xFF0C3B3E),
    surface: const Color(0xCC102A30),
    primary: const Color(0xFF4FD8C4),
    primaryDeep: const Color(0xFF2E9C8C),
    secondary: const Color(0xFFB85A9E),
    accent: const Color(0xFFFFF6E0),
    textOnBackground: const Color(0xFFEFFAF8),
    textOnBackgroundMuted: const Color(0xB3EFFAF8),
    isDark: true,
    sceneBackground: _scene('night_sparkle_teal'),
  );

  static final nightSparkleIndigo = ThemePalette(
    id: 'night_sparkle_indigo',
    name: 'Nuit Scintillante Indigo',
    emoji: '💫',
    background: const Color(0xFF10123A),
    surface: const Color(0xCC1A1440),
    primary: const Color(0xFF8C7AF0),
    primaryDeep: const Color(0xFF5E4AC8),
    secondary: const Color(0xFFC45A9E),
    accent: const Color(0xFFF0EBFF),
    textOnBackground: const Color(0xFFF2EEFA),
    textOnBackgroundMuted: const Color(0xB3F2EEFA),
    isDark: true,
    sceneBackground: _scene('night_sparkle_indigo'),
  );

  static final goldenHaze = ThemePalette(
    id: 'golden_haze',
    name: 'Brume Dorée',
    emoji: '🌤️',
    background: const Color(0xFFF5A85A),
    surface: const Color(0xE6FFF8E8),
    primary: const Color(0xFFF0A24E),
    primaryDeep: const Color(0xFFD9863A),
    secondary: const Color(0xFFF7CE8E),
    accent: const Color(0xFFFFFCF3),
    textOnBackground: const Color(0xFF4A3418),
    textOnBackgroundMuted: const Color(0x994A3418),
    isDark: false,
    sceneBackground: _scene('golden_haze'),
  );

  static final goldenHazePink = ThemePalette(
    id: 'golden_haze_pink',
    name: 'Brume Rosée',
    emoji: '🌸',
    background: const Color(0xFFE58FA8),
    surface: const Color(0xE6FDF0F5),
    primary: const Color(0xFFE58FA8),
    primaryDeep: const Color(0xFFC46888),
    secondary: const Color(0xFFF3C9DE),
    accent: const Color(0xFFFFF7FB),
    textOnBackground: const Color(0xFF4A2438),
    textOnBackgroundMuted: const Color(0x994A2438),
    isDark: false,
    sceneBackground: _scene('golden_haze_pink'),
  );

  static final duskMountainsStars = ThemePalette(
    id: 'dusk_mountains_stars',
    name: 'Crépuscule Montagnes Étoilé',
    emoji: '🌆',
    background: const Color(0xFF1B1F52),
    surface: const Color(0xCC201038),
    primary: const Color(0xFFE8875A),
    primaryDeep: const Color(0xFFC46A3E),
    secondary: const Color(0xFFB84F6E),
    accent: const Color(0xFFF4A85E),
    textOnBackground: const Color(0xFFFAF0E8),
    textOnBackgroundMuted: const Color(0xB3FAF0E8),
    isDark: true,
    sceneBackground: _scene('dusk_mountains_stars'),
  );

  static final dawnMountainsStars = ThemePalette(
    id: 'dawn_mountains_stars',
    name: 'Aube Montagnes Étoilée',
    emoji: '🌅',
    background: const Color(0xFF1C2258),
    surface: const Color(0xCC1E2448),
    primary: const Color(0xFF8FA0D0),
    primaryDeep: const Color(0xFF5E6FA8),
    secondary: const Color(0xFFC7B8D8),
    accent: const Color(0xFFEDE0E8),
    textOnBackground: const Color(0xFFF2F0F8),
    textOnBackgroundMuted: const Color(0xB3F2F0F8),
    isDark: true,
    sceneBackground: _scene('dawn_mountains_stars'),
  );

  static final all = <ThemePalette>[
    douceurPoudree,
    coucherDeSoleil,
    lavandeDouce,
    oceanTendresse,
    nuitEtoilee,
    romanceBordeaux,
    doreElegance,
    emeraudePassion,
    sunsetMountains,
    sunsetMountainsPink,
    nightStarsSoft,
    nightStarsDense,
    nightSparkleTeal,
    nightSparkleIndigo,
    goldenHaze,
    goldenHazePink,
    duskMountainsStars,
    dawnMountainsStars,
  ];

  static const defaultTheme = douceurPoudree;

  static ThemePalette byId(String id) => all.firstWhere((t) => t.id == id, orElse: () => defaultTheme);
}
