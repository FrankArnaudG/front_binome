import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Puce colorée pour un statut (commande pending/paid/failed/cancelled,
/// déblocage de pack, etc.) — la couleur est fournie par l'appelant, qui
/// connaît la sémantique de son propre statut.
class StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const StatusChip({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
