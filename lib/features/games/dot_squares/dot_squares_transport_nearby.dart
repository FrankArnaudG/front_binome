import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nearby_connections/nearby_connections.dart';

import '../../../models/dot_square_session.dart';
import 'dot_squares_engine.dart';
import 'dot_squares_transport.dart';
import '../../../core/server_clock.dart';

/// Identifiants internes des deux rôles — voir kNearbyHostRole/
/// kNearbyGuestRole dans memory_game_transport_nearby.dart, même principe
/// (Nearby Connections n'a pas de notion de compte).
const kDotSquaresHostRole = 'host';
const kDotSquaresGuestRole = 'guest';

/// Mode "présentiel connecté" — l'HÔTE est autoritaire : lui seul applique
/// DotSquaresEngine, l'invité ne fait que proposer des coups/demandes et
/// recevoir l'état à jour. Copie structurelle conforme de
/// NearbyTicTacToeTransport.
class NearbyDotSquaresTransport extends DotSquaresTransport {
  final Nearby nearby;
  final String endpointId;
  final bool isHost;
  final _controller = StreamController<DotSquaresBoardState>.broadcast();
  late DotSquaresBoardState _state;

  /// Côté hôte : démarre la partie et l'envoie tout de suite à l'invité.
  NearbyDotSquaresTransport.host({
    required this.nearby,
    required this.endpointId,
    int cols = DotSquaresEngine.gridCols,
  }) : isHost = true {
    _state = DotSquaresBoardState.initial(myUserId: kDotSquaresHostRole, partnerUserId: kDotSquaresGuestRole, cols: cols);
    _sendInit();
  }

  /// Côté invité : état par défaut tant que le message `init` de l'hôte
  /// n'est pas arrivé.
  NearbyDotSquaresTransport.guest({
    required this.nearby,
    required this.endpointId,
  }) : isHost = false {
    _state = const DotSquaresBoardState(myUserId: kDotSquaresGuestRole);
  }

  void _send(Map<String, dynamic> message) {
    nearby.sendBytesPayload(endpointId, Uint8List.fromList(utf8.encode(jsonEncode(message))));
  }

  void _sendInit() {
    _send({
      'type': 'init',
      'gridCols': _state.gridCols,
      'startedAt': _state.startedAt?.toIso8601String(),
    });
  }

