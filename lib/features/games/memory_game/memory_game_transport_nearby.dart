import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nearby_connections/nearby_connections.dart';

import '../../../models/memory_game_session.dart';
import 'memory_emoji_pool.dart';
import 'memory_game_engine.dart';
import 'memory_game_transport.dart';

/// Identifiants internes des deux rôles — Nearby Connections n'a pas de
/// notion de compte, seulement un lien pair-à-pair établi en avance (voir
/// memory_game_nearby_connect_screen.dart). Traduits vers les vrais
/// identifiants du couple uniquement à l'enregistrement du résultat final
/// (voir toPairsByUserId), que seul l'HÔTE poste (voir le plan).
const kNearbyHostRole = 'host';
const kNearbyGuestRole = 'guest';

/// Mode "présentiel connecté" — l'HÔTE est autoritaire : lui seul génère
/// le plateau et applique MemoryGameEngine, l'invité ne fait que proposer
/// des flips et recevoir l'état à jour. Aucun appel backend pendant la
/// partie (voir MemoryGameController, jamais utilisé ici).
class NearbyMemoryGameTransport extends MemoryGameTransport {
  final Nearby nearby;
  final String endpointId;
  final bool isHost;
  final _controller = StreamController<MemoryGameBoardState>.broadcast();
  late MemoryGameBoardState _state;

  /// Côté hôte : génère et envoie le plateau à l'invité tout de suite.
  NearbyMemoryGameTransport.host({
    required this.nearby,
    required this.endpointId,
    required int pairCount,
  }) : isHost = true {
    _state = MemoryGameBoardState(
      board: generateShuffledMemoryBoard(pairCount),
      currentTurnUserId: kNearbyHostRole,
      startedAt: DateTime.now(),
      myUserId: kNearbyHostRole,
    );
    _sendInit();
  }

  /// Côté invité : plateau vide tant que le message `init` de l'hôte n'est
  /// pas arrivé (voir onPayloadReceived) — l'écran de plateau doit afficher
  /// un chargement tant que `currentState.board` est vide.
  NearbyMemoryGameTransport.guest({
    required this.nearby,
    required this.endpointId,
  }) : isHost = false {
    _state = const MemoryGameBoardState(board: [], myUserId: kNearbyGuestRole);
  }

  void _send(Map<String, dynamic> message) {
    nearby.sendBytesPayload(endpointId, Uint8List.fromList(utf8.encode(jsonEncode(message))));
  }

  void _sendInit() {
    _send({
      'type': 'init',
      'pairCount': _state.board.length ~/ 2,
      'board': _state.board,
      'startedAt': _state.startedAt?.toIso8601String(),
    });
  }

  void _sendState() {
    _send({
      'type': 'state',
      'matched': _state.matched.map((p) => {'indices': p.indices, 'user_id': p.userId}).toList(),
      'flipped': _state.flipped,
      'mismatch': _state.mismatch,
      'currentTurnUserId': _state.currentTurnUserId,
      'movesCount': _state.movesCount,
      'movesByUser': _state.movesByUser,
      'finished': _state.finished,
      'startedAt': _state.startedAt?.toIso8601String(),
      'pausedByUserId': _state.pausedByUserId,
      'pausedAt': _state.pausedAt?.toIso8601String(),
    });
  }

  /// À brancher sur `Nearby().acceptConnection(endpointId,
  /// onPayLoadRecieved: transport.onPayloadReceived)` juste après que la
  /// connexion soit établie (voir memory_game_nearby_connect_screen.dart).
  void onPayloadReceived(String fromEndpointId, Payload payload) {
    if (payload.type != PayloadType.BYTES || payload.bytes == null) return;

    final message = jsonDecode(utf8.decode(payload.bytes!)) as Map<String, dynamic>;
    switch (message['type']) {
      case 'init':
        // Reçu côté invité uniquement.
        final board = (message['board'] as List).map((e) => e as String).toList();
        _state = MemoryGameBoardState(
          board: board,
          currentTurnUserId: kNearbyHostRole,
          startedAt: message['startedAt'] != null ? DateTime.parse(message['startedAt'] as String) : DateTime.now(),
          myUserId: kNearbyGuestRole,
        );
        _controller.add(_state);
      case 'state':
        // Reçu côté invité (l'hôte fait autorité) — l'hôte n'a normalement
        // jamais besoin de recevoir ce message de lui-même, mais l'ignorer
        // simplement s'il arrivait serait sans risque.
        final matched = (message['matched'] as List)
            .map((e) => MemoryGameMatchedPair.fromJson(e as Map<String, dynamic>))
            .toList();
        final mismatchRaw = message['mismatch'] as List?;
        final pausedByUserId = message['pausedByUserId'] as String?;
        _state = _state.copyWith(
          matched: matched,
          flipped: (message['flipped'] as List).map((e) => e as int).toList(),
          mismatch: mismatchRaw?.map((e) => e as int).toList(),
          clearMismatch: mismatchRaw == null,
          currentTurnUserId: message['currentTurnUserId'] as String?,
          movesCount: message['movesCount'] as int,
          movesByUser: (message['movesByUser'] as Map).map((k, v) => MapEntry(k as String, v as int)),
          finished: message['finished'] as bool,
          startedAt: message['startedAt'] != null ? DateTime.parse(message['startedAt'] as String) : _state.startedAt,
          pausedByUserId: pausedByUserId,
          pausedAt: message['pausedAt'] != null ? DateTime.parse(message['pausedAt'] as String) : null,
          clearPause: pausedByUserId == null,
        );
        _controller.add(_state);
      case 'flip':
        // Reçu côté hôte uniquement — l'invité demande un flip, l'hôte
        // l'arbitre et redistribue le nouvel état (voir flip() ci-dessous,
        // même chemin que pour ses propres flips).
        if (isHost) _applyHostFlip(message['index'] as int, kNearbyGuestRole);
      case 'pause_request':
        // Reçu côté hôte uniquement — n'importe lequel des deux peut
        // demander la pause (voir pause() ci-dessous), l'hôte arbitre et
        // redistribue (même principe que flip, voir demande utilisateur).
        if (isHost) _applyHostPause(kNearbyGuestRole);
      case 'resume_request':
        // Reçu côté hôte uniquement — réservé à qui a posé la pause, voir
        // _applyHostResume qui vérifie le rôle avant d'agir.
        if (isHost) _applyHostResume(kNearbyGuestRole);
    }
  }

