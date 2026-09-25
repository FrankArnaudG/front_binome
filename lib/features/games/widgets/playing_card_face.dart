import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Widget de carte partagé entre "Bataille" (War Card) et "Bataille de
/// couleurs" (Suit Battle) — voir demande utilisateur : les deux jeux de
/// cartes doivent avoir le même rendu de carte. Extrait de l'ancien
/// `_PlayingCardFace` de War Card (indices en coin + disposition réelle
/// des pips), avec en plus la gestion du Joker (absent de "Bataille" mais
/// présent dans "Bataille de couleurs").

const Color kPlayingCardRedColor = Color(0xFFE5484D);
const Color kPlayingCardJokerColor = Color(0xFF7C4DFF);

String suitSymbolFor(String suit) => switch (suit) {
      'S' => '♠',
      'H' => '♥',
      'D' => '♦',
      'C' => '♣',
      _ => '',
    };

class _PipSpot {
  final double dx;
  final double dy;
  final bool rotated;

  const _PipSpot(this.dx, this.dy, {this.rotated = false});
}

/// Disposition RÉELLE des pips par rang — mise en page classique d'un jeu
/// de 52 cartes françaises/anglaises. Les rangs non listés ('A', 'J', 'Q',
/// 'K') n'ont pas de champ de pips (voir [PlayingCardFace] : as = un seul
/// gros pip central, figures = lettre).
const Map<String, List<_PipSpot>> _kPipLayouts = {
  '2': [_PipSpot(0, -0.75), _PipSpot(0, 0.75, rotated: true)],
  '3': [_PipSpot(0, -0.75), _PipSpot(0, 0), _PipSpot(0, 0.75, rotated: true)],
  '4': [
    _PipSpot(-0.6, -0.75),
    _PipSpot(0.6, -0.75),
    _PipSpot(-0.6, 0.75, rotated: true),
    _PipSpot(0.6, 0.75, rotated: true),
  ],
  '5': [
    _PipSpot(-0.6, -0.85),
    _PipSpot(0.6, -0.85),
    _PipSpot(0, 0),
    _PipSpot(-0.6, 0.85, rotated: true),
    _PipSpot(0.6, 0.85, rotated: true),
  ],
  '6': [
    _PipSpot(-0.6, -0.85),
    _PipSpot(0.6, -0.85),
    _PipSpot(-0.6, 0),
    _PipSpot(0.6, 0),
    _PipSpot(-0.6, 0.85, rotated: true),
    _PipSpot(0.6, 0.85, rotated: true),
  ],
  '7': [
    _PipSpot(-0.6, -0.9),
    _PipSpot(0.6, -0.9),
    _PipSpot(0, -0.45),
    _PipSpot(-0.6, 0),
    _PipSpot(0.6, 0),
    _PipSpot(-0.6, 0.9, rotated: true),
    _PipSpot(0.6, 0.9, rotated: true),
  ],
  '8': [
    _PipSpot(-0.6, -0.9),
    _PipSpot(0.6, -0.9),
    _PipSpot(0, -0.45),
    _PipSpot(-0.6, 0),
    _PipSpot(0.6, 0),
    _PipSpot(0, 0.45, rotated: true),
    _PipSpot(-0.6, 0.9, rotated: true),
    _PipSpot(0.6, 0.9, rotated: true),
  ],
  '9': [
    _PipSpot(-0.6, -0.9),
    _PipSpot(0.6, -0.9),
    _PipSpot(-0.6, -0.42),
    _PipSpot(0.6, -0.42),
    _PipSpot(0, 0),
    _PipSpot(-0.6, 0.42, rotated: true),
    _PipSpot(0.6, 0.42, rotated: true),
    _PipSpot(-0.6, 0.9, rotated: true),
    _PipSpot(0.6, 0.9, rotated: true),
  ],
  '10': [
    _PipSpot(-0.6, -0.9),
    _PipSpot(0.6, -0.9),
    _PipSpot(-0.6, -0.42),
    _PipSpot(0.6, -0.42),
    _PipSpot(0, -0.65),
    _PipSpot(0, 0.65, rotated: true),
    _PipSpot(-0.6, 0.42, rotated: true),
    _PipSpot(0.6, 0.42, rotated: true),
    _PipSpot(-0.6, 0.9, rotated: true),
    _PipSpot(0.6, 0.9, rotated: true),
  ],
};

