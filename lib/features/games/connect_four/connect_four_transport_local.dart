import 'dart:async';

import 'connect_four_engine.dart';
import 'connect_four_transport.dart';

/// Mode "présentiel, un seul téléphone" (pass-and-play) — aucune
/// connexion, tout se joue en mémoire locale. Le "tour" reste un
/// indicateur purement visuel — copie structurelle conforme de
/// LocalDotSquaresTransport/LocalTicTacToeTransport.
class LocalConnectFourTransport extends ConnectFourTransport {
  final String myUserId;
  final String partnerUserId;
  final _controller = StreamController<ConnectFourBoardState>.broadcast();
  late ConnectFourBoardState _state;
  late final List<int> _columnMapping;

  LocalConnectFourTransport({required this.myUserId, required this.partnerUserId}) {
    _state = ConnectFourBoardState.initial(myUserId: myUserId);
    _columnMapping = ConnectFourEngine.generateColumnMapping();
  }

  @override
  Stream<ConnectFourBoardState> get stateStream => _controller.stream;

  @override
  ConnectFourBoardState get currentState => _state;

  @override
  bool get requiresTurnToPlay => false;

  @override
  Future<bool> drop(int pipe) async {
    if (_state.finished || _state.isPaused) return false;
    final currentPlayer = _state.currentTurnUserId ?? myUserId;
    final column = _columnMapping[pipe];

    final ConnectFourDropOutcome outcome;
    try {
      outcome = ConnectFourEngine.drop(
        board: _state.board,
        column: column,
        userId: currentPlayer,
        movesCount: _state.movesCount,
        creatorId: myUserId,
        partnerId: partnerUserId,
      );
    } on ArgumentError {
      return false; // tuyau menant à une colonne pleine — coup refusé, aucun jeton posé.
    }

    _state = _state.copyWith(
      board: outcome.board,
      currentTurnUserId: outcome.nextTurnUserId ?? currentPlayer,
      winnerUserId: outcome.winnerUserId,
      isTie: outcome.isTie,
      movesCount: outcome.movesCount,
      finished: outcome.finished,
      winningLine: outcome.winningLine,
    );
    _controller.add(_state);
    return true;
  }

  @override
  Future<void> abandon() async {
    _state = _state.copyWith(finished: true);
    _controller.add(_state);
  }

  // Même correctif que LocalDotSquaresTransport : `myUserId` reste fixe
  // pour toute la partie, donc l'utiliser comme `pausedByUserId` garantit
  // que `pausedByMe` reste vrai sur cet appareil partagé.
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
