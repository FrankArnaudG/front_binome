import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nearby_connections/nearby_connections.dart';

import 'number_hunt_engine.dart';
import 'number_hunt_transport.dart';
import '../../../core/server_clock.dart';

/// Identifiants internes des deux rôles — voir kNearbyHostRole/
/// kNearbyGuestRole dans memory_game_transport_nearby.dart, même principe
/// (Nearby Connections n'a pas de notion de compte).
const kNumberHuntHostRole = 'host';
const kNumberHuntGuestRole = 'guest';

/// Mode "présentiel connecté" — l'HÔTE est autoritaire : lui seul applique
/// NumberHuntEngine, l'invité ne fait que proposer des tentatives et
/// recevoir l'état à jour. PAS de tour par tour : l'hôte reçoit les
/// tentatives des DEUX côtés (les siennes en direct, celles de l'invité
/// via message) et les traite dans l'ordre d'ARRIVÉE — l'ordre naturel des
/// messages P2P fait déjà foi, pas besoin d'un arbitrage de course
/// supplémentaire comme côté serveur à distance (une seule autorité ici,
/// jamais deux écritures concurrentes). Copie structurelle conforme de
/// NearbyTicTacToeTransport.
class NearbyNumberHuntTransport extends NumberHuntTransport {
  final Nearby nearby;
  final String endpointId;
  final bool isHost;
  final _controller = StreamController<NumberHuntBoardState>.broadcast();
  late NumberHuntBoardState _state;

  /// Côté hôte : démarre la partie et l'envoie tout de suite à l'invité.
  NearbyNumberHuntTransport.host({
    required this.nearby,
    required this.endpointId,
    required int cellCount,
  }) : isHost = true {
    final initial = NumberHuntEngine.generateInitialState(cellCount: cellCount);
    _state = NumberHuntBoardState(
      board: initial.board,
      currentTarget: initial.currentTarget,
      scoresByUser: {kNumberHuntHostRole: 0, kNumberHuntGuestRole: 0},
      startedAt: ServerClock.instance.now(),
      myUserId: kNumberHuntHostRole,
    );
    _sendInit();
  }

  /// Côté invité : état par défaut tant que le message `init` de l'hôte
  /// n'est pas arrivé.
  NearbyNumberHuntTransport.guest({
    required this.nearby,
    required this.endpointId,
  }) : isHost = false {
    _state = const NumberHuntBoardState(myUserId: kNumberHuntGuestRole);
  }

  void _send(Map<String, dynamic> message) {
    nearby.sendBytesPayload(endpointId, Uint8List.fromList(utf8.encode(jsonEncode(message))));
  }

  void _sendInit() {
    _send({
      'type': 'init',
      'board': _state.board,
      'currentTarget': _state.currentTarget,
      'startedAt': _state.startedAt?.toIso8601String(),
    });
  }

  void _sendState() {
    _send({
      'type': 'state',
      'board': _state.board,
      'found': _state.found,
      'currentTarget': _state.currentTarget,
      'scoresByUser': _state.scoresByUser,
      'winnerUserId': _state.winnerUserId,
      'isTie': _state.isTie,
      'movesCount': _state.movesCount,
      'finished': _state.finished,
      'startedAt': _state.startedAt?.toIso8601String(),
      'pausedByUserId': _state.pausedByUserId,
      'pausedAt': _state.pausedAt?.toIso8601String(),
    });
  }

