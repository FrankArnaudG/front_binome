import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../models/box.dart';
import '../../../theme/theme_scope.dart';

/// Action rapide la plus visible du Dashboard : "Envoyer un poème-slide"
/// ouvre directement la bibliothèque de slides — mise en avant par
/// rapport aux autres actions (secondaires, en grille) pour guider
/// l'usage quotidien.
///
/// Bascule AUTOMATIQUEMENT (en vrai temps réel, voir
/// [_scheduleNightlySwitch]) vers un texte/icône "rituel du soir" une
/// fois l'heure configurée passée, plutôt que d'afficher une bannière
/// séparée juste en dessous menant au même endroit (voir demande
/// utilisateur : "ça évite d'avoir deux bandes ayant le même chemin au
/// même moment" — remplace l'ancien DarkNightlyPoemBanner).
class SendThoughtCta extends StatefulWidget {
  final VoidCallback onTap;
  // Non-null uniquement quand on veut activer la bascule "rituel du
  // soir" (voir DashboardTab) — `null` garde le texte générique tout le
  // temps.
  final Box? box;
  final bool hasSentToday;

  const SendThoughtCta({super.key, required this.onTap, this.box, this.hasSentToday = false});

  @override
  State<SendThoughtCta> createState() => _SendThoughtCtaState();
}

class _SendThoughtCtaState extends State<SendThoughtCta> {
  Timer? _nightlySwitchTimer;

  @override
  void initState() {
    super.initState();
    _scheduleNightlySwitch();
  }

  @override
  void didUpdateWidget(SendThoughtCta oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.box?.eveningRitualTime != widget.box?.eveningRitualTime ||
        oldWidget.box?.eveningRitualEnabled != widget.box?.eveningRitualEnabled) {
      _scheduleNightlySwitch();
    }
  }

  @override
  void dispose() {
    _nightlySwitchTimer?.cancel();
    super.dispose();
  }

  bool get _isNightly {
    final box = widget.box;
    if (box == null || !box.eveningRitualEnabled || widget.hasSentToday) return false;

    final parts = box.eveningRitualTime.split(':');
    if (parts.length < 2) return false;
    final ritualHour = int.tryParse(parts[0]);
    final ritualMinute = int.tryParse(parts[1]);
    if (ritualHour == null || ritualMinute == null) return false;

    final now = TimeOfDay.now();
    return now.hour > ritualHour || (now.hour == ritualHour && now.minute >= ritualMinute);
  }

  /// Minuteur programmé À HEURE FIXE (pas un Timer.periodic, même
  /// principe que DarkQuickActionsGrid._scheduleEmojiRefresh) pour
  /// basculer l'affichage pile à l'heure du rituel du soir, sans
  /// attendre qu'un autre événement (envoi, retour sur l'écran...)
  /// déclenche un rebuild — voir demande utilisateur : "automatiquement
  /// en temps réel".
  void _scheduleNightlySwitch() {
    _nightlySwitchTimer?.cancel();
    final box = widget.box;
    if (box == null || !box.eveningRitualEnabled || _isNightly) return;

    final parts = box.eveningRitualTime.split(':');
    if (parts.length < 2) return;
    final ritualHour = int.tryParse(parts[0]);
    final ritualMinute = int.tryParse(parts[1]);
    if (ritualHour == null || ritualMinute == null) return;

    final now = DateTime.now();
    final target = DateTime(now.year, now.month, now.day, ritualHour, ritualMinute);
    if (!target.isAfter(now)) return; // déjà passé aujourd'hui — _isNightly l'aurait déjà détecté ci-dessus.

    _nightlySwitchTimer = Timer(target.difference(now), () {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;
    final nightly = _isNightly;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
          decoration: BoxDecoration(
            gradient: theme.accentGradient,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [BoxShadow(color: theme.primary.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
                child: Icon(nightly ? Icons.nightlight_round : Icons.auto_stories_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t(nightly ? 'nightly_title' : 'cta_send_thought'),
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t(nightly ? 'nightly_subtitle' : 'cta_send_thought_hint'),
                      style: GoogleFonts.nunito(fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
