import 'dart:async';

import '../../../core/realtime_client.dart';
import '../../../models/tic_tac_toe_session.dart';
import '../game_service.dart';
import 'tic_tac_toe_transport.dart';

/// Mode "à distance" — synchronisation via le backend (REST pour les
/// actions, WebSocket Reverb pour recevoir les coups de l'autre) — copie
/// structurelle conforme de RemoteMemoryGameTransport.
class RemoteTicTacToeTransport extends TicTacToeTransport {
  final String sessionId;
  final String boxId;
  final String myUserId;
  final _controller = StreamController<TicTacToeBoardState>.broadcast();
  late TicTacToeBoardState _state;

  RemoteTicTacToeTransport({
    required TicTacToeSession session,
    required this.boxId,
    required this.myUserId,
  }) : sessionId = session.id {
    _state = _stateFrom(session);
    RealtimeClient.instance.subscribeToBox(boxId, onEvent: _onRealtimeEvent);
  }

  TicTacToeBoardState _stateFrom(
    TicTacToeSession session, {
    List<int>? scoredLine,
    List<String?>? preScatterBoard,
  }) =>
      TicTacToeBoardState(
        board: session.board,
        piecesRemainingByUser: session.piecesRemainingByUser,
        scoresByUser: session.scoresByUser,
        targetScore: session.targetScore,
        currentTurnUserId: session.currentTurnUserId,
        winnerUserId: session.winnerUserId,
        isDraw: session.isDraw,
        movesCount: session.movesCount,
        finished: session.isFinished || session.abandoned,
        startedAt: session.startedAt,
        myUserId: myUserId,
        pausedByUserId: session.pausedByUserId,
        pausedAt: session.pausedAt,
        scoredLine: scoredLine,
        preScatterBoard: preScatterBoard,
      );

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.event != 'TicTacToeUpdated') return;
    final data = event.data;
    if (data == null) return;

    final session = TicTacToeSession.fromJson(data['session'] as Map<String, dynamic>);
    // Un event peut concerner une AUTRE partie de morpion du même box si
    // plusieurs étaient lancées coup sur coup — ignoré si ce n'est pas la
    // nôtre, même principe que RemoteMemoryGameTransport.
    if (session.id != sessionId) return;

    _state = _stateFrom(
      session,
      scoredLine: (data['scored_line'] as List?)?.map((e) => e as int).toList(),
      preScatterBoard: (data['pre_scatter_board'] as List?)?.map((e) => e as String?).toList(),
    );
    _controller.add(_state);
  }

  @override
  Stream<TicTacToeBoardState> get stateStream => _controller.stream;

  @override
  TicTacToeBoardState get currentState => _state;

  @override
  Future<void> place(int position) async {
    final result = await GameService.instance.playTicTacToeMove(sessionId, to: position);
    _state = _stateFrom(result.session, scoredLine: result.scoredLine, preScatterBoard: result.preScatterBoard);
    _controller.add(_state);
  }

  @override
  Future<void> move(int from, int to) async {
    final result = await GameService.instance.playTicTacToeMove(sessionId, to: to, from: from);
    _state = _stateFrom(result.session, scoredLine: result.scoredLine, preScatterBoard: result.preScatterBoard);
    _controller.add(_state);
  }

  @override
  Future<void> abandon() async {
    final session = await GameService.instance.abandonTicTacToe(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> pause() async {
    final session = await GameService.instance.pauseTicTacToe(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> resume() async {
    // Réservé à qui a posé la pause — le backend renvoie 403 sinon (voir
    // TicTacToeController::resume) ; l'UI ne propose de toute façon jamais
    // ce bouton à l'autre.
    if (!_state.pausedByMe) return;
    final session = await GameService.instance.resumeTicTacToe(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  void dispose() {
    RealtimeClient.instance.unsubscribeFromBox(boxId, onEvent: _onRealtimeEvent);
    _controller.close();
  }
}
