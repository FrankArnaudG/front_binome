/// État unifié d'une partie de "Chasse aux Chiffres", quel que soit le
/// mode — [NumberHuntBoardScreen] ne connaît que cette forme, jamais les
/// détails de synchronisation sous-jacents (voir NumberHuntTransport),
/// même principe que les 3 autres jeux.
///
/// PAS de tour par tour ici (contrairement aux 3 autres jeux) : pas de
/// `currentTurnUserId`/`isMyTurn`, n'importe lequel des deux peut tenter à
/// tout moment — voir [currentTarget], le seul nombre qui compte.
class NumberHuntBoardState {
  final List<int> board;
  final Map<String, String> found;
  final int? currentTarget;
  final Map<String, int> scoresByUser;
  final String? winnerUserId;
  final bool isTie;
  final int movesCount;
  final bool finished;
  // Distinct d'une fin normale (toutes les cibles trouvées) — voir
  // NumberHuntBoardScreen._onState : seule cette valeur déclenche la
  // pop-up "{partenaire} a mis fin à cette partie" plutôt que le
  // scoreboard habituel (voir demande utilisateur, même principe que
  // MemoryGameBoardState.abandoned).
  final bool abandoned;
  final DateTime? startedAt;
  final String myUserId;
  final String? pausedByUserId;
  final DateTime? pausedAt;

  const NumberHuntBoardState({
    this.board = const [],
    this.found = const {},
    this.currentTarget,
    this.scoresByUser = const {},
    this.winnerUserId,
    this.isTie = false,
    this.movesCount = 0,
    this.finished = false,
    this.abandoned = false,
    this.startedAt,
    required this.myUserId,
    this.pausedByUserId,
    this.pausedAt,
  });

  bool get isPaused => pausedByUserId != null;
  bool get pausedByMe => pausedByUserId == myUserId;
  bool get iWon => winnerUserId == myUserId;

  int scoreFor(String userId) => scoresByUser[userId] ?? 0;

  NumberHuntBoardState copyWith({
    List<int>? board,
    Map<String, String>? found,
    int? currentTarget,
    bool clearTarget = false,
    Map<String, int>? scoresByUser,
    String? winnerUserId,
    bool? isTie,
    int? movesCount,
    bool? finished,
    bool? abandoned,
    DateTime? startedAt,
    String? pausedByUserId,
    DateTime? pausedAt,
    bool clearPause = false,
  }) =>
      NumberHuntBoardState(
        board: board ?? this.board,
        found: found ?? this.found,
        currentTarget: clearTarget ? null : (currentTarget ?? this.currentTarget),
        scoresByUser: scoresByUser ?? this.scoresByUser,
        winnerUserId: winnerUserId ?? this.winnerUserId,
        isTie: isTie ?? this.isTie,
        movesCount: movesCount ?? this.movesCount,
        finished: finished ?? this.finished,
        abandoned: abandoned ?? this.abandoned,
        startedAt: startedAt ?? this.startedAt,
        myUserId: myUserId,
        pausedByUserId: clearPause ? null : (pausedByUserId ?? this.pausedByUserId),
        pausedAt: clearPause ? null : (pausedAt ?? this.pausedAt),
      );
}

/// Abstraction commune aux 3 modes de "Chasse aux Chiffres" — encapsule
/// UNIQUEMENT la façon dont les tentatives sont synchronisées entre les
/// deux joueurs ; la logique de règles elle-même est identique partout
/// (voir NumberHuntEngine côté Dart, ou son pendant PHP pour le mode à
/// distance) — copie structurelle conforme des 3 autres jeux, SAUF
/// [requiresTurnToPlay] qui n'a pas lieu d'être ici (pas de tour par tour).
abstract class NumberHuntTransport {
  Stream<NumberHuntBoardState> get stateStream;

  NumberHuntBoardState get currentState;

  /// Tente [number]. No-op silencieux si ce n'est pas (ou plus) le nombre
  /// cible courant — jamais d'erreur pour une tentative simplement ratée.
  Future<void> attempt(int number);

  Future<void> abandon();

  /// Met la partie en pause — n'importe lequel des deux peut la déclencher,
  /// mais seule cette personne pourra la lever (voir resume()).
  Future<void> pause();

  /// Lève la pause — réservé à qui l'a posée ; chaque implémentation refuse
  /// silencieusement (no-op) un appel par l'autre plutôt que de planter.
  Future<void> resume();

  void dispose();
}
