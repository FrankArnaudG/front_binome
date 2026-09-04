import 'dart:async';

import 'dot_squares_engine.dart';
import 'dot_squares_transport.dart';

/// Mode "présentiel, un seul téléphone" (pass-and-play) — aucune
/// connexion, tout se joue en mémoire locale. Le "tour" reste un
/// indicateur purement visuel (voir DotSquaresBoardScreen) — copie
/// structurelle conforme de LocalTicTacToeTransport.
///
/// [requestClose] clôture IMMÉDIATEMENT (pas de proposition/confirmation :
/// les deux joueurs sont la même personne physique devant le même
/// appareil, voir demande utilisateur : "si on joue sur un seul
/// téléphone, c'est un seul clic").
class LocalDotSquaresTransport extends DotSquaresTransport {
  final String myUserId;
  final String partnerUserId;
  final _controller = StreamController<DotSquaresBoardState>.broadcast();
  late DotSquaresBoardState _state;

  LocalDotSquaresTransport({
    required this.myUserId,
    required this.partnerUserId,
    int cols = DotSquaresEngine.gridCols,
  }) {
    _state = DotSquaresBoardState.initial(myUserId: myUserId, partnerUserId: partnerUserId, cols: cols);
  }

  @override
  Stream<DotSquaresBoardState> get stateStream => _controller.stream;

  @override
  DotSquaresBoardState get currentState => _state;

  @override
  bool get requiresTurnToPlay => false;

  @override
  Future<void> place(int position) async {
    if (_state.finished || _state.isPaused) return;
    final currentPlayer = _state.currentTurnUserId ?? myUserId;
    final otherPlayer = currentPlayer == myUserId ? partnerUserId : myUserId;

    final result = DotSquaresEngine.place(
      points: _state.points,
      rectangles: _state.rectangles,
      scoresByUser: _state.scoresByUser,
      position: position,
      userId: currentPlayer,
      otherUserId: otherPlayer,
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
  }

  @override
  Future<void> requestClose() async {
    if (_state.finished) return;
    final scores = _state.scoresByUser;
    final myScore = scores[myUserId] ?? 0;
    final partnerScore = scores[partnerUserId] ?? 0;
    _state = _state.copyWith(
      finished: true,
      isTie: myScore == partnerScore,
      winnerUserId: myScore == partnerScore ? null : (myScore > partnerScore ? myUserId : partnerUserId),
    );
    _controller.add(_state);
  }

  @override
  Future<void> cancelCloseRequest() async {
    // Pas de proposition en attente possible en pass-and-play — no-op.
  }

  @override
  Future<void> abandon() async {
    _state = _state.copyWith(finished: true);
    _controller.add(_state);
  }

  // Même correctif que LocalTicTacToeTransport : `myUserId` reste fixe pour
  // toute la partie, donc l'utiliser comme `pausedByUserId` garantit que
  // `pausedByMe` reste vrai sur cet appareil partagé.
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
