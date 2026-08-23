import 'dart:async';

import 'memory_emoji_pool.dart';
import 'memory_game_engine.dart';
import 'memory_game_transport.dart';

/// Mode "présentiel, un seul téléphone" (pass-and-play) — aucune
/// connexion, tout se joue en mémoire locale. Le "tour" reste un
/// indicateur purement visuel (voir MemoryGameBoardScreen) : les deux
/// partenaires se passent le même appareil, donc [myUserId] alterne
/// simplement entre les deux identifiants selon [currentTurnUserId].
class LocalMemoryGameTransport extends MemoryGameTransport {
  final String myUserId;
  final String partnerUserId;
  final _controller = StreamController<MemoryGameBoardState>.broadcast();
  late MemoryGameBoardState _state;

  LocalMemoryGameTransport({
    required int pairCount,
    required this.myUserId,
    required this.partnerUserId,
  }) {
    _state = MemoryGameBoardState(
      board: generateShuffledMemoryBoard(pairCount),
      currentTurnUserId: myUserId,
      startedAt: DateTime.now(),
      // En pass-and-play, "myUserId" du state suit toujours le joueur dont
      // c'est le tour — voir isMyTurn, toujours vrai ici par construction.
      myUserId: myUserId,
    );
  }

  @override
  Stream<MemoryGameBoardState> get stateStream => _controller.stream;

  @override
  MemoryGameBoardState get currentState => _state;

  @override
  bool get requiresTurnToFlip => false;

  @override
  Future<void> flip(int index) async {
    if (_state.finished) return;
    final currentPlayer = _state.currentTurnUserId ?? myUserId;
    final otherPlayer = currentPlayer == myUserId ? partnerUserId : myUserId;

    final result = MemoryGameEngine.flip(
      board: _state.board,
      matched: _state.matched,
      flipped: _state.flipped,
      currentTurnUserId: currentPlayer,
      movesCount: _state.movesCount,
      movesByUser: _state.movesByUser,
      index: index,
      userId: currentPlayer,
      otherUserId: otherPlayer,
    );

    _state = _state.copyWith(
      matched: result.matched,
      flipped: result.flipped,
      mismatch: result.mismatch,
      clearMismatch: result.mismatch == null,
      currentTurnUserId: result.currentTurnUserId,
      movesCount: result.movesCount,
      movesByUser: result.movesByUser,
      finished: result.finished,
    );
    _controller.add(_state);
  }

  @override
  Future<void> abandon() async {
    _state = _state.copyWith(finished: true);
    _controller.add(_state);
  }

  @override
  void dispose() {
    _controller.close();
  }
}
