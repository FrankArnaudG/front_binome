import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'local_cache.dart';

/// État des fonctionnalités (activées/désactivées depuis le panel admin —
/// voir FeatureFlagController côté backend), même esprit que
/// WalletBalanceNotifier : singleton `ChangeNotifier`, rafraîchi au chargement
/// du Dashboard. Une fonctionnalité inconnue est considérée activée par
/// défaut, pour ne jamais bloquer l'app sur un souci de connexion.
///
/// Voir demande utilisateur : un démarrage à froid SANS connexion ne doit
/// pas réactiver par erreur ce qui a été désactivé depuis l'admin — avant ce
/// correctif, `_flags` repartait vide à chaque lancement (jamais persisté),
/// et un premier refresh() en échec laissait `isEnabled()` répondre `true`
/// pour tout. Le dernier état connu est donc mis en cache disque (voir
/// LocalCache), relu avant même le premier appel réseau de la session.
class FeatureFlagsService extends ChangeNotifier {
  FeatureFlagsService._();
  static final FeatureFlagsService instance = FeatureFlagsService._();

  static const _cacheKey = 'cache_feature_flags';

  Map<String, bool> _flags = {};
  bool _loaded = false;
  bool _cacheChecked = false;

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
    // Lu une seule fois par session, AVANT le tout premier appel réseau —
    // jamais après, pour ne jamais écraser un état réseau plus frais par
    // une valeur de cache potentiellement périmée.
    if (!_cacheChecked) {
      _cacheChecked = true;
      final cached = await LocalCache.instance.readJson<Map<String, dynamic>>(_cacheKey);
      if (cached != null) {
        _flags = cached.map((key, value) => MapEntry(key, value as bool));
      }
    }

    try {
      final data = await ApiClient.instance.get('/feature-flags') as Map<String, dynamic>;
      _flags = data.map((key, value) => MapEntry(key, value as bool));
      unawaited(LocalCache.instance.writeJson(_cacheKey, _flags));
    } catch (_) {
      // Best effort — on garde le dernier état connu (ce refresh raté, ou à
      // défaut le cache disque lu ci-dessus) plutôt que de bloquer l'app.
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }
}
