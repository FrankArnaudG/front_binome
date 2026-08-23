import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Thème unique et fixe : l'app ne suit pas le dark mode système, chaque
/// écran choisit explicitement son fond (navy ou blush) pour garder une
/// identité de marque constante.
class AppTheme {
  AppTheme._();

  static ThemeData get base {
    final colorScheme = const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.secondary,
      onSecondary: Colors.white,
      tertiary: AppColors.accent,
      onTertiary: AppColors.textOnBlush,
      error: Color(0xFFCF6679),
      onError: Colors.white,
      surface: AppColors.blushCard,
      onSurface: AppColors.textOnBlush,
    );

    final textTheme = GoogleFonts.nunitoTextTheme().copyWith(
      displayLarge: GoogleFonts.poppins(
        fontSize: 40,
        fontWeight: FontWeight.w800,
        height: 1.05,
        letterSpacing: -0.5,
      ),
      displaySmall: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w700, height: 1.1),
      headlineMedium: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w700),
      titleLarge: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600),
      bodyLarge: GoogleFonts.nunito(fontSize: 16),
      bodyMedium: GoogleFonts.nunito(fontSize: 14),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.blush,
      textTheme: textTheme,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
          textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
