import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'realtime_client.dart';
import 'token_storage.dart';

/// État du mode maintenance, tenu à jour depuis `GET /maintenance-status`
/// (interrogé au démarrage) et via le canal temps réel public `maintenance`
/// (diffusé par l'admin à chaque activation/désactivation/prolongation, voir
/// MaintenanceUpdated côté backend) — voir demande utilisateur : "quand ils
/// se connectent doivent voir un message pour les mettre en attente" et "ces
/// comptes [autorisés] doivent voir une bande les informant que la
/// maintenance est activée".
///
/// Ne bloque jamais le démarrage de l'app en cas d'échec réseau (comme
/// AppUpdateChecker) : une maintenance non détectée n'est pas grave, un
/// démarrage bloqué le serait.
class MaintenanceService extends ChangeNotifier {
  MaintenanceService._();
  static final MaintenanceService instance = MaintenanceService._();

  static const _channel = 'maintenance';

  bool isActive = false;
  String? message;
  DateTime? endsAt;
  bool allowed = false;
  bool _hasToken = false;
  bool _started = false;
  Timer? _pollTimer;

  /// Compte bloqué : maintenance active, session identifiée (un jeton
  /// existe) et ce compte n'est pas sur la liste des comptes toujours
  /// autorisés. SANS jeton (pas encore connecté), on ne bloque jamais — sinon
  /// un compte autorisé ne pourrait même plus atteindre l'écran de connexion
  /// pour prouver qui il est (voir /maintenance-status, `allowed` vaut
  /// toujours faux pour une requête anonyme).
  bool get isBlocked => isActive && _hasToken && !allowed;

  /// Compte autorisé pendant une maintenance active : pas bloqué, mais doit
  /// voir la bande d'information (voir demande utilisateur).
  bool get showBanner => isActive && allowed;

  /// Démarré une seule fois depuis AppShell (voir ApiClient.onSessionRevoked,
  /// même principe) : premier statut + abonnement au canal public.
  void start() {
    if (_started) return;
    _started = true;
    refresh();
    RealtimeClient.instance.subscribePublic(_channel, onEvent: _onRealtimeEvent);
  }

  void stop() {
    if (!_started) return;
    _started = false;
    RealtimeClient.instance.unsubscribePublic(_channel, onEvent: _onRealtimeEvent);
    _stopPolling();
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.event != 'MaintenanceUpdated') return;
    refresh();
  }

  Future<void> refresh() async {
    try {
      _hasToken = await TokenStorage.instance.readToken() != null;
      final data = await ApiClient.instance.get('/maintenance-status') as Map<String, dynamic>;
      isActive = data['is_active'] == true;
      message = data['message'] as String?;
      final endsAtRaw = data['ends_at'] as String?;
      endsAt = endsAtRaw == null ? null : DateTime.tryParse(endsAtRaw);
      allowed = data['allowed'] == true;
      notifyListeners();
      // Filet de sécurité : si is_active tarde à redevenir faux côté app
      // (événement temps réel manqué — voir incident du 29/09/2026, une
      // désactivation faite hors du bouton admin n'avait pas diffusé
      // MaintenanceUpdated), on revérifie régulièrement tant que actif,
      // plutôt que de rester bloqué indéfiniment en attendant cet
      // événement (même principe que SuspensionService).
      isActive ? _startPolling() : _stopPolling();
    } catch (_) {
      // Jamais bloquant (voir AppUpdateChecker) : un souci réseau ici ne
      // doit pas empêcher l'app de démarrer normalement.
    }
  }

  void _startPolling() {
    _pollTimer ??= Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Branché sur ApiClient (voir onSessionRevoked, même principe pour le
  /// 401) : un 503 en cours d'utilisation signale une maintenance qui vient
  /// de démarrer — on ne veut pas attendre le prochain événement temps réel
  /// pour l'afficher, donc on revérifie tout de suite le statut complet
  /// (le corps d'un 503 ne contient que le message d'erreur, pas
  /// is_active/allowed/ends_at, voir EnsureNotInMaintenance).
  void onBlockedResponse() {
    refresh();
  }
}
