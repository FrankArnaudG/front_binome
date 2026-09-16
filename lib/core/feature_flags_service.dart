import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// État des fonctionnalités (activées/désactivées depuis le panel admin —
/// voir FeatureFlagController côté backend), même esprit que
/// WalletBalanceNotifier : singleton `ChangeNotifier`, rafraîchi au chargement
/// du Dashboard. Une fonctionnalité inconnue ou en cas d'échec réseau est
/// considérée activée par défaut, pour ne jamais bloquer l'app sur un souci
/// de connexion.
class FeatureFlagsService extends ChangeNotifier {
  FeatureFlagsService._();
  static final FeatureFlagsService instance = FeatureFlagsService._();

  Map<String, bool> _flags = {};
  bool _loaded = false;

  bool isEnabled(String key) => _flags[key] ?? true;

  // Tant que le tout premier refresh() n'est pas terminé, isEnabled()
  // retombe sur `true` par défaut pour toute fonctionnalité — un écran
  // affiché avant cette réponse réseau (voir DashboardTab.initState, appel
  // non attendu) montrerait donc brièvement une tuile désactivée avant
  // qu'elle disparaisse au prochain rebuild (voir demande utilisateur :
  // "meme celle desactiver apparessent quelque seconde avant de
  // disparetre"). Les écrans qui veulent éviter ce flash peuvent donc
  // masquer leurs tuiles conditionnelles tant que `!isLoaded`, plutôt que
  // de les afficher de façon optimiste.
  bool get isLoaded => _loaded;

  Future<void> refresh() async {
    try {
      final data = await ApiClient.instance.get('/feature-flags') as Map<String, dynamic>;
      _flags = data.map((key, value) => MapEntry(key, value as bool));
    } catch (_) {
      // Best effort — on garde le dernier état connu plutôt que de bloquer l'app.
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }
}