  void _applyHostPause(String byRole) {
    if (_state.isPaused || _state.finished) return;
    _state = _state.copyWith(pausedByUserId: byRole, pausedAt: DateTime.now());
    _controller.add(_state);
    _sendState();
  }

  void _applyHostResume(String byRole) {
    // Réservé à qui a posé la pause (voir demande utilisateur) — un appel
    // par l'autre rôle est silencieusement ignoré, même principe que le
    // 403 côté backend pour le mode à distance.
    if (!_state.isPaused || _state.pausedByUserId != byRole) return;
    final paused = _state.pausedAt;
    if (paused != null && _state.startedAt != null) {
      _state = _state.copyWith(startedAt: _state.startedAt!.add(DateTime.now().difference(paused)));
    }
    _state = _state.copyWith(clearPause: true);
    _controller.add(_state);
    _sendState();
  }

  void _applyHostFlip(int index, String byRole) {
    if (_state.finished || _state.isPaused) return;
    final result = MemoryGameEngine.flip(
      board: _state.board,
      matched: _state.matched,
      flipped: _state.flipped,
      currentTurnUserId: _state.currentTurnUserId ?? kNearbyHostRole,
      movesCount: _state.movesCount,
      movesByUser: _state.movesByUser,
      index: index,
      userId: byRole,
      otherUserId: byRole == kNearbyHostRole ? kNearbyGuestRole : kNearbyHostRole,
    );
    _state = _state.copyWith(
      matched: result.matched,
      flipped: result.flipped,
      mismatch: result.mismatch,
      clearMismatch: result.mismatch == null,
      currentTurnUserId: result.currentTurnUserId,
      movesCount: result.movesCount,
      movesByUser: result.movesByUser,
      finished: result.finished,
    );
    _controller.add(_state);
    _sendState();
  }

  @override
  Stream<MemoryGameBoardState> get stateStream => _controller.stream;

  @override
  MemoryGameBoardState get currentState => _state;

  @override
  Future<void> flip(int index) async {
    if (isHost) {
      _applyHostFlip(index, kNearbyHostRole);
    } else {
      _send({'type': 'flip', 'index': index});
    }
  }

  @override
  Future<void> abandon() async {
    _state = _state.copyWith(finished: true);
    _controller.add(_state);
    if (isHost) _sendState();
  }

  @override
  Future<void> pause() async {
    if (isHost) {
      _applyHostPause(kNearbyHostRole);
    } else {
      _send({'type': 'pause_request'});
    }
  }

  @override
  Future<void> resume() async {
    // L'UI ne propose de toute façon jamais ce bouton à qui n'a pas posé
    // la pause (voir MemoryGameBoardState.pausedByMe) — ce garde-fou
    // couvre juste le cas défensif d'un appel direct.
    if (!_state.pausedByMe) return;
    if (isHost) {
      _applyHostResume(kNearbyHostRole);
    } else {
      _send({'type': 'resume_request'});
    }
  }

  /// Traduit `matched` (rôles internes host/guest) vers les vrais
  /// identifiants du couple pour GameService.recordMemoryGameResult — voir
  /// la doc de classe, seul l'hôte poste ce résultat.
  Map<String, int> pairsByUserId({required String hostUserId, required String guestUserId}) {
    final counts = <String, int>{};
    for (final pair in _state.matched) {
      final realId = pair.userId == kNearbyHostRole ? hostUserId : guestUserId;
      counts[realId] = (counts[realId] ?? 0) + 1;
    }
    return counts;
  }

  @override
  void dispose() {
    _controller.close();
  }
}
