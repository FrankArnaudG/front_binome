import 'package:flutter/material.dart';

import '../../../l10n/locale_scope.dart';
import '../../../models/slide.dart';
import '../../../theme/handwritten_fonts.dart';
import '../../../theme/theme_palette.dart';
import '../../../widgets/asset_or_fallback.dart';
import '../content_service.dart';
import '../pack_categories.dart';

bool isNetworkMediaPath(String? path) =>
    path != null && (path.startsWith('http://') || path.startsWith('https://'));

/// Fond d'une carte de slide sans image propre : image par défaut de la
/// catégorie (packagée dans l'app), sinon ambiance historique `mood_<slug>`,
/// sinon l'illustration générique (hero), comme sur les cartes de pack.
Widget _categoryBackground(String category, String? senderGender) =>
    categoryImage(
      category,
      gender: senderGender,
      fallback: AssetOrFallback(
        assetPath: 'assets/images/mood_$category.png',
        fit: BoxFit.cover,
        fallback: Image.asset(
          'assets/images/hero_couple.jpg',
          fit: BoxFit.cover,
        ),
      ),
    );

/// Le même habillage visuel que le feed "Envoyer une pensée" (voir
/// PackFeedScreen) : image ou ambiance de catégorie en fond, voile sombre en
/// bas, légende (ou habillage personnalisé du studio admin) par-dessus.
/// Réutilisé tel quel pour revisionner une slide déjà envoyée depuis le
/// Carnet de bord, afin que l'expérience reste identique qu'on parcoure un
/// pack ou qu'on rouvre un souvenir.
class SlideVisualCard extends StatelessWidget {
  final Slide slide;
  final ThemePalette theme;
  final String? category;

  /// Genre ("Homme"/"Femme") de la personne qui ENVOIE le poème — sert à
  /// choisir la variante genrée de l'image de catégorie (ex. "Manque de toi" :
  /// on voit la personne qui est en manque, donc l'expéditeur, pour lui comme
  /// pour son binôme qui reçoit).
  final String? senderGender;
  final double borderRadius;
  final double captionRightPadding;
  final Widget? overlay;

  /// Multiplie tailles de texte/espacements de la légende — 1.0 par défaut
  /// (taille "pleine carte"). À réduire (ex. 0.45) quand la carte est
  /// affichée en miniature (aperçu dans le fil de discussion) : les valeurs
  /// par défaut sont pensées pour une carte pleine largeur et paraissent
  /// démesurées telles quelles sur une petite carte.
  final double scale;

  const SlideVisualCard({
    super.key,
    required this.slide,
    required this.theme,
    this.category,
    this.senderGender,
    this.borderRadius = 24,
    this.captionRightPadding = 24,
    this.overlay,
    this.scale = 1,
  });

  @override
  Widget build(BuildContext context) {
    final localeCode = LocaleScope.of(context).current.code;
    final categoryLabel = category != null
        ? ContentService.instance.categoryLabelSync(category!, localeCode) ??
              category!.toUpperCase()
        : null;
    final slideText = slide.textFor(localeCode) ?? '';

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        // Dégradé du thème toujours présent en-dessous — l'image d'ambiance
        // (bougie, chambre tamisée, ciel étoilé...) vient se poser par-dessus
        // dès qu'elle est déposée dans les assets, sans rien casser tant
        // qu'elle n'y est pas encore.
        gradient: theme.accentGradient,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Image propre à la slide (choisie dans le studio admin, hébergée
          // sur le serveur) si elle existe, sinon image par défaut de la
          // catégorie packagée dans l'app (une par catégorie), sinon
          // l'ambiance historique, sinon le dégradé du thème.
          if (isNetworkMediaPath(slide.mediaPath))
            Image.network(
              slide.mediaPath!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => category != null
                  ? _categoryBackground(category!, senderGender)
                  : const SizedBox.shrink(),
            )
          else if (category != null)
            _categoryBackground(category!, senderGender),
          // Voile sombre en bas pour garder la légende (et une éventuelle
          // barre d'actions) lisible par-dessus une éventuelle photo chargée.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Colors.black45],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.45, 1],
              ),
            ),
          ),
          if (slide.design != null)
            // Habillage personnalisé depuis le studio admin : position/
            // couleur/police exactement comme dans son aperçu (mêmes
            // coordonnées en pourcentage).
            Align(
              alignment: FractionalOffset(
                slide.design!.textX / 100,
                slide.design!.textY / 100,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24 * scale),
                child: Text(
                  slideText,
                  textAlign: TextAlign.left,
                  style:
                      handwrittenFont(
                        slide.design!.fontFamily,
                        color: slide.design!.textColor,
                        fontSize: 20 * scale,
                      ).copyWith(
                        height: 1.4,
                        shadows: const [
                          Shadow(
                            color: Colors.black45,
                            blurRadius: 10,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                ),
              ),
            )
          else ...[
            // Légende par défaut : police manuscrite des battements de cœur,
            // posée EN BAS à gauche comme avant (façon TikTok), taille
            // proportionnelle à la carte, étiquette de catégorie en pastille.
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cardW = constraints.maxWidth;
                  final cardH = constraints.maxHeight;
                  final length = slideText.runes.length;
                  final lengthFactor = length <= 45 ? 1.0 : (length <= 80 ? 0.88 : 0.78);
                  final fontSize = (cardW * 0.08 * lengthFactor).clamp(11.0, 36.0);
                  final leftPadding = cardW * 0.07;
                  // Marge à droite pour la barre d'actions du fil de lecture.
                  final rightPadding = captionRightPadding * scale;
                  // Plancher : garde de la place pour les cœurs de progression
                  // (fixés à bottom: 10), même à faible échelle.
                  final bottomPadding = 28 * scale < 26 ? 26.0 : 28 * scale;
                  final textWidth = cardW - leftPadding - rightPadding;
                  return Padding(
                    padding: EdgeInsets.fromLTRB(leftPadding, 0, rightPadding, bottomPadding),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: SizedBox(
                        width: textWidth,
                        height: cardH * 0.42,
                        child: FittedBox(
                          // Filet de sécurité : ne réduit que si le texte
                          // dépasse vraiment la zone prévue.
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.bottomLeft,
                          child: SizedBox(
                            width: textWidth,
                            child: Text(
                              slideText,
                              textAlign: TextAlign.left,
                              style: handwrittenFont('dancing_script', color: Colors.white, fontSize: fontSize).copyWith(
                                height: 1.2,
                                shadows: const [Shadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 2))],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (categoryLabel != null)
              // À gauche : le prix du poème s'affiche en haut à droite dans le
              // fil de lecture (voir PackFeedScreen).
              Positioned(
                top: 12 * scale,
                left: 12 * scale,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.favorite_rounded, size: 12 * scale, color: Colors.white),
                      SizedBox(width: 4 * scale),
                      Text(categoryLabel, style: handwrittenFont('caveat', color: Colors.white, fontSize: 15 * scale)),
                    ],
                  ),
                ),
              ),
          ],
          if (overlay != null) overlay!,
        ],
      ),
    );
  }
}
