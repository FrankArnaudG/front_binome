import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Logo "Binome" — deux images superposées (voir demande utilisateur :
/// remplacer le rendu par code, source d'un bug d'alignement récurrent, par
/// l'image fournie), chacune teintée dynamiquement via [ColorFiltered] :
/// [binome_wordmark_text.png] (silhouette des lettres) prend [color],
/// [binome_wordmark_heart.png] (silhouette du cœur seul) prend [heartColor]
/// — les deux images partagent exactement le même cadrage (issues du même
/// fichier source découpé en deux), donc toujours parfaitement alignées,
/// sans dépendre des métriques d'une police.
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
    final height = fontSize * 1.1;
    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          ColorFiltered(
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            child: Image.asset('assets/logo/binome_wordmark_text.png', height: height, fit: BoxFit.contain),
          ),
          ColorFiltered(
            colorFilter: ColorFilter.mode(heartColor, BlendMode.srcIn),
            child: Image.asset('assets/logo/binome_wordmark_heart.png', height: height, fit: BoxFit.contain),
          ),
        ],
      ),
    );
  }
}
