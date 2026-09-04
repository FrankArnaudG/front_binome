import 'dart:async';

import 'tic_tac_toe_engine.dart';
import 'tic_tac_toe_transport.dart';

/// Mode "présentiel, un seul téléphone" (pass-and-play) — aucune
/// connexion, tout se joue en mémoire locale. Le "tour" reste un
/// indicateur purement visuel (voir TicTacToeBoardScreen) — copie
/// structurelle conforme de LocalMemoryGameTransport.
class LocalTicTacToeTransport extends TicTacToeTransport {
  final String myUserId;
  final String partnerUserId;
  final _controller = StreamController<TicTacToeBoardState>.broadcast();
  late TicTacToeBoardState _state;

  LocalTicTacToeTransport({
    required this.myUserId,
    required this.partnerUserId,
  }) {
    _state = TicTacToeBoardState(
      piecesRemainingByUser: {
        myUserId: TicTacToeEngine.placementPiecesPerPlayer,
        partnerUserId: TicTacToeEngine.placementPiecesPerPlayer,
      },
      scoresByUser: {myUserId: 0, partnerUserId: 0},
      currentTurnUserId: myUserId,
      startedAt: DateTime.now(),
      myUserId: myUserId,
    );
  }

  @override
  Stream<TicTacToeBoardState> get stateStream => _controller.stream;

  @override
  TicTacToeBoardState get currentState => _state;

  @override
  bool get requiresTurnToPlay => false;

  @override
  Future<void> place(int position) async {
    if (_state.finished || _state.isPaused) return;
    final currentPlayer = _state.currentTurnUserId ?? myUserId;
    final otherPlayer = currentPlayer == myUserId ? partnerUserId : myUserId;

    final result = TicTacToeEngine.place(
      board: _state.board,
      piecesRemainingByUser: _state.piecesRemainingByUser,
      scoresByUser: _state.scoresByUser,
      position: position,
      userId: currentPlayer,
      otherUserId: otherPlayer,
      movesCount: _state.movesCount,
    );
    _applyResult(result);
  }

  @override
  Future<void> move(int from, int to) async {
    if (_state.finished || _state.isPaused) return;
    final currentPlayer = _state.currentTurnUserId ?? myUserId;
    final otherPlayer = currentPlayer == myUserId ? partnerUserId : myUserId;

    final result = TicTacToeEngine.move(
      board: _state.board,
      piecesRemainingByUser: _state.piecesRemainingByUser,
      scoresByUser: _state.scoresByUser,
      from: from,
      to: to,
      userId: currentPlayer,
      otherUserId: otherPlayer,
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
  }

  @override
  Future<void> abandon() async {
    _state = _state.copyWith(finished: true);
    _controller.add(_state);
  }

  // Même correctif que LocalMemoryGameTransport : `myUserId` reste fixe
  // pour toute la partie (ce n'est PAS le joueur dont c'est le tour), donc
  // l'utiliser comme `pausedByUserId` garantit que `pausedByMe` reste vrai
  // sur cet appareil partagé, où la restriction "seul qui a posé la pause
  // peut la lever" n'a physiquement aucun sens.
  @override
  Future<void> pause() async {
    if (_state.isPaused || _state.finished) return;
    _state = _state.copyWith(pausedByUserId: myUserId, pausedAt: DateTime.now());
    _controller.add(_state);
  }

  @override
  Future<void> resume() async {
    if (!_state.isPaused) return;
    final paused = _state.pausedAt;
    if (paused != null && _state.startedAt != null) {
      _state = _state.copyWith(startedAt: _state.startedAt!.add(DateTime.now().difference(paused)));
    }
    _state = _state.copyWith(clearPause: true);
    _controller.add(_state);
  }

  @override
  void dispose() {
    _controller.close();
  }
}
