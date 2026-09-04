import '../../../models/battleship_session.dart';

/// État unifié d'une partie de "Bataille Navale", quel que soit le mode —
/// [BattleshipBoardScreen] ne connaît que cette forme, jamais les
/// détails de synchronisation sous-jacents (voir BattleshipTransport).
///
/// DÉJÀ FILTRÉE pour [myUserId] — [myFleet] est TOUJOURS SA PROPRE
/// flotte, [opponentSunkShips] ne contient QUE les bateaux adverses
/// entièrement coulés. Aucune implémentation de [BattleshipTransport] ne
/// doit jamais construire un état qui exposerait la disposition d'un
/// bateau adverse encore vivant — c'est LA règle de sécurité de ce jeu
/// (voir BattleshipEngine côté PHP, doc de classe).
class BattleshipBoardState {
  final List<BattleshipShip> myFleet;
  final List<BattleshipShot> myShots;
  final List<List<int>> opponentSunkShips;
  final bool myReady;
  final bool opponentReady;
  final bool isBattlePhase;
  final String? currentTurnUserId;
  final String? winnerUserId;
  final int movesCount;
  final bool finished;
  final DateTime? startedAt;
  final String myUserId;
  final String opponentUserId;
  final String? pausedByUserId;
  final DateTime? pausedAt;

  const BattleshipBoardState({
    this.myFleet = const [],
    this.myShots = const [],
    this.opponentSunkShips = const [],
    this.myReady = false,
    this.opponentReady = false,
    this.isBattlePhase = false,
    this.currentTurnUserId,
    this.winnerUserId,
    this.movesCount = 0,
    this.finished = false,
    this.startedAt,
    required this.myUserId,
    required this.opponentUserId,
    this.pausedByUserId,
    this.pausedAt,
  });

  bool get isMyTurn => currentTurnUserId == myUserId;
  bool get isPaused => pausedByUserId != null;
  bool get pausedByMe => pausedByUserId == myUserId;
  bool get iWon => winnerUserId == myUserId;

  /// Cases de MA grille déjà touchées par l'adversaire — dérivé de
  /// [myFleet] (chaque bateau porte ses propres `hits`), pratique pour le
  /// rendu de ma propre grille sans reparcourir les bateaux à chaque fois.
  Set<int> get myHitCells => {for (final ship in myFleet) ...ship.hits};

  BattleshipBoardState copyWith({
    List<BattleshipShip>? myFleet,
    List<BattleshipShot>? myShots,
    List<List<int>>? opponentSunkShips,
    bool? myReady,
    bool? opponentReady,
    bool? isBattlePhase,
    String? currentTurnUserId,
    String? winnerUserId,
    int? movesCount,
    bool? finished,
    DateTime? startedAt,
    String? pausedByUserId,
    DateTime? pausedAt,
    bool clearPause = false,
  }) =>
      BattleshipBoardState(
        myFleet: myFleet ?? this.myFleet,
        myShots: myShots ?? this.myShots,
        opponentSunkShips: opponentSunkShips ?? this.opponentSunkShips,
        myReady: myReady ?? this.myReady,
        opponentReady: opponentReady ?? this.opponentReady,
        isBattlePhase: isBattlePhase ?? this.isBattlePhase,
        currentTurnUserId: currentTurnUserId ?? this.currentTurnUserId,
        winnerUserId: winnerUserId ?? this.winnerUserId,
        movesCount: movesCount ?? this.movesCount,
        finished: finished ?? this.finished,
        startedAt: startedAt ?? this.startedAt,
        myUserId: myUserId,
        opponentUserId: opponentUserId,
        pausedByUserId: clearPause ? null : (pausedByUserId ?? this.pausedByUserId),
        pausedAt: clearPause ? null : (pausedAt ?? this.pausedAt),
      );
}

/// Abstraction commune aux 3 modes de "Bataille Navale" — encapsule
/// UNIQUEMENT la façon dont les coups sont synchronisés entre les deux
/// joueurs ; la logique de règles elle-même est identique partout (voir
/// BattleshipEngine côté Dart, ou son pendant PHP pour le mode à
/// distance).
abstract class BattleshipTransport {
  Stream<BattleshipBoardState> get stateStream;

  BattleshipBoardState get currentState;

  /// Place sa flotte — voir BattleshipEngine.validateFleet pour les
  /// règles. Lève une [ArgumentError] si la flotte est invalide.
  Future<void> submitFleet(List<BattleshipShip> ships);

  /// Tire sur [cell] de la grille adverse.
  Future<void> fire(int cell);

  Future<void> abandon();

  Future<void> pause();

  Future<void> resume();

  void dispose();
}
