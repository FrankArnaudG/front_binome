import 'package:flutter/material.dart';

import '../../core/app_router.dart';
import '../../core/delivery_ack_service.dart';
import '../../core/doodle_notifier.dart';
import '../../l10n/locale_scope.dart';
import '../../widgets/nav_bars/classic_nav_bar.dart';
import '../../widgets/nav_bars/nav_item.dart';
import '../box/box_scope.dart';
import '../content/unread_timeline_service.dart';
import '../games/nearby_billing_tracker.dart';
import '../shop/subscription_status_notifier.dart';
import '../shop/wallet_balance_notifier.dart';
import 'tab_navigation_controller.dart';
import 'widgets/doodle_overlay.dart';
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
    if (state == AppLifecycleState.resumed) {
      DeliveryAckService.instance.onAppResumed();
      // Voir demande utilisateur : si un dessin est arrivé pendant que
      // l'app n'était pas au premier plan, il doit s'afficher tout de
      // suite au retour, sans attendre le prochain tick du poll de secours
      // (jusqu'à 10s, voir DoodleNotifier).
      DoodleNotifier.instance.pollNow();
      // Un paiement LigdiCash se termine dans le navigateur externe, hors
      // de l'app — au retour (résumé), le solde de pièces/l'abonnement
      // peuvent avoir changé sans qu'aucun écran n'ait rien demandé. On
      // rafraîchit ici, au niveau global, plutôt que dans ShopScreen/
      // SubscriptionScreen uniquement, pour couvrir aussi le cas où
      // l'utilisateur revient sur un tout autre écran de l'app.
      WalletBalanceNotifier.instance.refresh();
      SubscriptionStatusNotifier.instance.refresh();
      // Jours de jeu "présentiel connecté" en attente (voir
      // NearbyBillingTracker) — tente une déclaration à chaque retour au
      // premier plan, moment naturel où une connexion vient probablement
      // de revenir.
      final boxId = BoxScope.of(context).currentBox?.id;
      if (boxId != null) NearbyBillingTracker.instance.reportAndClear(boxId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppRouter.showGlobalNavBar,
      builder: (context, show, _) {
        if (!show) {
          // Voir demande utilisateur : le pop-up d'invitation à une partie
          // doit apparaître même par-dessus un écran qui masque la barre de
          // nav (tous les écrans de jeu, voir *BoardScreen.initState) — un
          // simple Stack ici, PAS un second Scaffold, pour ne rien changer
          // au comportement (resizeToAvoidBottomInset, etc.) de l'écran
          // qu'il recouvre.
          return Stack(
            children: [
              widget.child,
              const GameInviteOverlay(),
            ],
          );
        }

        final t = LocaleScope.of(context).t;

        return AnimatedBuilder(
          animation: Listenable.merge([TabNavigationController.instance, UnreadTimelineService.instance]),
          builder: (context, _) {
            final items = [
              // Duo en premier (page d'accueil, voir
              // TabNavigationController) — voir demande utilisateur.
              NavItem(outlinedIcon: Icons.favorite_outline, filledIcon: Icons.favorite_rounded, label: t('nav_duo')),
              NavItem(
                outlinedIcon: Icons.auto_awesome_outlined,
                filledIcon: Icons.auto_awesome_rounded,
                label: t('nav_gallery'),
                badgeCount: UnreadTimelineService.instance.count,
              ),
              NavItem(outlinedIcon: Icons.sports_esports_outlined, filledIcon: Icons.sports_esports_rounded, label: t('nav_games')),
              NavItem(outlinedIcon: Icons.person_outline_rounded, filledIcon: Icons.person_rounded, label: t('nav_profile')),
            ];
            return Scaffold(
              body: Stack(
                children: [
                  widget.child,
                  const GameInviteOverlay(),
                  const DoodleOverlay(),
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
