import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'token_storage.dart';

/// État de sanction "trop de requêtes" d'un compte (voir demande
/// utilisateur : détection des comptes qui "sollicitent trop le serveur" —
/// blocage automatique 24h/72h/indéfini, voir RateLimitStrike côté
/// backend). Purement réactif : un 423 sur N'IMPORTE QUEL appel déclenche
/// [onBlockedResponse] (voir ApiClient.onRateLimitSuspended, même principe
/// que MaintenanceService/onMaintenanceBlocked pour le 503) — une fois
/// bloqué, on interroge `/suspension-status` toutes les 60s pour savoir
/// dès que la sanction se lève, sans que le compte n'ait besoin de
/// relancer l'app.
class SuspensionService extends ChangeNotifier {
  SuspensionService._();
  static final SuspensionService instance = SuspensionService._();

  bool isSuspended = false;
  Timer? _pollTimer;

  void start() {
    ApiClient.onRateLimitSuspended = onBlockedResponse;
    refresh();
  }

  void stop() {
    if (ApiClient.onRateLimitSuspended == onBlockedResponse) ApiClient.onRateLimitSuspended = null;
    _stopPolling();
  }

  Future<void> refresh() async {
    final hasToken = await TokenStorage.instance.readToken() != null;
    if (!hasToken) {
      _stopPolling();
      if (isSuspended) {
        isSuspended = false;
        notifyListeners();
      }
      return;
    }

    try {
      final data = await ApiClient.instance.get('/suspension-status') as Map<String, dynamic>;
      final suspended = data['suspended'] == true;
      if (suspended != isSuspended) {
        isSuspended = suspended;
        notifyListeners();
      }
      suspended ? _startPolling() : _stopPolling();
    } catch (_) {
      // Jamais bloquant : un souci réseau ici ne doit pas empêcher l'app
      // de démarrer/continuer normalement.
    }
  }

  /// Branché sur ApiClient (voir onSessionRevoked/onMaintenanceBlocked,
  /// même principe pour le 401/503) : un 423 signale une sanction qui
  /// vient de démarrer — pas besoin d'attendre le prochain poll.
  void onBlockedResponse() {
    if (!isSuspended) {
      isSuspended = true;
      notifyListeners();
    }
    _startPolling();
  }

  void _startPolling() {
    _pollTimer ??= Timer.periodic(const Duration(seconds: 60), (_) => refresh());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}
