import '../../../models/memory_game_session.dart';

/// État unifié d'un plateau de "Jeu de Mémoire", quel que soit le mode —
/// [MemoryGameBoardScreen] ne connaît que cette forme, jamais les détails
/// de synchronisation sous-jacents (voir MemoryGameTransport).
class MemoryGameBoardState {
  final List<String> board;
  final List<MemoryGameMatchedPair> matched;
  final List<int> flipped;
  // Éphémère : la dernière paire ratée, à afficher un instant avant de la
  // recacher — jamais reflété dans [flipped] (voir MemoryGameEngine).
  final List<int>? mismatch;
  final String? currentTurnUserId;
  final int movesCount;
  final Map<String, int> movesByUser;
  final bool finished;
  final DateTime? startedAt;
  final String myUserId;

  const MemoryGameBoardState({
    required this.board,
    this.matched = const [],
    this.flipped = const [],
    this.mismatch,
    this.currentTurnUserId,
    this.movesCount = 0,
    this.movesByUser = const {},
    this.finished = false,
    this.startedAt,
    required this.myUserId,
  });

  bool get isMyTurn => currentTurnUserId == myUserId;

  Set<int> get matchedIndices => matched.expand((pair) => pair.indices ?? const <int>[]).toSet();

  MemoryGameBoardState copyWith({
    List<MemoryGameMatchedPair>? matched,
    List<int>? flipped,
    List<int>? mismatch,
    bool clearMismatch = false,
    String? currentTurnUserId,
    int? movesCount,
    Map<String, int>? movesByUser,
    bool? finished,
  }) =>
      MemoryGameBoardState(
        board: board,
        matched: matched ?? this.matched,
        flipped: flipped ?? this.flipped,
        mismatch: clearMismatch ? null : (mismatch ?? this.mismatch),
        currentTurnUserId: currentTurnUserId ?? this.currentTurnUserId,
        movesCount: movesCount ?? this.movesCount,
        movesByUser: movesByUser ?? this.movesByUser,
        finished: finished ?? this.finished,
        startedAt: startedAt,
        myUserId: myUserId,
      );
}

/// Abstraction commune aux 3 modes de "Jeu de Mémoire" — encapsule
/// UNIQUEMENT la façon dont les retournements de carte sont synchronisés
/// entre les deux joueurs (REST+WebSocket à distance, messages P2P en
/// Nearby, état local en pass-and-play) ; la logique de règles elle-même
/// est identique partout (voir MemoryGameEngine côté Dart, ou son
/// pendant PHP pour le mode à distance).
abstract class MemoryGameTransport {
  Stream<MemoryGameBoardState> get stateStream;

  MemoryGameBoardState get currentState;

  /// `false` uniquement pour le pass-and-play (voir
  /// LocalMemoryGameTransport) : les deux partenaires se passent le MÊME
  /// appareil, donc "à qui le tour" n'a de sens que comme indicateur
  /// visuel, jamais comme condition d'accès au plateau — contrairement à
  /// distance/Nearby, où retourner une carte hors de son tour doit être
  /// bloqué côté UI (en plus du 409 côté serveur pour le mode à distance).
  bool get requiresTurnToFlip => true;

  Future<void> flip(int index);

  Future<void> abandon();

  void dispose();
}
