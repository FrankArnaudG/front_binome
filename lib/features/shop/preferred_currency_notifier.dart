import 'package:flutter/foundation.dart';

import '../../core/local_cache.dart';
import 'currency_service.dart';

/// Devise de la Boutique (singleton `ChangeNotifier`, même esprit que
/// [WalletBalanceNotifier]) — sans lui, un changement fait depuis les
/// Paramètres n'était visible sur la Boutique qu'après un rechargement
/// manuel de l'écran (déjà ouvert avant le changement, donc jamais notifié).
///
/// Mise en cache (voir LocalCache) pour que ShopScreen puisse décider
/// INSTANTANÉMENT, dès le premier frame, s'il faut ou non proposer le choix
/// de devise — sans attendre un aller-retour réseau qui laissait sinon les
/// prix s'afficher un court instant avant que la modale n'apparaisse.
/// [refresh] continue d'interroger le serveur juste après, en silence, pour
/// rattraper un changement fait depuis un autre appareil.
class PreferredCurrencyNotifier extends ChangeNotifier {
  PreferredCurrencyNotifier._();
  static final PreferredCurrencyNotifier instance = PreferredCurrencyNotifier._();

  static const _cacheKey = 'cache_preferred_currency';

  String? _currency;
  String? get currency => _currency;

  void set(String? currency) {
    _currency = currency;
    notifyListeners();
    if (currency != null) LocalCache.instance.writeJson(_cacheKey, currency);
  }

  /// À appeler au démarrage de l'app (voir main.dart) pour que [currency]
  /// soit déjà renseigné avant même que ShopScreen ne monte.
  Future<void> loadCached() async {
    final cached = await LocalCache.instance.readJson<String>(_cacheKey);
    if (cached != null) {
      _currency = cached;
      notifyListeners();
    }
  }

  Future<String?> refresh() async {
    final value = await CurrencyService.instance.fetchPreferredCurrency();
    set(value);
    return value;
  }
}
