import 'package:flutter/material.dart';

import '../../../models/slide.dart';
import '../../../theme/theme_palette.dart';
import 'slide_visual_card.dart';

/// Visionneuse en lecture seule d'un pack déjà envoyé — même swipe
/// horizontal et mêmes points de progression que PackFeedScreen, mais sans
/// aucune action d'envoi (on rouvre un souvenir, on ne le renvoie pas).
class SlidePackViewer extends StatefulWidget {
  final List<Slide> slides;
  final ThemePalette theme;
  final String? category;

  /// Espace autour de chaque carte pendant le swipe — utile en plein écran
  /// (pour ne pas coller les cartes entre elles), mais à mettre à zéro
  /// quand la visionneuse est déjà contenue dans un cadre serré (ex. la
  /// modale de réponse-poème) : sinon le fond derrière la carte apparaît
  /// en bordure et casse le rendu immersif "bord à bord".
  final EdgeInsets slideMargin;

  const SlidePackViewer({
    super.key,
    required this.slides,
    required this.theme,
    this.category,
    this.slideMargin = const EdgeInsets.all(16),
  });

  @override
  State<SlidePackViewer> createState() => _SlidePackViewerState();
}

class _SlidePackViewerState extends State<SlidePackViewer> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PageView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: widget.slides.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (context, i) => Container(
            margin: widget.slideMargin,
            child: SlideVisualCard(
              slide: widget.slides[i],
              theme: widget.theme,
              category: widget.category,
            ),
          ),
        ),
        if (widget.slides.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: IgnorePointer(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.slides.length, (i) {
                  final reached = i <= _index;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Icon(
                      reached
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 12,
                      color: Colors.white.withValues(
                        alpha: reached ? 0.95 : 0.45,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
      ],
    );
  }
}
