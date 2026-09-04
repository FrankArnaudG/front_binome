import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nearby_connections/nearby_connections.dart';

import 'tic_tac_toe_engine.dart';
import 'tic_tac_toe_transport.dart';

/// Identifiants internes des deux rôles — voir kNearbyHostRole/
/// kNearbyGuestRole dans memory_game_transport_nearby.dart, même principe
/// (Nearby Connections n'a pas de notion de compte).
const kTicTacToeHostRole = 'host';
const kTicTacToeGuestRole = 'guest';

/// Mode "présentiel connecté" — l'HÔTE est autoritaire : lui seul applique
/// TicTacToeEngine, l'invité ne fait que proposer des coups et recevoir
/// l'état à jour. Copie structurelle conforme de NearbyMemoryGameTransport.
class NearbyTicTacToeTransport extends TicTacToeTransport {
  final Nearby nearby;
  final String endpointId;
  final bool isHost;
  final _controller = StreamController<TicTacToeBoardState>.broadcast();
  late TicTacToeBoardState _state;

  /// Côté hôte : démarre la partie et l'envoie tout de suite à l'invité.
  NearbyTicTacToeTransport.host({
    required this.nearby,
    required this.endpointId,
  }) : isHost = true {
    _state = TicTacToeBoardState(
      piecesRemainingByUser: {
        kTicTacToeHostRole: TicTacToeEngine.placementPiecesPerPlayer,
        kTicTacToeGuestRole: TicTacToeEngine.placementPiecesPerPlayer,
      },
      scoresByUser: {kTicTacToeHostRole: 0, kTicTacToeGuestRole: 0},
      currentTurnUserId: kTicTacToeHostRole,
      startedAt: DateTime.now(),
      myUserId: kTicTacToeHostRole,
    );
    _sendInit();
  }

  /// Côté invité : état par défaut tant que le message `init` de l'hôte
  /// n'est pas arrivé.
  NearbyTicTacToeTransport.guest({
    required this.nearby,
    required this.endpointId,
  }) : isHost = false {
    _state = const TicTacToeBoardState(myUserId: kTicTacToeGuestRole);
  }

  void _send(Map<String, dynamic> message) {
    nearby.sendBytesPayload(endpointId, Uint8List.fromList(utf8.encode(jsonEncode(message))));
  }

  void _sendInit() {
    _send({
      'type': 'init',
      'startedAt': _state.startedAt?.toIso8601String(),
    });
  }

