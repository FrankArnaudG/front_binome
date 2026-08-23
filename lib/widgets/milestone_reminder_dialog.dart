import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/theme_scope.dart';

/// Rappel de date à cœur affiché DANS l'app à l'ouverture (voir
/// MilestoneReminderService.checkAndNotify côté logique) — canal principal,
/// indépendant de toute permission système : la notification système n'est
/// qu'un bonus optionnel déclenché séparément, jamais une condition pour
/// que ce rappel apparaisse.
Future<void> showMilestoneReminderDialog(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    // Fermable UNIQUEMENT via "Compris" — sans ça, le moindre tap ailleurs
    // à l'écran (barrierDismissible vaut true par défaut) la refermait
    // avant même d'avoir pu la lire (constaté en réel).
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) {
      final theme = ThemeScope.paletteOf(context);
      // Bloque aussi le geste/bouton retour Android — barrierDismissible
      // ne couvre que le tap sur le fond, pas le retour système.
      return PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 30, offset: const Offset(0, 14)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: theme.accentGradient),
                  child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 16),
                Text(
                  'Une date à cœur approche',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: theme.textOnBackground),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(fontSize: 14, color: theme.textOnBackgroundMuted, height: 1.4),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => Navigator.of(context).pop(),
                      child: Ink(
                        height: 48,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), gradient: theme.accentGradient),
                        child: Center(
                          child: Text(
                            'Compris 💕',
                            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
