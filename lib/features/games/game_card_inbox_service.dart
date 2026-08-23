import 'package:flutter/foundation.dart';

import '../../models/send.dart';
import 'game_service.dart';

/// Envois de jeu reçus pas encore traités — cartes-questions
/// (répondues/relancées/rejetées) ET stories en émojis (devinées/jugées) —
/// alimente la bulle de notification globale unique (voir AppShell). Mis à
/// jour soit par un rafraîchissement explicite, soit en direct par un
/// événement temps réel (voir DashboardTab._onRealtimeEvent).
class GameCardInboxService extends ChangeNotifier {
  GameCardInboxService._();
  static final GameCardInboxService instance = GameCardInboxService._();

  List<Send> _pending = [];
  List<Send> get pending => _pending;

  /// Affiche la dernière liste connue tout de suite (voir
  /// GameService.cachedCardInbox), avant même la réponse réseau — pour que
  /// la bulle (voir GameCardBubble) puisse apparaître dès le lancement de
  /// l'app plutôt que de rester invisible le temps du premier fetch.
  Future<void> refresh() async {
    if (_pending.isEmpty) {
      final cached = await GameService.instance.cachedCardInbox();
      if (cached != null && _pending.isEmpty) {
        _pending = cached;
        notifyListeners();
      }
    }
    try {
      _pending = await GameService.instance.fetchCardInbox();
      notifyListeners();
    } catch (_) {
      // Best effort — la bulle garde simplement son dernier état connu.
    }
  }

  void addPending(Send send) {
    if (_pending.any((s) => s.id == send.id)) return;
    _pending = [send, ..._pending];
    notifyListeners();
  }

  void removePending(String sendId) {
    if (!_pending.any((s) => s.id == sendId)) return;
    _pending = _pending.where((s) => s.id != sendId).toList();
    notifyListeners();
  }
}
