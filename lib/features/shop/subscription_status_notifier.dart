import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/local_cache.dart';
import '../../core/realtime_client.dart';
import '../../models/subscription.dart';
import 'subscription_service.dart';

/// Statut d'abonnement du user courant (singleton `ChangeNotifier`, même
/// esprit que [WalletBalanceNotifier]) : tout écran qui gate une action sur
/// le solde de tokens doit aussi consulter [isActive] avant d'afficher un
/// blocage "solde insuffisant" — un·e abonné·e a un accès illimité et
/// gratuit tant que son abonnement est actif (voir User::hasActiveSubscription
/// côté backend).
///
/// [expiresAt] est aussi mis en cache (voir LocalCache) pour que [isActive]
/// réponde correctement dès le tout premier frame — sans ça, un badge basé
/// dessus (voir CoinBalanceBadge) affichait d'abord le solde de tokens
/// normal (le temps que [refresh] joigne le serveur) avant de basculer sur
/// "∞", un flash visible constaté en réel (voir demande utilisateur : "ca
/// apparait toujour, je remarque que... les piece... apparait avant de
/// disparetre et l'infini apparait").
class SubscriptionStatusNotifier extends ChangeNotifier {
  SubscriptionStatusNotifier._();
  static final SubscriptionStatusNotifier instance = SubscriptionStatusNotifier._();

  static const _cacheKey = 'cache_subscription_expires_at';

  String? _myUserId;

  Subscription? _subscription;
  Subscription? get subscription => _subscription;

  bool get isActive => _subscription != null && _subscription!.expiresAt.isAfter(DateTime.now());

  DateTime? get expiresAt => _subscription?.expiresAt;

  /// Dernier statut connu (voir LocalCache), sans appel réseau — à appeler
  /// au démarrage pour que [isActive] réponde correctement dès le tout
  /// premier frame, avant même que [refresh] ait eu le temps de joindre le
  /// serveur (voir main.dart, même principe que WalletBalanceNotifier.loadCached).
  Future<void> loadCached() async {
    final cachedIso = await LocalCache.instance.readJson<String>(_cacheKey);
    if (cachedIso == null) return;
    final expiresAt = DateTime.tryParse(cachedIso);
    if (expiresAt == null) return;
    // Reconstruction minimale : seuls isActive/expiresAt sont consultés par
    // qui que ce soit avant le vrai refresh (ni id ni plan ne sont utilisés
    // hors de SubscriptionScreen, qui attend toujours refresh() de toute
    // façon avant de s'afficher).
    _subscription = Subscription(id: '', startedAt: expiresAt, expiresAt: expiresAt);
    notifyListeners();
  }

  /// Voir demande utilisateur : "es ce connecter au reverbe pour le temp
  /// reel?" — à appeler une fois l'utilisateur connu (voir AppRouter.
  /// routeAfterAuth, même principe que GameInviteNotifier.init), pour une
  /// mise à jour instantanée (paiement confirmé OU ajustement admin,
  /// voir SubscriptionUpdated côté back) sans attendre la réouverture de
  /// l'écran Abonnement.
  void init(String myUserId) {
    if (_myUserId == myUserId) return;
    _myUserId = myUserId;
    RealtimeClient.instance.subscribePrivate('App.Models.User.$myUserId', onEvent: _onEvent);
  }

  void _onEvent(RealtimeEvent event) {
    if (event.event != 'SubscriptionUpdated') return;
    unawaited(refresh());
  }

  Future<void> refresh() async {
    try {
      final subscription = await SubscriptionService.instance.fetchMySubscription();
      _subscription = subscription;
      notifyListeners();
      LocalCache.instance.writeJson(_cacheKey, subscription?.expiresAt.toIso8601String());
    } catch (_) {
      // Hors-ligne ou endpoint indisponible : on garde le dernier statut
      // connu plutôt que de faire planter l'écran appelant.
    }
  }
}
