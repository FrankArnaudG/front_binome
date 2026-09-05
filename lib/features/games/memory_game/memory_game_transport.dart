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
  // Distinct d'une fin normale (plateau entièrement retrouvé) — voir
  // MemoryGameBoardScreen._onState : seule cette valeur déclenche la pop-up
  // "{partenaire} a mis fin à cette partie" plutôt que le scoreboard
  // habituel (voir demande utilisateur).
  final bool abandoned;
  final DateTime? startedAt;
  final String myUserId;
  // Non-null tant que la partie est en pause — id de qui l'a posée (voir
  // demande utilisateur : "c'est uniquement celui qui a mis la pose qui
  // peut la lever").
  final String? pausedByUserId;
  // Moment où la pause EN COURS a commencé — sert uniquement à figer
  // l'affichage du chrono (voir MemoryGameBoardScreen._elapsed) : sans ça,
  // le temps continuerait de s'écouler à l'écran pendant la pause, alors
  // que startedAt n'est décalé qu'À LA REPRISE (voir MemoryGameController::
  // resume et son équivalent local/Nearby).
  final DateTime? pausedAt;

  const MemoryGameBoardState({
    required this.board,
    this.matched = const [],
    this.flipped = const [],
    this.mismatch,
    this.currentTurnUserId,
    this.movesCount = 0,
    this.movesByUser = const {},
    this.finished = false,
    this.abandoned = false,
    this.startedAt,
    required this.myUserId,
    this.pausedByUserId,
    this.pausedAt,
  });

  bool get isMyTurn => currentTurnUserId == myUserId;
  bool get isPaused => pausedByUserId != null;
  bool get pausedByMe => pausedByUserId == myUserId;

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
    bool? abandoned,
    DateTime? startedAt,
    String? pausedByUserId,
    DateTime? pausedAt,
    // Distingue "ne pas toucher pausedByUserId/pausedAt" (défaut) de "les
    // remettre à null" (voir resume(), même motif que clearMismatch) —
    // sans ce flag, passer littéralement `null` pour lever la pause serait
    // indiscernable de "je ne fournis rien".
    bool clearPause = false,
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
        abandoned: abandoned ?? this.abandoned,
        startedAt: startedAt ?? this.startedAt,
        myUserId: myUserId,
        pausedByUserId: clearPause ? null : (pausedByUserId ?? this.pausedByUserId),
        pausedAt: clearPause ? null : (pausedAt ?? this.pausedAt),
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

  /// Met la partie en pause — n'importe lequel des deux peut la déclencher,
  /// mais seule cette personne pourra la lever (voir resume(), demande
  /// utilisateur). Bloque flip() pour les deux tant qu'elle est active.
  Future<void> pause();

  /// Lève la pause — réservé à qui l'a posée ; chaque implémentation refuse
  /// silencieusement (no-op) un appel par l'autre plutôt que de planter,
  /// l'UI ne propose de toute façon jamais ce bouton à qui n'a pas le
  /// droit (voir MemoryGameBoardState.pausedByMe).
  Future<void> resume();

  void dispose();
}
