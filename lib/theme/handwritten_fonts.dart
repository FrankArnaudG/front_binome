import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Police manuscrite/romantique choisie dans le studio admin (voir
/// SlideController::FONTS côté backend) : les clés doivent rester identiques
/// des deux côtés pour garantir la même apparence.
TextStyle handwrittenFont(
  String slug, {
  required Color color,
  required double fontSize,
}) {
  switch (slug) {
    case 'dancing_script':
      return GoogleFonts.dancingScript(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
      );
    case 'caveat':
      return GoogleFonts.caveat(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
      );
    case 'great_vibes':
      return GoogleFonts.greatVibes(color: color, fontSize: fontSize);
    case 'sacramento':
      return GoogleFonts.sacramento(color: color, fontSize: fontSize);
    case 'parisienne':
      return GoogleFonts.parisienne(color: color, fontSize: fontSize);
    case 'playfair_display_italic':
    default:
      return GoogleFonts.playfairDisplay(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        fontStyle: FontStyle.italic,
      );
  }
}
