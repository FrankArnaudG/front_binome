import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/local_cache.dart';

/// Solde de tokens du couple courant (singleton `ChangeNotifier`, même
/// esprit que BoxService) : mis à jour immédiatement après un achat/envoi
/// sans devoir refetch tout l'écran qui l'affiche.
///
/// Le solde est aussi mis en cache (voir LocalCache) pour s'afficher
/// instantanément au lancement de l'app, hors-ligne y compris — mais dès
/// qu'une connexion existe, [refresh] interroge TOUJOURS le serveur en
/// priorité (jamais la valeur en cache) : un solde de tokens n'a pas le
/// droit d'être périmé silencieusement comme un simple flux de lecture.
///
/// Note : l'endpoint GET /wallet n'existe côté backend qu'à partir de la
/// Phase 3 (Boutique) — `refresh()` échoue silencieusement en attendant,
/// le badge affiche simplement 0.
class WalletBalanceNotifier extends ChangeNotifier {
  WalletBalanceNotifier._();
  static final WalletBalanceNotifier instance = WalletBalanceNotifier._();

  static const _cacheKey = 'cache_wallet_balance';

  // Décimal désormais (voir migration convert_coin_balances_to_decimal
  // côté backend et demande utilisateur : facturation proportionnelle du
  // temps de jeu, "on stocke vraiment des pièces fractionnées").
  double _balance = 0;
  double get balance => _balance;

  void set(num balance) {
    _balance = balance.toDouble();
    notifyListeners();
    LocalCache.instance.writeJson(_cacheKey, _balance);
  }

  /// Dernier solde connu (voir LocalCache), sans appel réseau — à appeler au
  /// démarrage pour peindre le badge instantanément, avant même que
  /// [refresh] ait eu le temps de joindre le serveur.
  Future<void> loadCached() async {
    final cached = await LocalCache.instance.readJson<num>(_cacheKey);
    if (cached != null) {
      _balance = cached.toDouble();
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    try {
      final data = await ApiClient.instance.get('/wallet') as Map<String, dynamic>;
      set(parseBalance(data['balance']));
    } catch (_) {
      // Hors-ligne ou endpoint indisponible : on garde la dernière valeur
      // connue (déjà chargée depuis le cache ou la session en cours)
      // plutôt que de faire planter l'écran appelant.
    }
  }

  /// Le backend sérialise `balance` en STRING (voir cast `decimal:3` côté
  /// Laravel, ex. `"45.626"`) plutôt qu'en nombre JSON brut — pratique
  /// courante pour une valeur financière, ça évite toute imprécision côté
  /// client aussi. Accepte quand même un nombre brut par robustesse (ex.
  /// GameWalletTicked, qui diffuse un vrai float PHP).
  static double parseBalance(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  /// Affichage compact — la plupart des mouvements restent des nombres
  /// entiers (achats boutique, cadeaux...), seule la facturation du temps
  /// de jeu introduit des fractions (voir demande utilisateur) : jamais
  /// "51.0", seulement "51" quand c'est un compte rond, sinon 2 décimales.
  static String format(double balance) {
    if (balance == balance.roundToDouble()) return balance.toStringAsFixed(0);
    return balance.toStringAsFixed(2);
  }
}
