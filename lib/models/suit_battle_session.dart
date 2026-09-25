/// L'état d'une partie de "Jeu de Carte Classique", mode à distance (voir
/// SuitBattleController) — reçu au démarrage puis à chaque événement temps
/// réel `SuitBattleUpdated`, le client remplace son état local par celui-ci
/// plutôt que de tenter un patch partiel (même principe que les autres
/// jeux).
///
/// QUATRIÈME pattern de synchronisation de ce projet (voir WarCardSession
/// pour le troisième) : tour par tour classique (`turnUserId`), mais avec
/// un sous-état explicite [phase] ('lead' ou 'response') — chaque échange
/// se joue en deux temps distincts plutôt qu'un simple coup unique.
class SuitBattleSession {
  final String id;
  // Numéro de version serveur (voir HasStateVersion) : 0 = serveur sans versionnement.
  final int version;
  // `null` pour une partie hors-Box (défi à un ami de jeu via son code,
  // voir demande utilisateur) — [playerOneId]/[playerTwoId] portent alors
  // les deux joueurs à la place de box->creator_id/partner_id (même
  // principe que TicTacToeSession).
  final String? boxId;
  final String? playerOneId;
  final String? playerTwoId;
  final String gameId;
  final String? createdBy;
  final List<String> deck;
  final bool dealt;
  final bool readyCreator;
  final bool readyPartner;
  final bool started;
  final List<String>? spreadCreator;
  final List<String>? spreadPartner;
  final List<String> wonCreator;
  final List<String> wonPartner;
  final String? tableCard;
  final String? tableOwnerUserId;
  final String? responseCard;
  final String? pendingRoundWinnerId;
  final String? turnUserId;
  final String? phase;
  final int roundsCount;
  final String? winnerUserId;
  final bool isTie;
  final bool abandoned;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime? pausedAt;
  final String? pausedByUserId;

  const SuitBattleSession({
    required this.id,
    this.version = 0,
    this.boxId,
    this.playerOneId,
    this.playerTwoId,
    required this.gameId,
    this.createdBy,
    this.deck = const [],
    this.dealt = true,
    this.readyCreator = false,
    this.readyPartner = false,
    this.started = true,
    this.spreadCreator,
    this.spreadPartner,
    this.wonCreator = const [],
    this.wonPartner = const [],
    this.tableCard,
    this.tableOwnerUserId,
    this.responseCard,
    this.pendingRoundWinnerId,
    this.turnUserId,
    this.phase,
    this.roundsCount = 0,
    this.winnerUserId,
    this.isTie = false,
    this.abandoned = false,
    this.startedAt,
    this.finishedAt,
    this.pausedAt,
    this.pausedByUserId,
  });

  bool get isFinished => finishedAt != null;
  bool get isPaused => pausedAt != null;
  bool get isFriendSession => boxId == null;

  factory SuitBattleSession.fromJson(Map<String, dynamic> json) => SuitBattleSession(
        id: json['id'] as String,
        version: (json['version'] as num?)?.toInt() ?? 0,
        boxId: json['box_id'] as String?,
        playerOneId: json['player_one_id'] as String?,
        playerTwoId: json['player_two_id'] as String?,
        gameId: json['game_id'] as String,
        createdBy: json['created_by'] as String?,
        deck: (json['deck'] as List?)?.map((e) => e as String).toList() ?? const [],
        dealt: json['dealt'] as bool? ?? true,
        readyCreator: json['ready_creator'] as bool? ?? false,
        readyPartner: json['ready_partner'] as bool? ?? false,
        started: json['started'] as bool? ?? true,
        spreadCreator: (json['spread_creator'] as List?)?.map((e) => e as String).toList(),
        spreadPartner: (json['spread_partner'] as List?)?.map((e) => e as String).toList(),
        wonCreator: (json['won_creator'] as List?)?.map((e) => e as String).toList() ?? const [],
        wonPartner: (json['won_partner'] as List?)?.map((e) => e as String).toList() ?? const [],
        tableCard: json['table_card'] as String?,
        tableOwnerUserId: json['table_owner_user_id'] as String?,
        responseCard: json['response_card'] as String?,
        pendingRoundWinnerId: json['pending_round_winner_id'] as String?,
        turnUserId: json['turn_user_id'] as String?,
        phase: json['phase'] as String?,
        roundsCount: json['rounds_count'] as int? ?? 0,
        winnerUserId: json['winner_user_id'] as String?,
        isTie: json['is_tie'] as bool? ?? false,
        abandoned: json['abandoned'] as bool? ?? false,
        startedAt: json['started_at'] != null ? DateTime.parse(json['started_at'] as String) : null,
        finishedAt: json['finished_at'] != null ? DateTime.parse(json['finished_at'] as String) : null,
        pausedAt: json['paused_at'] != null ? DateTime.parse(json['paused_at'] as String) : null,
        pausedByUserId: json['paused_by_user_id'] as String?,
      );
}

/// Résultat de fin de partie pour une session donnée (voir
/// SuitBattleController::stats).
class SuitBattleMatchStats {
  final String? winnerUserId;
  final bool isTie;
  final int roundsCount;
  final int? durationSeconds;

  const SuitBattleMatchStats({
    this.winnerUserId,
    this.isTie = false,
    this.roundsCount = 0,
    this.durationSeconds,
  });

  factory SuitBattleMatchStats.fromJson(Map<String, dynamic> json) => SuitBattleMatchStats(
        winnerUserId: json['winner_user_id'] as String?,
        isTie: json['is_tie'] as bool? ?? false,
        roundsCount: json['rounds_count'] as int? ?? 0,
        durationSeconds: json['duration_seconds'] as int?,
      );
}
