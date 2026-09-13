import 'package:flutter/foundation.dart';

/// État partagé de l'onglet actif du Dashboard/Galerie/Jeux/Profil — vit en
/// dehors de [MainTabScreen] pour que la barre de navigation globale
/// (voir [AppShell]) puisse afficher/faire changer l'onglet actif même
/// quand un écran secondaire (Boutique, Poèmes-Slides...) est poussé
/// par-dessus les 4 onglets.
class TabNavigationController extends ChangeNotifier {
  TabNavigationController._();
  static final TabNavigationController instance = TabNavigationController._();

  // Duo — premier onglet (voir AppShell/MainTabScreen), page
  // d'accueil au lancement/à la connexion (voir demande utilisateur).
  int _index = 0;
  int get index => _index;

  void setIndex(int index) {
    if (_index == index) return;
    _index = index;
    notifyListeners();
  }

  /// Remet l'onglet actif à Duo (0) — appelé à chaque
  /// connexion/déconnexion (voir AppRouter.toLogin/toHome) : sans ça, ce
  /// singleton garde l'onglet où on se trouvait avant de se déconnecter
  /// (ex. Profil), et on atterrit dessus après une reconnexion, même sur
  /// un compte différent.
  void reset() {
    if (_index == 0) return;
    _index = 0;
    notifyListeners();
  }
}
