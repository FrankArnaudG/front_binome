import 'package:flutter/material.dart';

/// Identité "Binome" : un rose vif comme accent unique, posé sur deux
/// fonds fixes (navy immersif pour l'onboarding/le jeu, blush pour la
/// connexion et les écrans de compte) — pas de dark mode système.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFFFF3B5C); // rose grenadine
  static const Color primaryDeep = Color(0xFFE0294A);
  static const Color secondary = Color(0xFF7C6BFF); // lavande (accents discrets)
  static const Color accent = Color(0xFFFFB199); // pêche

  static const Color navy = Color(0xFF14102B);
  static const Color navyDeep = Color(0xFF0C0A1C);
  static const Color navySurface = Color(0xFF211A3D);

  static const Color blush = Color(0xFFFFF1EC);
  static const Color blushCard = Color(0xFFFFFFFF);

  static const Color textOnNavy = Color(0xFFFDF6FF);
  static const Color textOnNavyMuted = Color(0xB3FDF6FF);
  static const Color textOnBlush = Color(0xFF241733);
  static const Color textOnBlushMuted = Color(0x99241733);

  static const List<Color> heroOverlay = [Color(0x00000000), Color(0xE6120B22)];
}
