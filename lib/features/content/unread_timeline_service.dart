import 'package:flutter/foundation.dart';

import 'content_service.dart';

/// Nombre d'envois reçus jamais ouverts (voir Send.isSeen) — alimente la
/// pastille sur l'onglet "Carnet de bord" (voir ClassicNavBar/AppShell).
/// Se limite à la première page du Carnet de bord (voir
/// ContentService.fetchSends) : au-delà de ça, un compte exact n'apporte
/// rien de plus qu'un badge "20+" pour un usage de couple à faible volume.
class UnreadTimelineService extends ChangeNotifier {
  UnreadTimelineService._();
  static final UnreadTimelineService instance = UnreadTimelineService._();

  int _count = 0;
  int get count => _count;

  Future<void> refresh(String currentUserId) async {
    try {
      final sends = await ContentService.instance.fetchSends();
      _count = sends.where((s) => s.recipientId == currentUserId && !s.isSeen).length;
      notifyListeners();
    } catch (_) {
      // Best effort — la pastille garde simplement son dernier état connu.
    }
  }

  /// Décompte immédiat au moment où un envoi est ouvert (voir
  /// TimelineScreen._openSend) — évite d'attendre un aller-retour réseau
  /// pour que la pastille se mette à jour à l'instant du tap.
  void decrement() {
    if (_count == 0) return;
    _count -= 1;
    notifyListeners();
  }

  /// Incrément immédiat sur réception temps réel (voir
  /// DashboardTab._onRealtimeEvent) — la pastille doit refléter un nouvel
  /// envoi dès son arrivée, sans attendre le prochain refresh.
  void increment() {
    _count += 1;
    notifyListeners();
  }
}
