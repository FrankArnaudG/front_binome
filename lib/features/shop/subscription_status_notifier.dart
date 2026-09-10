import 'package:flutter/foundation.dart';

import '../../models/subscription.dart';
import 'subscription_service.dart';

/// Statut d'abonnement du user courant (singleton `ChangeNotifier`, même
/// esprit que [WalletBalanceNotifier]) : tout écran qui gate une action sur
/// le solde de pièces doit aussi consulter [isActive] avant d'afficher un
/// blocage "solde insuffisant" — un·e abonné·e a un accès illimité et
/// gratuit tant que son abonnement est actif (voir User::hasActiveSubscription
/// côté backend).
class SubscriptionStatusNotifier extends ChangeNotifier {
  SubscriptionStatusNotifier._();
  static final SubscriptionStatusNotifier instance = SubscriptionStatusNotifier._();

  Subscription? _subscription;
  Subscription? get subscription => _subscription;

  bool get isActive => _subscription != null && _subscription!.expiresAt.isAfter(DateTime.now());

  DateTime? get expiresAt => _subscription?.expiresAt;

  Future<void> refresh() async {
    try {
      final subscription = await SubscriptionService.instance.fetchMySubscription();
      _subscription = subscription;
      notifyListeners();
    } catch (_) {
      // Hors-ligne ou endpoint indisponible : on garde le dernier statut
      // connu plutôt que de faire planter l'écran appelant.
    }
  }
}