  void _sendState() {
    _send({
      'type': 'state',
      'points': _state.points,
      'rectangles': _state.rectangles.map((r) => r.toJson()).toList(),
      'scoresByUser': _state.scoresByUser,
      'currentTurnUserId': _state.currentTurnUserId,
      'winnerUserId': _state.winnerUserId,
      'isTie': _state.isTie,
      'movesCount': _state.movesCount,
      'finished': _state.finished,
      'abandoned': _state.abandoned,
      'startedAt': _state.startedAt?.toIso8601String(),
      'pausedByUserId': _state.pausedByUserId,
      'pausedAt': _state.pausedAt?.toIso8601String(),
      'closeRequestedByUserId': _state.closeRequestedByUserId,
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
        _state = DotSquaresBoardState.initial(
          myUserId: kDotSquaresGuestRole,
          partnerUserId: kDotSquaresHostRole,
          cols: message['gridCols'] as int? ?? DotSquaresEngine.gridCols,
        ).copyWith(
          currentTurnUserId: kDotSquaresHostRole,
          startedAt: message['startedAt'] != null ? DateTime.parse(message['startedAt'] as String) : ServerClock.instance.now(),
        );
        _controller.add(_state);
      case 'state':
        // Reçu côté invité (l'hôte fait autorité).
        final closeRequestedByUserId = message['closeRequestedByUserId'] as String?;
        final pausedByUserId = message['pausedByUserId'] as String?;
        _state = _state.copyWith(
          points: (message['points'] as List).map((e) => e as String?).toList(),
          rectangles: (message['rectangles'] as List)
              .map((e) => DotSquareRectangle.fromJson(e as Map<String, dynamic>))
              .toList(),
          scoresByUser: (message['scoresByUser'] as Map).map((k, v) => MapEntry(k as String, v as int)),
          currentTurnUserId: message['currentTurnUserId'] as String?,
          winnerUserId: message['winnerUserId'] as String?,
          isTie: message['isTie'] as bool,
          movesCount: message['movesCount'] as int,
          finished: message['finished'] as bool,
          abandoned: message['abandoned'] as bool? ?? false,
          startedAt: message['startedAt'] != null ? DateTime.parse(message['startedAt'] as String) : _state.startedAt,
          pausedByUserId: pausedByUserId,
          pausedAt: message['pausedAt'] != null ? DateTime.parse(message['pausedAt'] as String) : null,
          clearPause: pausedByUserId == null,
          closeRequestedByUserId: closeRequestedByUserId,
          clearCloseRequest: closeRequestedByUserId == null,
        );
        _controller.add(_state);
      case 'place':
        // Reçu côté hôte uniquement — l'invité propose une pose, l'hôte
        // l'arbitre et redistribue le nouvel état.
        if (isHost) _applyHostPlace(message['position'] as int, kDotSquaresGuestRole);
      case 'close_request':
        if (isHost) _applyHostRequestClose(kDotSquaresGuestRole);
      case 'close_cancel':
        if (isHost) _applyHostCancelClose(kDotSquaresGuestRole);
      case 'pause_request':
        if (isHost) _applyHostPause(kDotSquaresGuestRole);
      case 'resume_request':
        if (isHost) _applyHostResume(kDotSquaresGuestRole);
      case 'abandon_request':
        if (isHost) _applyHostAbandon();
    }
  }

  void _applyHostPlace(int position, String byRole) {
    if (_state.finished || _state.isPaused) return;
    final otherRole = byRole == kDotSquaresHostRole ? kDotSquaresGuestRole : kDotSquaresHostRole;
    final result = DotSquaresEngine.place(
      points: _state.points,
      rectangles: _state.rectangles,
      scoresByUser: _state.scoresByUser,
      position: position,
      userId: byRole,
      otherUserId: otherRole,
      movesCount: _state.movesCount,
      cols: _state.gridCols,
    );
    _state = _state.copyWith(
      points: result.points,
      rectangles: result.rectangles,
      scoresByUser: result.scoresByUser,
      currentTurnUserId: result.currentTurnUserId ?? _state.currentTurnUserId,
      winnerUserId: result.winnerUserId,
      isTie: result.isTie,
      movesCount: result.movesCount,
      finished: result.finished,
      newlyScored: result.newlyScored,
    );
    _controller.add(_state);
    _sendState();
  }

  void _applyHostRequestClose(String byRole) {
    if (_state.finished || _state.isPaused) return;
    final requestedBy = _state.closeRequestedByUserId;
    if (requestedBy == null) {
      _state = _state.copyWith(closeRequestedByUserId: byRole);
    } else if (requestedBy != byRole) {
      final scores = _state.scoresByUser;
      final hostScore = scores[kDotSquaresHostRole] ?? 0;
      final guestScore = scores[kDotSquaresGuestRole] ?? 0;
      _state = _state.copyWith(
        finished: true,
        isTie: hostScore == guestScore,
        winnerUserId: hostScore == guestScore ? null : (hostScore > guestScore ? kDotSquaresHostRole : kDotSquaresGuestRole),
      );
    }
    _controller.add(_state);
    _sendState();
  }

  void _applyHostCancelClose(String byRole) {
    if (_state.closeRequestedByUserId != byRole) return;
    _state = _state.copyWith(clearCloseRequest: true);
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
    // Réservé à qui a posé la pause — un appel par l'autre rôle est
    // silencieusement ignoré, même principe que le 403 côté backend pour
    // le mode à distance.
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
  Stream<DotSquaresBoardState> get stateStream => _controller.stream;

  @override
  DotSquaresBoardState get currentState => _state;

  @override
  Future<void> place(int position) async {
    if (isHost) {
      _applyHostPlace(position, kDotSquaresHostRole);
    } else {
      _send({'type': 'place', 'position': position});
    }
  }

  @override
  Future<void> requestClose() async {
    if (isHost) {
      _applyHostRequestClose(kDotSquaresHostRole);
    } else {
      _send({'type': 'close_request'});
    }
  }

  @override
  Future<void> cancelCloseRequest() async {
    if (_state.closeRequestedByUserId != (isHost ? kDotSquaresHostRole : kDotSquaresGuestRole)) return;
    if (isHost) {
      _applyHostCancelClose(kDotSquaresHostRole);
    } else {
      _send({'type': 'close_cancel'});
    }
  }

  @override
  Future<void> abandon() async {
    if (isHost) {
      _applyHostAbandon();
    } else {
      // Prévient l'hôte pour qu'il redistribue l'état "abandonné" à son
      // tour (voir demande utilisateur : "mon binôme ne reçoit rien") —
      // même principe que pause_request : seul l'hôte fait autorité et
      // diffuse, l'invité ne peut pas clore la partie unilatéralement pour
      // l'autre. Reflété localement tout de suite pour fermer SON écran
      // sans attendre l'aller-retour Bluetooth (voir _confirmAbandon).
      _send({'type': 'abandon_request'});
      _state = _state.copyWith(finished: true, abandoned: true);
      _controller.add(_state);
    }
  }

  void _applyHostAbandon() {
    if (_state.finished) return;
    _state = _state.copyWith(finished: true, abandoned: true);
    _controller.add(_state);
    _sendState();
  }

  @override
  Future<void> pause() async {
    if (isHost) {
      _applyHostPause(kDotSquaresHostRole);
    } else {
      _send({'type': 'pause_request'});
    }
  }

  @override
  Future<void> resume() async {
    if (!_state.pausedByMe) return;
    if (isHost) {
      _applyHostResume(kDotSquaresHostRole);
    } else {
      _send({'type': 'resume_request'});
    }
  }

  @override
  void dispose() {
    _controller.close();
  }
}
