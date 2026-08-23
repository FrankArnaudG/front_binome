import 'package:flutter/foundation.dart';

import '../features/content/content_service.dart';
import 'realtime_client.dart';

/// Confirme "reçu" (voir SendDelivered/`Send.status == 'delivered'` côté
/// backend) tout envoi qui m'est destiné, indépendamment de l'écran/onglet
/// actuellement ouvert — contrairement aux abonnements par écran (voir
/// GameBoxHistoryScreen, EmojiStorySessionScreen), celui-ci vit pour toute
/// la session authentifiée (démarré une fois dans AppRouter.routeAfterAuth,
/// jamais désabonné tant qu'on ne se déconnecte pas).
///
/// Volontairement PAS déclenché depuis le gestionnaire de notification push
/// en arrière-plan : Android peut retarder/tuer ce traitement (optimisation
/// batterie), ce qui rendrait le "reçu" invérifiable. À la place, "reçu" se
/// confirme dès que l'app est prouvée connectée au serveur : un SendCreated
/// arrive en direct pendant que l'app tourne, OU un rattrapage en masse
/// (markPendingDelivered) à chaque (re)connexion — ouverture de l'app,
/// retour au premier plan (voir AppShell.didChangeAppLifecycleState), ou
/// abonnement au canal Box.
class DeliveryAckService {
  DeliveryAckService._();
  static final DeliveryAckService instance = DeliveryAckService._();

  String? _boxId;
  String? _userId;

  bool get isStarted => _boxId != null;

  void start(String boxId, String userId) {
    if (_boxId == boxId && _userId == userId) return;
    if (_boxId != null) stop();
    _boxId = boxId;
    _userId = userId;
    RealtimeClient.instance.subscribeToBox(boxId, onEvent: _onEvent);
    _sweep();
  }

  void stop() {
    final boxId = _boxId;
    if (boxId == null) return;
    RealtimeClient.instance.unsubscribeFromBox(boxId, onEvent: _onEvent);
    _boxId = null;
    _userId = null;
  }

  /// À rappeler quand l'app revient au premier plan (voir AppShell) — le
  /// socket a pu être coupé pendant que l'app était en arrière-plan, ce
  /// rattrapage garantit que "reçu" reste correct même si l'event temps réel
  /// en direct a été manqué.
  void onAppResumed() {
    if (_boxId != null) _sweep();
  }

  void _onEvent(RealtimeEvent event) {
    if (event.event != 'SendCreated') return;
    final sendJson = event.data?['send'] as Map<String, dynamic>?;
    if (sendJson == null) return;
    if (sendJson['recipient_id'] != _userId || sendJson['status'] != 'sent') return;
    final sendId = sendJson['id'] as String?;
    if (sendId == null) return;
    _markDelivered(sendId);
  }

  Future<void> _markDelivered(String sendId) async {
    try {
      await ContentService.instance.markDelivered(sendId);
    } catch (_) {
      // best effort — le prochain rattrapage (markPendingDelivered) le
      // reprendra de toute façon.
    }
  }

  Future<void> _sweep() async {
    try {
      await ContentService.instance.markPendingDelivered();
    } catch (e) {
      debugPrint('DeliveryAckService: rattrapage échoué ($e)');
    }
  }
}
