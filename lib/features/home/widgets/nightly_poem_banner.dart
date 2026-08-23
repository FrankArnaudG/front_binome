import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/box.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/app_card.dart';

/// Bannière "Poème de la nuit" calculée côté client (heure actuelle vs
/// l'heure du rituel du soir de la Box, et si un envoi a déjà eu lieu
/// aujourd'hui) — pas de notification push cette passe.
class NightlyPoemBanner extends StatelessWidget {
  final Box? box;
  final bool hasSentToday;
  final VoidCallback onTap;

  const NightlyPoemBanner({super.key, required this.box, required this.hasSentToday, required this.onTap});

  bool get _shouldShow {
    final currentBox = box;
    if (currentBox == null || !currentBox.eveningRitualEnabled || hasSentToday) return false;

    final parts = currentBox.eveningRitualTime.split(':');
    if (parts.length < 2) return false;

    final ritualHour = int.tryParse(parts[0]);
    final ritualMinute = int.tryParse(parts[1]);
    if (ritualHour == null || ritualMinute == null) return false;

    final now = TimeOfDay.now();
    return now.hour > ritualHour || (now.hour == ritualHour && now.minute >= ritualMinute);
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldShow) return const SizedBox.shrink();

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          const Icon(Icons.nightlight_round, color: AppColors.secondary, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "C'est l'heure du poème de la nuit",
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textOnBlush),
                ),
                const SizedBox(height: 2),
                Text(
                  'Envoie un mot doux avant de dormir',
                  style: GoogleFonts.nunito(fontSize: 12, color: AppColors.textOnBlushMuted),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textOnBlushMuted),
        ],
      ),
    );
  }
}
