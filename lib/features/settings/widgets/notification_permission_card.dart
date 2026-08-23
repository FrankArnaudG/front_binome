import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/notification_permission_nudge.dart';
import '../../../l10n/locale_scope.dart';
import '../../../theme/theme_scope.dart';
import '../../../widgets/themed_card.dart';

/// Accès permanent à l'activation des notifications, dans les Réglages —
/// pas de croix pour la fermer, reste affichée en continu tant que la
/// permission est refusée, disparaît uniquement une fois accordée (voir
/// demande utilisateur : remplace l'ancienne bannière temporaire du
/// Dashboard, plafonnée et fermable, retirée pour ne garder que celle-ci).
class NotificationPermissionCard extends StatefulWidget {
  const NotificationPermissionCard({super.key});

  @override
  State<NotificationPermissionCard> createState() => _NotificationPermissionCardState();
}

class _NotificationPermissionCardState extends State<NotificationPermissionCard>
    with WidgetsBindingObserver {
  bool _denied = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour depuis les réglages système : la carte doit disparaître dès
    // que la permission est accordée, sans attendre une réouverture de
    // l'écran des Réglages.
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final denied = await NotificationPermissionNudge.instance.isPermissionDenied();
    if (mounted) {
      setState(() {
        _denied = denied;
        _checked = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked || !_denied) return const SizedBox.shrink();
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return ThemedCard(
      child: Row(
        children: [
          Icon(Icons.notifications_off_rounded, color: theme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('notif_card_title'),
                  style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: theme.textOnBackground),
                ),
                const SizedBox(height: 2),
                Text(
                  t('notif_card_subtitle'),
                  style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => NotificationPermissionNudge.instance.openSystemSettings(),
            child: Text(t('common_enable')),
          ),
        ],
      ),
    );
  }
}