/// Le visage complet d'une carte — indices en coin (haut-gauche, et
/// bas-droit retourné à 180°, comme sur une vraie carte) + champ central
/// fidèle au rang : un pip pour l'as, la disposition réelle pour 2 à 10
/// (voir [_kPipLayouts]), une lettre pour les figures (J/Q/K — un vrai
/// portrait illustré serait hors de portée à cette taille, la lettre + les
/// indices en coin restent la convention standard pour identifier la
/// figure sans ambiguïté). [isJoker] bascule sur un visage dédié (absent
/// de "Bataille", présent dans "Bataille de couleurs").
class PlayingCardFace extends StatelessWidget {
  final String card;
  final bool isJoker;
  final double width;
  final double height;
  // Teinte de bordure optionnelle (ex: couleur du joueur) — sans elle, la
  // bordure reprend la couleur du texte/pips (rouge/noir, ou violet pour
  // un Joker).
  final Color? color;
  final Color? borderColor;
  final double borderWidth;
  final double borderRadius;

  const PlayingCardFace({
    super.key,
    required this.card,
    this.isJoker = false,
    required this.width,
    required this.height,
    this.color,
    this.borderColor,
    this.borderWidth = 2,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    if (isJoker) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: borderColor ?? color ?? kPlayingCardJokerColor.withValues(alpha: 0.5), width: borderWidth),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, color: kPlayingCardJokerColor, size: width * 0.34),
            Text(
              'JOKER',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: width * 0.14, color: kPlayingCardJokerColor),
            ),
          ],
        ),
      );
    }

    final rank = card.substring(0, card.length - 1);
    final suit = card.substring(card.length - 1);
    final suitSymbol = suitSymbolFor(suit);
    final isRedSuit = suit == 'H' || suit == 'D';
    final pipColor = isRedSuit ? kPlayingCardRedColor : Colors.black87;
    final cornerFontSize = width * 0.15;
    // Pips plus petits pour les rangs à 4 rangées (9/10) qui ont le moins
    // de marge verticale disponible, sinon les motifs se chevauchent.
    final denseRank = rank == '9' || rank == '10';
    final pipFontSize = width * (denseRank ? 0.09 : 0.105);
    // Boîte réservée à CHAQUE pip (voir centerField) — en la dimensionnant
    // explicitement, deux pips proches ne peuvent jamais se chevaucher
    // visuellement, contrairement à un Align nu sur du texte "brut" dont
    // la boîte suit le glyphe et peut déborder sur sa voisine.
    final pipBoxSize = pipFontSize * 1.15;

    Widget corner({required bool flipped}) {
      final child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rank, style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: cornerFontSize, color: pipColor, height: 1)),
          Text(suitSymbol, style: TextStyle(fontSize: cornerFontSize * 0.8, color: pipColor, height: 1)),
        ],
      );
      return flipped ? Transform.rotate(angle: 3.14159, child: child) : child;
    }

    Widget centerField() {
      if (rank == 'A') {
        return Center(child: Text(suitSymbol, style: TextStyle(fontSize: width * 0.4, color: pipColor)));
      }
      if (rank == 'J' || rank == 'Q' || rank == 'K') {
        return Center(
          child: Text(rank, style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: width * 0.38, color: pipColor)),
        );
      }
      final layout = _kPipLayouts[rank];
      if (layout == null) return const SizedBox.shrink();

      return Stack(
        children: [
          for (final spot in layout)
            Align(
              alignment: Alignment(spot.dx, spot.dy),
              child: SizedBox(
                width: pipBoxSize,
                height: pipBoxSize,
                child: Center(
                  child: Transform.rotate(
                    angle: spot.rotated ? 3.14159 : 0,
                    child: Text(
                      suitSymbol,
                      style: TextStyle(fontSize: pipFontSize, color: pipColor, height: 1, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.all(width * 0.07),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor ?? color?.withValues(alpha: 0.5) ?? pipColor.withValues(alpha: 0.5), width: borderWidth),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: Stack(
        children: [
          Positioned(top: 0, left: 0, child: corner(flipped: false)),
          Positioned(bottom: 0, right: 0, child: corner(flipped: true)),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: width * 0.26, vertical: height * 0.13),
              child: centerField(),
            ),
          ),
        ],
      ),
    );
  }
}
