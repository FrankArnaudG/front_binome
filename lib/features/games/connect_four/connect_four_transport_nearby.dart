import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nearby_connections/nearby_connections.dart';

import 'connect_four_engine.dart';
import 'connect_four_transport.dart';

/// Identifiants internes des deux rôles — voir kDotSquaresHostRole/
/// kDotSquaresGuestRole, même principe (Nearby Connections n'a pas de
/// notion de compte).
const kConnectFourHostRole = 'host';
const kConnectFourGuestRole = 'guest';

/// Mode "présentiel connecté" — l'HÔTE est autoritaire : lui seul applique
/// ConnectFourEngine, l'invité ne fait que proposer des coups et recevoir
/// l'état à jour. Copie structurelle conforme de NearbyDotSquaresTransport.
class NearbyConnectFourTransport extends ConnectFourTransport {
  final Nearby nearby;
  final String endpointId;
  final bool isHost;
  final _controller = StreamController<ConnectFourBoardState>.broadcast();
  late ConnectFourBoardState _state;
  // Voir demande utilisateur : "tuyaux" — jamais envoyée à l'invité, même
  // en mémoire (l'hôte seul traduit tuyau → vraie colonne, voir
  // _applyHostDrop) ; l'invité n'a besoin que du plateau résultant.
  late final List<int> _columnMapping;

  /// Côté hôte : démarre la partie et l'envoie tout de suite à l'invité.
  NearbyConnectFourTransport.host({
    required this.nearby,
    required this.endpointId,
  }) : isHost = true {
    _state = ConnectFourBoardState.initial(myUserId: kConnectFourHostRole);
    _columnMapping = ConnectFourEngine.generateColumnMapping();
    _sendInit();
  }

  /// Côté invité : état par défaut tant que le message `init` de l'hôte
  /// n'est pas arrivé.
  NearbyConnectFourTransport.guest({
    required this.nearby,
    required this.endpointId,
  }) : isHost = false {
    _state = const ConnectFourBoardState(myUserId: kConnectFourGuestRole);
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
      'currentTurnUserId': _state.currentTurnUserId,
      'winnerUserId': _state.winnerUserId,
      'isTie': _state.isTie,
      'movesCount': _state.movesCount,
      'finished': _state.finished,
      'startedAt': _state.startedAt?.toIso8601String(),
      'pausedByUserId': _state.pausedByUserId,
      'pausedAt': _state.pausedAt?.toIso8601String(),
      'winningLine': _state.winningLine,
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
        _state = ConnectFourBoardState(
          board: ConnectFourEngine.generateInitialState(),
          currentTurnUserId: kConnectFourHostRole,
          startedAt: message['startedAt'] != null ? DateTime.parse(message['startedAt'] as String) : DateTime.now(),
          myUserId: kConnectFourGuestRole,
        );
        _controller.add(_state);
      case 'state':
        // Reçu côté invité (l'hôte fait autorité).
        final pausedByUserId = message['pausedByUserId'] as String?;
        _state = _state.copyWith(
          board: (message['board'] as List).map((e) => e as String?).toList(),
          currentTurnUserId: message['currentTurnUserId'] as String?,
          winnerUserId: message['winnerUserId'] as String?,
          isTie: message['isTie'] as bool,
          movesCount: message['movesCount'] as int,
          finished: message['finished'] as bool,
          startedAt: message['startedAt'] != null ? DateTime.parse(message['startedAt'] as String) : _state.startedAt,
          pausedByUserId: pausedByUserId,
          pausedAt: message['pausedAt'] != null ? DateTime.parse(message['pausedAt'] as String) : null,
          clearPause: pausedByUserId == null,
          winningLine: (message['winningLine'] as List?)?.map((e) => e as int).toList(),
        );
        _controller.add(_state);
      case 'drop':
        // Reçu côté hôte uniquement — l'invité propose un TUYAU, l'hôte
        // seul connaît la vraie colonne (voir _columnMapping), l'arbitre
        // et redistribue le nouvel état.
        if (isHost) _applyHostDrop(message['pipe'] as int, kConnectFourGuestRole);
      case 'pause_request':
        if (isHost) _applyHostPause(kConnectFourGuestRole);
      case 'resume_request':
        if (isHost) _applyHostResume(kConnectFourGuestRole);
    }
  }

  bool _applyHostDrop(int pipe, String byRole) {
    if (_state.finished || _state.isPaused) return false;
    if (_state.currentTurnUserId != byRole) return false;
    final column = _columnMapping[pipe];

    final ConnectFourDropOutcome outcome;
    try {
      outcome = ConnectFourEngine.drop(
        board: _state.board,
        column: column,
        userId: byRole,
        movesCount: _state.movesCount,
        creatorId: kConnectFourHostRole,
        partnerId: kConnectFourGuestRole,
      );
    } on ArgumentError {
      return false;
    }

    _state = _state.copyWith(
      board: outcome.board,
      currentTurnUserId: outcome.nextTurnUserId ?? _state.currentTurnUserId,
      winnerUserId: outcome.winnerUserId,
      isTie: outcome.isTie,
      movesCount: outcome.movesCount,
      finished: outcome.finished,
      winningLine: outcome.winningLine,
    );
    _controller.add(_state);
    _sendState();
    return true;
  }

  void _applyHostPause(String byRole) {
    if (_state.isPaused || _state.finished) return;
    _state = _state.copyWith(pausedByUserId: byRole, pausedAt: DateTime.now());
    _controller.add(_state);
    _sendState();
  }

  void _applyHostResume(String byRole) {
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
  Stream<ConnectFourBoardState> get stateStream => _controller.stream;

  @override
  ConnectFourBoardState get currentState => _state;

  @override
  Future<bool> drop(int pipe) async {
    if (isHost) {
      return _applyHostDrop(pipe, kConnectFourHostRole);
    }
    // L'invité n'a aucun moyen de savoir synchroniquement si le tuyau
    // menait à une colonne pleine (seul l'hôte connaît la traduction) —
    // le nouvel état arrivera via `_sendState()` si le coup a été
    // accepté ; ce cas limite reste sans retour visuel côté invité.
    _send({'type': 'drop', 'pipe': pipe});
    return true;
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
      _applyHostPause(kConnectFourHostRole);
    } else {
      _send({'type': 'pause_request'});
    }
  }

  @override
  Future<void> resume() async {
    if (!_state.pausedByMe) return;
    if (isHost) {
      _applyHostResume(kConnectFourHostRole);
    } else {
      _send({'type': 'resume_request'});
    }
  }

  @override
  void dispose() {
    _controller.close();
  }
}
