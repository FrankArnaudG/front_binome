import 'dart:async';

import '../../../core/realtime_client.dart';
import '../../../models/tic_tac_toe_session.dart';
import '../game_service.dart';
import 'tic_tac_toe_engine.dart';
import 'tic_tac_toe_transport.dart';

/// Mode "à distance" — synchronisation via le backend (REST pour les
/// actions, WebSocket Reverb pour recevoir les coups de l'autre) — copie
/// structurelle conforme de RemoteMemoryGameTransport.
class RemoteTicTacToeTransport extends TicTacToeTransport {
  final String sessionId;
  final String boxId;
  final String myUserId;
  final String partnerUserId;
  final _controller = StreamController<TicTacToeBoardState>.broadcast();
  late TicTacToeBoardState _state;

  RemoteTicTacToeTransport({
    required TicTacToeSession session,
    required this.boxId,
    required this.myUserId,
    required this.partnerUserId,
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
        abandoned: session.abandoned,
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

  // Prédiction locale immédiate (voir RemoteMemoryGameTransport.flip pour le
  // même principe et sa justification) — sûre uniquement parce que ce
  // chemin n'est atteint que si c'est déjà mon tour (voir
  // TicTacToeBoardScreen), donc jamais de coup adverse concurrent à prévoir.
  // La dispersion aléatoire après alignement peut différer de celle du
  // serveur : sans conséquence visible, la réponse HTTP arrive presque
  // aussitôt et écrase cette prédiction avec l'état réel.
  void _applyOptimistic(TicTacToeMoveResult result) {
    _state = _state.copyWith(
      board: result.board,
      piecesRemainingByUser: result.piecesRemainingByUser,
      scoresByUser: result.scoresByUser,
      currentTurnUserId: result.currentTurnUserId,
      winnerUserId: result.winnerUserId,
      movesCount: result.movesCount,
      finished: result.finished,
      scoredLine: result.scoredLine,
      preScatterBoard: result.preScatterBoard,
    );
    _controller.add(_state);
  }

  Future<void> _resyncAfterFailure() async {
    try {
      final session = await GameService.instance.fetchTicTacToeState(sessionId);
      _state = _stateFrom(session);
      _controller.add(_state);
    } catch (_) {
      // best effort — voir doc de classe RealtimeClient.
    }
  }

  @override
  Future<void> place(int position) async {
    try {
      _applyOptimistic(TicTacToeEngine.place(
        board: _state.board,
        piecesRemainingByUser: _state.piecesRemainingByUser,
        scoresByUser: _state.scoresByUser,
        position: position,
        userId: myUserId,
        otherUserId: partnerUserId,
        movesCount: _state.movesCount,
      ));
    } catch (_) {
      // Coup localement invalide — le serveur tranchera.
    }

    try {
      final result = await GameService.instance.playTicTacToeMove(sessionId, to: position);
      _state = _stateFrom(result.session, scoredLine: result.scoredLine, preScatterBoard: result.preScatterBoard);
      _controller.add(_state);
    } catch (_) {
      await _resyncAfterFailure();
    }
  }

  @override
  Future<void> move(int from, int to) async {
    try {
      _applyOptimistic(TicTacToeEngine.move(
        board: _state.board,
        piecesRemainingByUser: _state.piecesRemainingByUser,
        scoresByUser: _state.scoresByUser,
        from: from,
        to: to,
        userId: myUserId,
        otherUserId: partnerUserId,
        movesCount: _state.movesCount,
      ));
    } catch (_) {
      // Coup localement invalide — le serveur tranchera.
    }

    try {
      final result = await GameService.instance.playTicTacToeMove(sessionId, to: to, from: from);
      _state = _stateFrom(result.session, scoredLine: result.scoredLine, preScatterBoard: result.preScatterBoard);
      _controller.add(_state);
    } catch (_) {
      await _resyncAfterFailure();
    }
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
