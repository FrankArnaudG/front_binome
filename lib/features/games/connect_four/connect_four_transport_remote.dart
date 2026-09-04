import 'dart:async';

import '../../../core/api_client.dart';
import '../../../core/realtime_client.dart';
import '../../../models/connect_four_session.dart';
import '../game_service.dart';
import 'connect_four_transport.dart';

/// Mode "à distance" — synchronisation via le backend (REST pour les
/// coups, WebSocket Reverb pour recevoir ceux du binôme). Tour par tour
/// classique arbitré côté serveur (voir ConnectFourController::drop) —
/// copie structurelle conforme des autres jeux à distance.
class RemoteConnectFourTransport extends ConnectFourTransport {
  final String sessionId;
  final String boxId;
  final String myUserId;
  final _controller = StreamController<ConnectFourBoardState>.broadcast();
  late ConnectFourBoardState _state;

  RemoteConnectFourTransport({
    required ConnectFourSession session,
    required this.boxId,
    required this.myUserId,
  }) : sessionId = session.id {
    _state = _stateFrom(session);
    RealtimeClient.instance.subscribeToBox(boxId, onEvent: _onRealtimeEvent);
  }

  ConnectFourBoardState _stateFrom(ConnectFourSession session, {List<int>? winningLine}) => ConnectFourBoardState(
        board: session.board,
        currentTurnUserId: session.currentTurnUserId,
        winnerUserId: session.winnerUserId,
        isTie: session.isTie,
        movesCount: session.movesCount,
        finished: session.isFinished || session.abandoned,
        startedAt: session.startedAt,
        myUserId: myUserId,
        pausedByUserId: session.pausedByUserId,
        pausedAt: session.pausedAt,
        winningLine: winningLine,
      );

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.event != 'ConnectFourUpdated') return;
    final data = event.data;
    if (data == null) return;

    final session = ConnectFourSession.fromJson(data['session'] as Map<String, dynamic>);
    if (session.id != sessionId) return;

    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Stream<ConnectFourBoardState> get stateStream => _controller.stream;

  @override
  ConnectFourBoardState get currentState => _state;

  @override
  Future<bool> drop(int pipe) async {
    try {
      final result = await GameService.instance.dropConnectFour(sessionId, pipe);
      _state = _stateFrom(result.session, winningLine: result.winningLine);
      _controller.add(_state);
      return true;
    } on ApiException {
      // Tuyau menant à une colonne pleine (voir demande utilisateur : le
      // client ne peut jamais le savoir à l'avance, la correspondance est
      // cachée) — coup refusé côté serveur, pas une vraie erreur.
      return false;
    }
  }

  @override
  Future<void> abandon() async {
    final session = await GameService.instance.abandonConnectFour(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> pause() async {
    final session = await GameService.instance.pauseConnectFour(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> resume() async {
    if (!_state.pausedByMe) return;
    final session = await GameService.instance.resumeConnectFour(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  void dispose() {
    RealtimeClient.instance.unsubscribeFromBox(boxId, onEvent: _onRealtimeEvent);
    _controller.close();
  }
}
