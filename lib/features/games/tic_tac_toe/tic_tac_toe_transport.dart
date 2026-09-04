/// État unifié d'un plateau de "Morpion à Deux", quel que soit le mode —
/// [TicTacToeBoardScreen] ne connaît que cette forme, jamais les détails de
/// synchronisation sous-jacents (voir TicTacToeTransport) — même principe
/// que MemoryGameBoardState.
///
/// Grille 5×5 (25 cases), jeu à SCORE : [piecesRemainingByUser] compte les
/// pions qu'il reste à POSER pour chacun (phase de pose tant que > 0, sinon
/// phase de déplacement) ; [scoresByUser] compte les alignements de 3
/// réussis ; victoire au premier à [targetScore] points, jamais de match nul.
class TicTacToeBoardState {
  final List<String?> board;
  final Map<String, int> piecesRemainingByUser;
  final Map<String, int> scoresByUser;
  final int targetScore;
  final String? currentTurnUserId;
  final String? winnerUserId;
  final bool isDraw;
  final int movesCount;
  final bool finished;
  final DateTime? startedAt;
  final String myUserId;
  // Non-null tant que la partie est en pause — id de qui l'a posée (voir
  // demande utilisateur sur le Jeu de Mémoire, appliqué ici dès le départ :
  // "seul qui a mis la pause peut la lever").
  final String? pausedByUserId;
  // Moment où la pause EN COURS a commencé — sert uniquement à figer le
  // chrono affiché (voir MemoryGameBoardState.pausedAt, même principe).
  final DateTime? pausedAt;
  // Renseignés UNIQUEMENT sur l'état émis juste après un alignement — voir
  // TicTacToeMoveResult, transitoires : ne représentent PAS [board] (déjà
  // dispersé) mais l'instant juste avant, pour que l'écran de jeu affiche
  // l'alignement en surbrillance quelques secondes (voir demande
  // utilisateur) avant de basculer sur [board]. Les états suivants ne les
  // reportent jamais (voir _stateFrom/_applyResult de chaque transport).
  final List<int>? scoredLine;
  final List<String?>? preScatterBoard;

  const TicTacToeBoardState({
    this.board = const [
      null, null, null, null, null,
      null, null, null, null, null,
      null, null, null, null, null,
      null, null, null, null, null,
      null, null, null, null, null,
    ], // 25 cases
    this.piecesRemainingByUser = const {},
    this.scoresByUser = const {},
    this.targetScore = 5,
    this.currentTurnUserId,
    this.winnerUserId,
    this.isDraw = false,
    this.movesCount = 0,
    this.finished = false,
    this.startedAt,
    required this.myUserId,
    this.pausedByUserId,
    this.pausedAt,
    this.scoredLine,
    this.preScatterBoard,
  });

  bool get isMyTurn => currentTurnUserId == myUserId;
  bool get isPaused => pausedByUserId != null;
  bool get pausedByMe => pausedByUserId == myUserId;
  bool get iWon => winnerUserId == myUserId;

  /// Phase de pose pour [userId] tant qu'il lui reste des pièces à poser ;
  /// phase de déplacement sinon.
  bool isPlacementPhaseFor(String userId) => (piecesRemainingByUser[userId] ?? 0) > 0;

  int scoreFor(String userId) => scoresByUser[userId] ?? 0;

  TicTacToeBoardState copyWith({
    List<String?>? board,
    Map<String, int>? piecesRemainingByUser,
    Map<String, int>? scoresByUser,
    int? targetScore,
    String? currentTurnUserId,
    String? winnerUserId,
    bool? isDraw,
    int? movesCount,
    bool? finished,
    DateTime? startedAt,
    String? pausedByUserId,
    DateTime? pausedAt,
    // Distingue "ne pas toucher pausedByUserId/pausedAt" (défaut) de "les
    // remettre à null" (voir resume(), même motif que MemoryGameBoardState).
    bool clearPause = false,
    // Pas de fallback sur `this.x` pour ces deux-là (contrairement aux
    // autres champs) : transitoires par nature, un appel copyWith() qui ne
    // les précise pas doit les remettre à `null`, pas les reporter d'un
    // état à l'autre (voir doc de champ).
    List<int>? scoredLine,
    List<String?>? preScatterBoard,
  }) =>
      TicTacToeBoardState(
        board: board ?? this.board,
        piecesRemainingByUser: piecesRemainingByUser ?? this.piecesRemainingByUser,
        scoresByUser: scoresByUser ?? this.scoresByUser,
        targetScore: targetScore ?? this.targetScore,
        currentTurnUserId: currentTurnUserId ?? this.currentTurnUserId,
        winnerUserId: winnerUserId ?? this.winnerUserId,
        isDraw: isDraw ?? this.isDraw,
        movesCount: movesCount ?? this.movesCount,
        finished: finished ?? this.finished,
        startedAt: startedAt ?? this.startedAt,
        myUserId: myUserId,
        pausedByUserId: clearPause ? null : (pausedByUserId ?? this.pausedByUserId),
        pausedAt: clearPause ? null : (pausedAt ?? this.pausedAt),
        scoredLine: scoredLine,
        preScatterBoard: preScatterBoard,
      );
}

/// Abstraction commune aux 3 modes de "Morpion à Deux" — encapsule
/// UNIQUEMENT la façon dont les coups sont synchronisés entre les deux
/// joueurs (REST+WebSocket à distance, messages P2P en Nearby, état local
/// en pass-and-play) ; la logique de règles elle-même est identique
/// partout (voir TicTacToeEngine côté Dart, ou son pendant PHP pour le
/// mode à distance) — copie structurelle conforme de MemoryGameTransport.
abstract class TicTacToeTransport {
  Stream<TicTacToeBoardState> get stateStream;

  TicTacToeBoardState get currentState;

  /// `false` uniquement pour le pass-and-play (voir
  /// LocalTicTacToeTransport) : les deux partenaires se passent le MÊME
  /// appareil, donc "à qui le tour" n'a de sens que comme indicateur
  /// visuel, jamais comme condition d'accès au plateau.
  bool get requiresTurnToPlay => true;

  /// Pose un nouveau pion sur [position] — réservé à la phase de pose.
  Future<void> place(int position);

  /// Déplace le pion en [from] vers n'importe quelle case vide [to] du
  /// plateau (pas de contrainte d'adjacence) — réservé à la phase de
  /// déplacement.
  Future<void> move(int from, int to);

  Future<void> abandon();

  /// Met la partie en pause — n'importe lequel des deux peut la déclencher,
  /// mais seule cette personne pourra la lever (voir resume()).
  Future<void> pause();

  /// Lève la pause — réservé à qui l'a posée ; chaque implémentation refuse
  /// silencieusement (no-op) un appel par l'autre plutôt que de planter,
  /// l'UI ne propose de toute façon jamais ce bouton à qui n'a pas le
  /// droit (voir TicTacToeBoardState.pausedByMe).
  Future<void> resume();

  void dispose();
}
