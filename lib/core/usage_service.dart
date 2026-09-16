import 'dart:async';

import 'api_client.dart';

/// Instrumentation "temps passé" / "fonctionnalité la plus utilisée" (voir
/// demande utilisateur) — toujours fire-and-forget : un échec réseau ou une
/// session pas encore authentifiée ne doit jamais faire planter ni ralentir
/// l'app, donc chaque appel avale ses propres erreurs.
///
/// Deux mécanismes complémentaires, voir UsageController côté backend :
/// - [logFeature] : une ouverture de fonctionnalité suivie (compteur).
/// - pings périodiques ([startSessionPings]/[stopSessionPings], pilotés par
///   AppShell) : approximation du temps passé, sans notion de fin de
///   session explicite (l'app peut être tuée sans prévenir).
class UsageService {
  UsageService._();
  static final UsageService instance = UsageService._();

  static const _pingInterval = Duration(seconds: 30);

  Timer? _timer;

  void logFeature(String feature, {String? detail}) {
    ApiClient.instance
        .post('/usage/feature-event', body: {'feature': feature, if (detail != null) 'detail': detail})
        .catchError((_) {});
  }

  void pingNow() {
    ApiClient.instance.post('/usage/session-ping').catchError((_) {});
  }

  /// À appeler quand l'app revient au premier plan (voir AppShell) — un
  /// ping immédiat puis un toutes les [_pingInterval] tant qu'elle y reste.
  void startSessionPings() {
    if (_timer != null) return;
    pingNow();
    _timer = Timer.periodic(_pingInterval, (_) => pingNow());
  }

  /// À appeler quand l'app passe en arrière-plan — pas la peine de continuer
  /// à pinguer un serveur pour une app que personne ne regarde.
  void stopSessionPings() {
    _timer?.cancel();
    _timer = null;
  }
}