  /// À brancher sur `Nearby().acceptConnection(endpointId,
  /// onPayLoadRecieved: transport.onPayloadReceived)`.
  void onPayloadReceived(String fromEndpointId, Payload payload) {
    if (payload.type != PayloadType.BYTES || payload.bytes == null) return;

    final message = jsonDecode(utf8.decode(payload.bytes!)) as Map<String, dynamic>;
    switch (message['type']) {
      case 'init':
        // Reçu côté invité uniquement.
        _state = NumberHuntBoardState(
          board: (message['board'] as List).map((e) => e as int).toList(),
          currentTarget: message['currentTarget'] as int?,
          scoresByUser: {kNumberHuntHostRole: 0, kNumberHuntGuestRole: 0},
          startedAt: message['startedAt'] != null ? DateTime.parse(message['startedAt'] as String) : ServerClock.instance.now(),
          myUserId: kNumberHuntGuestRole,
        );
        _controller.add(_state);
      case 'state':
        // Reçu côté invité (l'hôte fait autorité).
        final pausedByUserId = message['pausedByUserId'] as String?;
        _state = _state.copyWith(
          board: (message['board'] as List).map((e) => e as int).toList(),
          found: (message['found'] as Map).map((k, v) => MapEntry(k as String, v as String)),
          currentTarget: message['currentTarget'] as int?,
          clearTarget: message['currentTarget'] == null,
          scoresByUser: (message['scoresByUser'] as Map).map((k, v) => MapEntry(k as String, v as int)),
          winnerUserId: message['winnerUserId'] as String?,
          isTie: message['isTie'] as bool,
          movesCount: message['movesCount'] as int,
          finished: message['finished'] as bool,
          startedAt: message['startedAt'] != null ? DateTime.parse(message['startedAt'] as String) : _state.startedAt,
          pausedByUserId: pausedByUserId,
          pausedAt: message['pausedAt'] != null ? DateTime.parse(message['pausedAt'] as String) : null,
          clearPause: pausedByUserId == null,
        );
        _controller.add(_state);
      case 'attempt':
        // Reçu côté hôte uniquement — l'invité propose une tentative,
        // l'hôte l'arbitre (ordre d'arrivée) et redistribue le nouvel état.
        if (isHost) _applyHostAttempt(message['number'] as int, kNumberHuntGuestRole);
      case 'pause_request':
        if (isHost) _applyHostPause(kNumberHuntGuestRole);
      case 'resume_request':
        if (isHost) _applyHostResume(kNumberHuntGuestRole);
    }
  }

  void _applyHostAttempt(int number, String byRole) {
    if (_state.finished || _state.isPaused) return;
    final outcome = NumberHuntEngine.attempt(
      currentTarget: _state.currentTarget,
      found: _state.found,
      scoresByUser: _state.scoresByUser,
      number: number,
      userId: byRole,
      movesCount: _state.movesCount,
      creatorId: kNumberHuntHostRole,
      partnerId: kNumberHuntGuestRole,
      cellCount: _state.board.length,
    );
    if (!outcome.wasCorrect) return; // pas (ou plus) le nombre cible — rien à faire, pas d'erreur

    _state = _state.copyWith(
      found: outcome.found,
      scoresByUser: outcome.scoresByUser,
      currentTarget: outcome.newTarget,
      clearTarget: outcome.newTarget == null,
      movesCount: outcome.movesCount,
      finished: outcome.finished,
      winnerUserId: outcome.winnerUserId,
      isTie: outcome.isTie,
    );
    _controller.add(_state);
    _sendState();
  }

  void _applyHostPause(String byRole) {
    if (_state.isPaused || _state.finished) return;
    _state = _state.copyWith(pausedByUserId: byRole, pausedAt: ServerClock.instance.now());
    _controller.add(_state);
    _sendState();
  }

  void _applyHostResume(String byRole) {
    if (!_state.isPaused || _state.pausedByUserId != byRole) return;
    final paused = _state.pausedAt;
    if (paused != null && _state.startedAt != null) {
      _state = _state.copyWith(startedAt: _state.startedAt!.add(ServerClock.instance.now().difference(paused)));
    }
    _state = _state.copyWith(clearPause: true);
    _controller.add(_state);
    _sendState();
  }

  @override
  Stream<NumberHuntBoardState> get stateStream => _controller.stream;

  @override
  NumberHuntBoardState get currentState => _state;

  @override
  Future<void> attempt(int number) async {
    if (isHost) {
      _applyHostAttempt(number, kNumberHuntHostRole);
    } else {
      _send({'type': 'attempt', 'number': number});
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
      _applyHostPause(kNumberHuntHostRole);
    } else {
      _send({'type': 'pause_request'});
    }
  }

  @override
  Future<void> resume() async {
    if (!_state.pausedByMe) return;
    if (isHost) {
      _applyHostResume(kNumberHuntHostRole);
    } else {
      _send({'type': 'resume_request'});
    }
  }

  @override
  void dispose() {
    _controller.close();
  }
}
