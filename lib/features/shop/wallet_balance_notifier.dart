import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/local_cache.dart';

/// Solde de pièces du couple courant (singleton `ChangeNotifier`, même
/// esprit que BoxService) : mis à jour immédiatement après un achat/envoi
/// sans devoir refetch tout l'écran qui l'affiche.
///
/// Le solde est aussi mis en cache (voir LocalCache) pour s'afficher
/// instantanément au lancement de l'app, hors-ligne y compris — mais dès
/// qu'une connexion existe, [refresh] interroge TOUJOURS le serveur en
/// priorité (jamais la valeur en cache) : un solde de pièces n'a pas le
/// droit d'être périmé silencieusement comme un simple flux de lecture.
///
/// Note : l'endpoint GET /wallet n'existe côté backend qu'à partir de la
/// Phase 3 (Boutique) — `refresh()` échoue silencieusement en attendant,
/// le badge affiche simplement 0.
class WalletBalanceNotifier extends ChangeNotifier {
  WalletBalanceNotifier._();
  static final WalletBalanceNotifier instance = WalletBalanceNotifier._();

  static const _cacheKey = 'cache_wallet_balance';

  int _balance = 0;
  int get balance => _balance;

  void set(int balance) {
    _balance = balance;
    notifyListeners();
    LocalCache.instance.writeJson(_cacheKey, balance);
  }

  /// Dernier solde connu (voir LocalCache), sans appel réseau — à appeler au
  /// démarrage pour peindre le badge instantanément, avant même que
  /// [refresh] ait eu le temps de joindre le serveur.
  Future<void> loadCached() async {
    final cached = await LocalCache.instance.readJson<int>(_cacheKey);
    if (cached != null) {
      _balance = cached;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    try {
      final data = await ApiClient.instance.get('/wallet') as Map<String, dynamic>;
      set(data['balance'] as int? ?? 0);
    } catch (_) {
      // Hors-ligne ou endpoint indisponible : on garde la dernière valeur
      // connue (déjà chargée depuis le cache ou la session en cours)
      // plutôt que de faire planter l'écran appelant.
    }
  }
}
