import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../content/timeline_screen.dart';
import '../games/games_menu_screen.dart';
import '../settings/settings_screen.dart';
import 'dashboard_tab.dart';
import 'tab_navigation_controller.dart';

/// Coquille à 4 onglets (navigation façon WhatsApp) : Dashboard (Cœur),
/// Galerie (Livre), Jeux et Profil. Bascule via [IndexedStack] — aucun
/// rechargement, chaque onglet garde son état. La barre de navigation
/// elle-même n'est plus dessinée ici : elle vit dans `AppShell`, montée
/// globalement, pour rester visible aussi sur les écrans poussés
/// par-dessus (Boutique, Poèmes-Slides...) — voir [TabNavigationController]
/// pour l'état partagé de l'onglet actif.
///
/// [ThemeScope]/[LocaleScope] sont montés globalement dans `main.dart`
/// (autour du Navigator entier, pas juste ici) — donc tous les écrans,
/// onglets comme écrans poussés (Boutique, Poèmes-Slides...), peuvent lire
/// le thème/la langue personnels choisis dans les Paramètres.
class MainTabScreen extends StatefulWidget {
  final AppUser user;

  const MainTabScreen({super.key, required this.user});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  void _goToTab(int index) => TabNavigationController.instance.setIndex(index);

  // Carnet de bord en premier (page d'accueil) — voir demande utilisateur,
  // doit rester synchronisé avec l'ordre des NavItem dans AppShell.
  late final List<Widget> _pages = [
    TimelineScreen(user: widget.user),
    DashboardTab(user: widget.user, onNavigateToTab: _goToTab),
    GamesMenuScreen(user: widget.user),
    SettingsScreen(user: widget.user),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: TabNavigationController.instance,
      builder: (context, _) => IndexedStack(index: TabNavigationController.instance.index, children: _pages),
    );
  }
}
