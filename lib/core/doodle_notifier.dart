import 'dart:async';

import 'package:flutter/foundation.dart';

import '../features/box/box_service.dart';
import '../features/doodle/doodle_service.dart';
import '../models/doodle.dart';
import 'realtime_client.dart';

/// Doodle envoyé au binôme (voir demande utilisateur) — reste à l'écoute du
/// canal temps réel de la Box EN PERMANENCE, même esprit que
/// GameInviteNotifier, mais plus simple : pas de "réponse" à attendre côté
/// auteur, un doodle reçu s'affiche directement en plein écran chez le/la
/// destinataire (voir demande utilisateur : "s'affiche en plein écran chez
/// l'autre", pas une petite bulle).
class DoodleNotifier extends ChangeNotifier {
  DoodleNotifier._();
  static final DoodleNotifier instance = DoodleNotifier._();

  String? _myUserId;
  String? _subscribedBoxId;
  Timer? _pollTimer;
  String? _lastShownDoodleId;

  Doodle? _pendingDoodle;
  Doodle? get pendingDoodle => _pendingDoodle;

  void init(String myUserId) {
    _myUserId = myUserId;
    BoxService.instance.removeListener(_onBoxChanged);
    BoxService.instance.addListener(_onBoxChanged);
    _onBoxChanged();

    // Poll de secours (indépendant du socket, même principe que
    // GameInviteNotifier) — sans ça, un événement WebSocket manqué ne
    // ferait jamais apparaître le doodle avant de relancer l'app entière.
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _pollPending());
  }

  Future<void> _pollPending() async {
    if (_subscribedBoxId == null) return;
    try {
      final doodle = await DoodleService.instance.fetchPendingDoodle();
      if (doodle != null && doodle.toUserId == _myUserId) {
        _show(doodle);
      }
    } catch (_) {
      // Best-effort.
    }
  }

  void _onBoxChanged() {
    final box = BoxService.instance.currentBox;
    final boxId = box?.partnerId != null ? box!.id : null;
    if (boxId == _subscribedBoxId) return;

    final previousBoxId = _subscribedBoxId;
    if (previousBoxId != null) {
      RealtimeClient.instance.unsubscribeFromBox(previousBoxId, onEvent: _onEvent);
    }
    _subscribedBoxId = boxId;
    if (boxId != null) {
      RealtimeClient.instance.subscribeToBox(boxId, onEvent: _onEvent);
    }
  }

  void _onEvent(RealtimeEvent event) {
    if (event.event != 'DoodleSent') return;
    final data = event.data;
    if (data == null) return;
    final doodle = Doodle.fromJson(data['doodle'] as Map<String, dynamic>);
    if (doodle.toUserId != _myUserId) return;
    _show(doodle);
  }

  void _show(Doodle doodle) {
    if (doodle.id == _lastShownDoodleId) return;
    _lastShownDoodleId = doodle.id;
    _pendingDoodle = doodle;
    notifyListeners();
  }

  /// Reprend un doodle par son id — voir PushNotificationService, utilisé
  /// quand le tap vient d'une notification reçue app fermée/en arrière-plan.
  Future<void> showDoodleById(String doodleId) async {
    try {
      final doodle = await DoodleService.instance.fetchPendingDoodle();
      if (doodle != null && doodle.id == doodleId && doodle.toUserId == _myUserId) {
        _show(doodle);
      }
    } catch (_) {
      // Best-effort.
    }
  }

  /// Efface le doodle affiché — appelé une fois DoodleViewScreen fermé.
  void dismissPendingDoodle() {
    _pendingDoodle = null;
    notifyListeners();
  }
}
