/// Un bateau tel que connu par SON propriétaire (voir [BattleshipSession.myFleet])
/// — `cells` = les 10 cases qu'il occupe, `hits` = celles déjà touchées
/// par l'adversaire.
class BattleshipShip {
  final List<int> cells;
  final List<int> hits;

  const BattleshipShip({required this.cells, this.hits = const []});

  bool get isSunk => hits.toSet().length >= cells.length;

  /// Nouvelle instance avec [cell] ajoutée aux cases touchées — utilisé
  /// par BattleshipEngine.fire (modes présentiel), jamais côté à
  /// distance (le serveur fait déjà autorité).
  BattleshipShip withHit(int cell) => BattleshipShip(cells: cells, hits: [...hits, cell]);

  factory BattleshipShip.fromJson(Map<String, dynamic> json) => BattleshipShip(
        cells: (json['cells'] as List).map((e) => e as int).toList(),
        hits: (json['hits'] as List?)?.map((e) => e as int).toList() ?? const [],
      );

  Map<String, dynamic> toJson() => {'cells': cells, 'hits': hits};
}

/// Un tir déjà effectué PAR ce joueur sur la grille adverse (voir
/// [BattleshipSession.myShots]).
class BattleshipShot {
  final int cell;
  final bool hit;

  const BattleshipShot({required this.cell, required this.hit});

  factory BattleshipShot.fromJson(Map<String, dynamic> json) =>
      BattleshipShot(cell: json['cell'] as int, hit: json['hit'] as bool);
}

/// L'état d'une partie de "Bataille Navale", mode à distance (voir
/// BattleshipController) — CONTRAIREMENT aux autres jeux, cette forme est
/// DÉJÀ FILTRÉE côté serveur (voir BattleshipEngine::toPublicArrayFor) :
/// [myFleet] est TOUJOURS la flotte de CELUI QUI DEMANDE, et
/// [opponentSunkShips] ne contient QUE les bateaux adverses entièrement
/// coulés — jamais la disposition d'un bateau adverse encore vivant. Reçu
/// au démarrage puis à chaque signal temps réel `BattleshipUpdated`
/// (lui-même sans contenu, voir RemoteBattleshipTransport — il ne fait
/// que déclencher un nouvel appel à `state()`).
///
/// [boxId] `null` pour une partie hors-Box (défi à un ami de jeu via son
/// code, voir demande utilisateur) — [playerOneId]/[playerTwoId] portent
/// alors les deux joueurs à la place de box->creator_id/partner_id (même
/// principe que TicTacToeSession).
class BattleshipSession {
  final String id;
  final String? boxId;
  final String? playerOneId;
  final String? playerTwoId;
  final String gameId;
  final String? createdBy;
  final int gridSize;
  final List<BattleshipShip> myFleet;
  final List<BattleshipShot> myShots;
  final List<List<int>> opponentSunkShips;
  final bool myReady;
  final bool opponentReady;
  final bool isBattlePhase;
  final String? currentTurnUserId;
  final String? winnerUserId;
  final int movesCount;
  final bool abandoned;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime? pausedAt;
  final String? pausedByUserId;

  const BattleshipSession({
    required this.id,
    this.boxId,
    this.playerOneId,
    this.playerTwoId,
    required this.gameId,
    this.createdBy,
    this.gridSize = 10,
    this.myFleet = const [],
    this.myShots = const [],
    this.opponentSunkShips = const [],
    this.myReady = false,
    this.opponentReady = false,
    this.isBattlePhase = false,
    this.currentTurnUserId,
    this.winnerUserId,
    this.movesCount = 0,
    this.abandoned = false,
    this.startedAt,
    this.finishedAt,
    this.pausedAt,
    this.pausedByUserId,
  });

  bool get isFinished => finishedAt != null;
  bool get isPaused => pausedAt != null;
  bool get isFriendSession => boxId == null;

  factory BattleshipSession.fromJson(Map<String, dynamic> json) => BattleshipSession(
        id: json['id'] as String,
        boxId: json['box_id'] as String?,
        playerOneId: json['player_one_id'] as String?,
        playerTwoId: json['player_two_id'] as String?,
        gameId: json['game_id'] as String,
        createdBy: json['created_by'] as String?,
        // Défaut 10 pour compatibilité avec un payload en cache ne portant
        // pas encore cette clé (voir migration back-end).
        gridSize: (json['grid_size'] as num?)?.toInt() ?? 10,
        myFleet: (json['my_fleet'] as List?)?.map((e) => BattleshipShip.fromJson(e as Map<String, dynamic>)).toList() ?? const [],
        myShots: (json['my_shots'] as List?)?.map((e) => BattleshipShot.fromJson(e as Map<String, dynamic>)).toList() ?? const [],
        opponentSunkShips:
            (json['opponent_sunk_ships'] as List?)?.map((ship) => (ship as List).map((e) => e as int).toList()).toList() ?? const [],
        myReady: json['my_ready'] as bool? ?? false,
        opponentReady: json['opponent_ready'] as bool? ?? false,
        isBattlePhase: json['is_battle_phase'] as bool? ?? false,
        currentTurnUserId: json['current_turn_user_id'] as String?,
        winnerUserId: json['winner_user_id'] as String?,
        movesCount: json['moves_count'] as int? ?? 0,
        abandoned: json['abandoned'] as bool? ?? false,
        startedAt: json['started_at'] != null ? DateTime.parse(json['started_at'] as String) : null,
        finishedAt: json['finished_at'] != null ? DateTime.parse(json['finished_at'] as String) : null,
        pausedAt: json['paused_at'] != null ? DateTime.parse(json['paused_at'] as String) : null,
        pausedByUserId: json['paused_by_user_id'] as String?,
      );
}

/// Résultat de fin de partie pour une session donnée (voir
/// BattleshipController::stats).
class BattleshipMatchStats {
  final String? winnerUserId;
  final int movesCount;
  final int? durationSeconds;

  const BattleshipMatchStats({this.winnerUserId, this.movesCount = 0, this.durationSeconds});

  factory BattleshipMatchStats.fromJson(Map<String, dynamic> json) => BattleshipMatchStats(
        winnerUserId: json['winner_user_id'] as String?,
        movesCount: json['moves_count'] as int? ?? 0,
        durationSeconds: json['duration_seconds'] as int?,
      );
}
