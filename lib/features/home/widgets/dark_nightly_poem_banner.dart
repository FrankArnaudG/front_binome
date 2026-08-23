import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../models/box.dart';
import '../../../theme/theme_scope.dart';

/// Bannière "Poème de la nuit" — suit le thème personnel choisi (voir
/// [ThemeScope]), utilisée uniquement par [DashboardTab].
class DarkNightlyPoemBanner extends StatelessWidget {
  final Box? box;
  final bool hasSentToday;
  final VoidCallback onTap;

  const DarkNightlyPoemBanner({super.key, required this.box, required this.hasSentToday, required this.onTap});

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
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return Material(
      color: theme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: (theme.isDark ? Colors.white : Colors.black).withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Icon(Icons.nightlight_round, color: theme.secondary, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('nightly_title'),
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: theme.textOnBackground),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t('nightly_subtitle'),
                      style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.textOnBackgroundMuted),
            ],
          ),
        ),
      ),
    );
  }
}
