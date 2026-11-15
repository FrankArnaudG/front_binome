import 'package:flutter/material.dart';

import '../../../core/app_router.dart';
import '../../../l10n/locale_scope.dart';
import '../../../theme/theme_scope.dart';
import '../../auth/auth_service.dart';
import '../../box/box_service.dart';

/// Bande persistante affichée dès que le/la binôme a quitté la Box (voir
/// demande utilisateur : "une bande disant que mon/ma binôme s'est retiré
/// de la Box... un btn recréer une nouvelle box... je dois pouvoir
/// continuer à naviguer tant que je ne clique pas sur le btn"). Non
/// fermable — reste visible tant qu'aucune nouvelle Box n'a été créée ou
/// rejointe (voir BoxService._apply, qui efface `partnerLeftSnapshot` dans
/// ce cas). Se met à jour SEULE, sans refresh manuel : BoxService écoute
/// déjà l'événement temps réel BoxDissolved sur le canal de la Box (voir
/// BoxService._onRealtimeBoxEvent) et notifie ce widget via `ListenableBuilder`.
class PartnerLeftBanner extends StatefulWidget {
  const PartnerLeftBanner({super.key});

  @override
  State<PartnerLeftBanner> createState() => _PartnerLeftBannerState();
}

class _PartnerLeftBannerState extends State<PartnerLeftBanner> {
  bool _recreating = false;

  // Charge l'AppUser courant au moment du tap plutôt que de le faire
  // transiter depuis AppShell (qui ne connaît pas l'utilisateur connecté) —
  // AuthService.cachedUserIfLoggedIn() est déjà la source utilisée au
  // démarrage (voir SplashScreen), donc toujours disponible ici.
  Future<void> _recreateBox() async {
    setState(() => _recreating = true);
    try {
      final user = await AuthService.instance.cachedUserIfLoggedIn();
      // PartnerLeftBanner est monté DANS AppShell, au même niveau que
      // ClassicNavBar — donc AU-DESSUS du Navigator fourni par
      // MaterialApp.builder (voir AppRouter.navigatorKey : "nécessaire
      // pour naviguer... depuis un contexte situé au-dessus du Navigator,
      // où Navigator.of(context) ne trouve rien"). `context` ici échouerait
      // silencieusement ; on utilise le même contournement que
      // ClassicNavBar/_handlePushPermission.
      final navContext = AppRouter.navigatorKey.currentContext;
      if (user == null || navContext == null || !navContext.mounted) return;
      AppRouter.toBoxChoice(navContext, user, replace: true);
    } finally {
      if (mounted) setState(() => _recreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BoxService.instance,
      builder: (context, _) {
        final snapshot = BoxService.instance.partnerLeftSnapshot;
        if (snapshot == null) return const SizedBox.shrink();

        final t = LocaleScope.of(context).t;
        final theme = ThemeScope.paletteOf(context);
        final partner = BoxService.instance.partnerWhoLeft;
        final message = t(partner?.gender == 'Femme' ? 'partner_left_banner_f' : 'partner_left_banner_m');

        return Material(
          color: theme.primary,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.heart_broken_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _recreating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : TextButton(
                          onPressed: _recreateBox,
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: theme.primary,
                            minimumSize: const Size(0, 30),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: Text(
                            t('partner_left_banner_cta'),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
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
}
