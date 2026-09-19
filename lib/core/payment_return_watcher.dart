import 'dart:async';

import 'package:flutter/material.dart';

import '../features/shop/subscription_status_notifier.dart';
import '../features/shop/wallet_balance_notifier.dart';
import '../l10n/locale_controller.dart';
import 'app_router.dart';

/// Confirme dans l'app un paiement YengaPay fait dans le navigateur externe.
///
/// Le paiement se termine hors de l'app (voir ShopScreen/SubscriptionScreen,
/// `launchUrl` en mode externe) puis la page de retour du site rouvre l'app
/// (voir binomecouple.com/paiement/succes.html). Le solde n'est mis à jour que
/// par le webhook YengaPay côté serveur, qui peut arriver quelques secondes
/// APRÈS le retour dans l'app : on relit donc le solde et l'abonnement à
/// quelques secondes d'intervalle, et on affiche un message dès qu'un
/// changement apparaît — plutôt que de laisser croire que rien ne s'est passé.
///
/// N'affirme jamais qu'un paiement a réussi sans preuve : le message ne
/// s'affiche que si le solde a réellement augmenté ou si l'abonnement vient de
/// devenir actif.
class PaymentReturnWatcher {
  PaymentReturnWatcher._();
  static final PaymentReturnWatcher instance = PaymentReturnWatcher._();

  static const _maxAge = Duration(minutes: 30);
  static const _checkDelays = [Duration.zero, Duration(seconds: 3), Duration(seconds: 8), Duration(seconds: 15)];

  DateTime? _armedAt;
  double _balanceAtStart = 0;
  bool _subscribedAtStart = false;
  bool _checking = false;

  /// À appeler juste après avoir ouvert la page de paiement.
  void arm() {
    _armedAt = DateTime.now();
    _balanceAtStart = WalletBalanceNotifier.instance.balance;
    _subscribedAtStart = SubscriptionStatusNotifier.instance.isActive;
  }

  /// À appeler à chaque retour au premier plan de l'app (voir AppShell).
  Future<void> onResumed() async {
    final armedAt = _armedAt;
    if (armedAt == null || _checking) return;
    if (DateTime.now().difference(armedAt) > _maxAge) {
      _armedAt = null;
      return;
    }

    _checking = true;
    try {
      for (final delay in _checkDelays) {
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        await Future.wait([
          WalletBalanceNotifier.instance.refresh(),
          SubscriptionStatusNotifier.instance.refresh(),
        ]);
        if (_hasChanged()) {
          _armedAt = null;
          _showConfirmation();
          return;
        }
      }
      // Rien de nouveau après ~26 s : on n'affirme rien. Le webhook peut
      // encore arriver, le solde se mettra à jour tout seul au prochain
      // rafraîchissement.
    } finally {
      _checking = false;
    }
  }

  bool _hasChanged() {
    final balanceIncreased = WalletBalanceNotifier.instance.balance > _balanceAtStart + 0.0005;
    final subscriptionStarted = !_subscribedAtStart && SubscriptionStatusNotifier.instance.isActive;
    return balanceIncreased || subscriptionStarted;
  }

  void _showConfirmation() {
    final context = AppRouter.navigatorKey.currentContext;
    if (context == null) return;
    final message = LocaleController.instance.t('payment_confirmed');
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}
