import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/push_notification_service.dart';
import '../l10n/locale_scope.dart';
import '../theme/theme_palette.dart';
import '../theme/theme_scope.dart';

/// Sollicitation "douce" avant la vraie demande système — inspirée des
/// écrans "Turn on Notifications" désormais courants (icône + bénéfices +
/// gros bouton dégradé), plutôt que de laisser l'OS demander à froid sans
/// contexte dès le premier lancement. N'apparaît qu'une seule fois, tant
/// que la permission n'a encore jamais été tranchée (voir
/// [PushNotificationService.currentAuthorizationStatus] — appelé UNIQUEMENT
/// dans ce cas précis par [AppRouter.routeAfterAuth], jamais si déjà
/// accordée/refusée) : au-delà, c'est la carte de rappel des Paramètres
/// (voir NotificationPermissionCard) qui prend le relai, en permanence tant
/// que la permission reste refusée.
Future<void> showNotificationOptInPrompt(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (context) => const _NotificationOptInDialog(),
  );
}

class _NotificationOptInDialog extends StatefulWidget {
  const _NotificationOptInDialog();

  @override
  State<_NotificationOptInDialog> createState() => _NotificationOptInDialogState();
}

class _NotificationOptInDialogState extends State<_NotificationOptInDialog> {
  bool _requesting = false;

  Future<void> _activate() async {
    setState(() => _requesting = true);
    // C'est cet appel qui déclenche la vraie demande système (une seule
    // fois par installation, ensuite silencieuse) — voir
    // PushNotificationService.init.
    await PushNotificationService.instance.init();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 30, offset: const Offset(0, 14)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: theme.accentGradient),
                  child: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 34),
                ),
                const SizedBox(height: 20),
                Text(
                  t('notif_dialog_title'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(fontSize: 19, fontWeight: FontWeight.w800, color: theme.textOnBackground),
                ),
                const SizedBox(height: 6),
                Text(
                  t('notif_dialog_subtitle'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _Benefit(emoji: '💌', label: t('notif_dialog_benefit_dates'), theme: theme),
                    _Benefit(emoji: '💓', label: t('notif_dialog_benefit_heartbeats'), theme: theme),
                    _Benefit(emoji: '🎁', label: t('notif_dialog_benefit_gifts'), theme: theme),
                  ],
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: _requesting ? null : _activate,
                      child: Ink(
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: theme.accentGradient,
                          boxShadow: [
                            BoxShadow(color: theme.primary.withValues(alpha: 0.5), blurRadius: 20, offset: const Offset(0, 8)),
                          ],
                        ),
                        child: Center(
                          child: _requesting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                )
                              : Text(
                                  t('common_enable'),
                                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _requesting ? null : () => Navigator.of(context).pop(),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.4))),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  final String emoji;
  final String label;
  final ThemePalette theme;

  const _Benefit({required this.emoji, required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 26)),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w600, color: theme.textOnBackgroundMuted),
        ),
      ],
    );
  }
}
