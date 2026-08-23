import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Palette complète d'un thème sélectionnable — chaque personne du couple
/// choisit la sienne indépendamment (préférence locale, pas partagée via la
/// Box). Ne couvre que les 4 écrans d'onglets (Dashboard/Galerie/Jeux/
/// Profil) ; les écrans secondaires (Boutique, Cadeaux, Poèmes-Slides,
/// Coffre Photo...) restent volontairement sur la palette par défaut.
class ThemePalette {
  final String id;
  final String name;
  final String emoji;
  final Color background;
  final Color surface;
  final Color primary;
  final Color primaryDeep;
  final Color secondary;
  final Color accent;
  final Color textOnBackground;
  final Color textOnBackgroundMuted;

  /// Pilote la luminosité des icônes système, du splash, etc.
  final bool isDark;

  /// Fond illustré (dégradés + étoiles/montagnes/brume procédurales — voir
  /// `theme/backgrounds/`) qui remplace [backgroundGradient] quand présent.
  /// `null` pour les thèmes "classiques" (dégradé plat uni).
  final WidgetBuilder? sceneBackground;

  const ThemePalette({
    required this.id,
    required this.name,
    required this.emoji,
    required this.background,
    required this.surface,
    required this.primary,
    required this.primaryDeep,
    required this.secondary,
    required this.accent,
    required this.textOnBackground,
    required this.textOnBackgroundMuted,
    required this.isDark,
    this.sceneBackground,
  });

  LinearGradient get backgroundGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [background, Color.lerp(background, Colors.black, isDark ? 0.15 : 0.02)!],
      );

  LinearGradient get accentGradient => LinearGradient(colors: [primary, secondary]);

  /// Style d'icônes pour la barre de statut/navigation système, dérivé
  /// d'[isDark] plutôt que de la couleur de fond réelle d'une AppBar — une
  /// AppBar transparente n'a pas de couleur exploitable (Flutter estime la
  /// luminosité d'un `Colors.transparent` comme "noire", ignorant l'alpha,
  /// et choisirait donc des icônes claires même sur un thème clair, les
  /// rendant invisibles — voir demande utilisateur, capture d'écran
  /// "Jeux de Couple"). À passer explicitement à chaque `AppBar` dont le
  /// fond est transparent, plutôt que de compter sur le calcul automatique
  /// de Flutter.
  SystemUiOverlayStyle get statusBarOverlayStyle => SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      );
}