  void _sendState() {
    _send({
      'type': 'state',
      'board': _state.board,
      'piecesRemainingByUser': _state.piecesRemainingByUser,
      'scoresByUser': _state.scoresByUser,
      'targetScore': _state.targetScore,
      'currentTurnUserId': _state.currentTurnUserId,
      'winnerUserId': _state.winnerUserId,
      'isDraw': _state.isDraw,
      'movesCount': _state.movesCount,
      'finished': _state.finished,
      'startedAt': _state.startedAt?.toIso8601String(),
      'pausedByUserId': _state.pausedByUserId,
      'pausedAt': _state.pausedAt?.toIso8601String(),
      'scoredLine': _state.scoredLine,
      'preScatterBoard': _state.preScatterBoard,
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
        _state = TicTacToeBoardState(
          piecesRemainingByUser: {
            kTicTacToeHostRole: TicTacToeEngine.placementPiecesPerPlayer,
            kTicTacToeGuestRole: TicTacToeEngine.placementPiecesPerPlayer,
          },
          scoresByUser: {kTicTacToeHostRole: 0, kTicTacToeGuestRole: 0},
          currentTurnUserId: kTicTacToeHostRole,
          startedAt: message['startedAt'] != null ? DateTime.parse(message['startedAt'] as String) : DateTime.now(),
          myUserId: kTicTacToeGuestRole,
        );
        _controller.add(_state);
      case 'state':
        // Reçu côté invité (l'hôte fait autorité).
        final pausedByUserId = message['pausedByUserId'] as String?;
        _state = _state.copyWith(
          board: (message['board'] as List).map((e) => e as String?).toList(),
          piecesRemainingByUser: (message['piecesRemainingByUser'] as Map).map((k, v) => MapEntry(k as String, v as int)),
          scoresByUser: (message['scoresByUser'] as Map).map((k, v) => MapEntry(k as String, v as int)),
          targetScore: message['targetScore'] as int,
          currentTurnUserId: message['currentTurnUserId'] as String?,
          winnerUserId: message['winnerUserId'] as String?,
          isDraw: message['isDraw'] as bool,
          movesCount: message['movesCount'] as int,
          finished: message['finished'] as bool,
          startedAt: message['startedAt'] != null ? DateTime.parse(message['startedAt'] as String) : _state.startedAt,
          pausedByUserId: pausedByUserId,
          pausedAt: message['pausedAt'] != null ? DateTime.parse(message['pausedAt'] as String) : null,
          clearPause: pausedByUserId == null,
          scoredLine: (message['scoredLine'] as List?)?.map((e) => e as int).toList(),
          preScatterBoard: (message['preScatterBoard'] as List?)?.map((e) => e as String?).toList(),
        );
        _controller.add(_state);
      case 'place':
        // Reçu côté hôte uniquement — l'invité propose une pose, l'hôte
        // l'arbitre et redistribue le nouvel état.
        if (isHost) _applyHostPlace(message['position'] as int, kTicTacToeGuestRole);
      case 'move':
        if (isHost) _applyHostMove(message['from'] as int, message['to'] as int, kTicTacToeGuestRole);
      case 'pause_request':
        if (isHost) _applyHostPause(kTicTacToeGuestRole);
      case 'resume_request':
        if (isHost) _applyHostResume(kTicTacToeGuestRole);
    }
  }

  void _applyHostPlace(int position, String byRole) {
    if (_state.finished || _state.isPaused) return;
    final otherRole = byRole == kTicTacToeHostRole ? kTicTacToeGuestRole : kTicTacToeHostRole;
    final result = TicTacToeEngine.place(
      board: _state.board,
      piecesRemainingByUser: _state.piecesRemainingByUser,
      scoresByUser: _state.scoresByUser,
      position: position,
      userId: byRole,
      otherUserId: otherRole,
      movesCount: _state.movesCount,
    );
    _applyResult(result);
  }

  void _applyHostMove(int from, int to, String byRole) {
    if (_state.finished || _state.isPaused) return;
    final otherRole = byRole == kTicTacToeHostRole ? kTicTacToeGuestRole : kTicTacToeHostRole;
    final result = TicTacToeEngine.move(
      board: _state.board,
      piecesRemainingByUser: _state.piecesRemainingByUser,
      scoresByUser: _state.scoresByUser,
      from: from,
      to: to,
      userId: byRole,
      otherUserId: otherRole,
      movesCount: _state.movesCount,
    );
    _applyResult(result);
  }

  void _applyResult(TicTacToeMoveResult result) {
    _state = _state.copyWith(
      board: result.board,
      piecesRemainingByUser: result.piecesRemainingByUser,
      scoresByUser: result.scoresByUser,
      currentTurnUserId: result.currentTurnUserId ?? _state.currentTurnUserId,
      winnerUserId: result.winnerUserId,
      movesCount: result.movesCount,
      finished: result.finished,
      scoredLine: result.scoredLine,
      preScatterBoard: result.preScatterBoard,
    );
    _controller.add(_state);
    _sendState();
  }

  void _applyHostPause(String byRole) {
    if (_state.isPaused || _state.finished) return;
    _state = _state.copyWith(pausedByUserId: byRole, pausedAt: DateTime.now());
    _controller.add(_state);
    _sendState();
  }

  void _applyHostResume(String byRole) {
    // Réservé à qui a posé la pause — un appel par l'autre rôle est
    // silencieusement ignoré, même principe que le 403 côté backend pour
    // le mode à distance.
    if (!_state.isPaused || _state.pausedByUserId != byRole) return;
    final paused = _state.pausedAt;
    if (paused != null && _state.startedAt != null) {
      _state = _state.copyWith(startedAt: _state.startedAt!.add(DateTime.now().difference(paused)));
    }
    _state = _state.copyWith(clearPause: true);
    _controller.add(_state);
    _sendState();
  }

  @override
  Stream<TicTacToeBoardState> get stateStream => _controller.stream;

  @override
  TicTacToeBoardState get currentState => _state;

  @override
  Future<void> place(int position) async {
    if (isHost) {
      _applyHostPlace(position, kTicTacToeHostRole);
    } else {
      _send({'type': 'place', 'position': position});
    }
  }

  @override
  Future<void> move(int from, int to) async {
    if (isHost) {
      _applyHostMove(from, to, kTicTacToeHostRole);
    } else {
      _send({'type': 'move', 'from': from, 'to': to});
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
      _applyHostPause(kTicTacToeHostRole);
    } else {
      _send({'type': 'pause_request'});
    }
  }

  @override
  Future<void> resume() async {
    if (!_state.pausedByMe) return;
    if (isHost) {
      _applyHostResume(kTicTacToeHostRole);
    } else {
      _send({'type': 'resume_request'});
    }
  }

  @override
  void dispose() {
    _controller.close();
  }
}
