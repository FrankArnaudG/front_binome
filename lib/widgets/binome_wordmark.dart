import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// Logo texte "Binome" — le "i" est remplacé par un petit cœur pour garder
/// une lecture claire du nom tout en signant la marque.
class BinomeWordmark extends StatelessWidget {
  final double fontSize;
  final Color color;

  /// Couleur du cœur — [AppColors.primary] (rose de marque fixe) par
  /// défaut pour les écrans hors thème personnel (Login, Splash...).
  /// Passer `theme.primary` explicitement sur un écran qui suit le thème
  /// choisi par la personne (ex. Dashboard), pour rester cohérent avec les
  /// ~16 thèmes possibles plutôt qu'un rose imposé qui jurerait sur un
  /// thème doré/émeraude/océan.
  final Color heartColor;

  const BinomeWordmark({
    super.key,
    this.fontSize = 24,
    this.color = Colors.white,
    this.heartColor = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.poppins(fontSize: fontSize, fontWeight: FontWeight.w700, color: color);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('B', style: style),
        Transform.translate(
          offset: Offset(0, fontSize * 0.1),
          child: Icon(Icons.favorite_rounded, color: heartColor, size: fontSize * 0.78),
        ),
        Text('nome', style: style),
      ],
    );
  }
}
