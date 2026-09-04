import 'package:flutter/material.dart';

import '../../core/app_router.dart';
import '../../core/delivery_ack_service.dart';
import '../../l10n/locale_scope.dart';
import '../../widgets/nav_bars/classic_nav_bar.dart';
import '../../widgets/nav_bars/nav_item.dart';
import '../content/unread_timeline_service.dart';
import 'tab_navigation_controller.dart';
import 'widgets/game_card_bubble.dart';
import 'widgets/game_invite_overlay.dart';

/// Coquille globale qui superpose la barre de navigation classique à
/// n'importe quel écran poussé après l'authentification — pas seulement
/// les 4 onglets (Dashboard/Galerie/Jeux/Profil), mais aussi tout ce qui
/// s'ouvre depuis là (Boutique, Poèmes-Slides, Cadeaux, Coffre...). Reste
/// masquée pendant l'accueil/le jumelage/la connexion (voir
/// [AppRouter.showGlobalNavBar]).
///
/// Monté dans `main.dart` autour du Navigator entier (comme
/// BoxScope/ThemeScope/LocaleScope) : un tap sur la barre doit pouvoir
/// ramener à [MainTabScreen] depuis n'importe quel écran poussé, donc elle
/// ne peut pas vivre à l'intérieur d'un seul écran.
class AppShell extends StatefulWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) DeliveryAckService.instance.onAppResumed();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppRouter.showGlobalNavBar,
      builder: (context, show, _) {
        if (!show) return widget.child;

        final t = LocaleScope.of(context).t;

        return AnimatedBuilder(
          animation: Listenable.merge([TabNavigationController.instance, UnreadTimelineService.instance]),
          builder: (context, _) {
            final items = [
              // Carnet de bord en premier (page d'accueil, voir
              // TabNavigationController) — voir demande utilisateur.
              NavItem(
                outlinedIcon: Icons.auto_awesome_outlined,
                filledIcon: Icons.auto_awesome_rounded,
                label: t('nav_gallery'),
                badgeCount: UnreadTimelineService.instance.count,
              ),
              NavItem(outlinedIcon: Icons.favorite_outline, filledIcon: Icons.favorite_rounded, label: t('nav_duo')),
              NavItem(outlinedIcon: Icons.sports_esports_outlined, filledIcon: Icons.sports_esports_rounded, label: t('nav_games')),
              NavItem(outlinedIcon: Icons.person_outline_rounded, filledIcon: Icons.person_rounded, label: t('nav_profile')),
            ];
            return Scaffold(
              body: Stack(
                children: [
                  widget.child,
                  const GameCardBubble(),
                  const GameInviteOverlay(),
                ],
              ),
              bottomNavigationBar: ClassicNavBar(
                currentIndex: TabNavigationController.instance.index,
                items: items,
                onTap: (index) {
                  TabNavigationController.instance.setIndex(index);
                  // Revient à MainTabScreen si un écran secondaire (Boutique,
                  // Poèmes-Slides...) était ouvert par-dessus.
                  AppRouter.navigatorKey.currentState?.popUntil((route) => route.isFirst);
                },
              ),
            );
          },
        );
      },
    );
  }
}
