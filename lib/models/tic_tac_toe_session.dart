/// Laravel encode un tableau PHP associatif VIDE (`[]`) en JSON comme un
/// tableau `[]`, pas un objet `{}` — `as Map?` plante net dans ce cas
/// précis (voir MemoryGameSession, où ce piège a été rencontré en premier
/// pour `moves_by_user`) ; durci ici aussi par précaution même si ces
/// champs ne sont en pratique jamais vides (toujours créés avec les deux
/// id du couple, voir TicTacToeController::start).
Map<String, int> _parseIntMap(dynamic value) {
  if (value is Map) {
    return value.map((key, v) => MapEntry(key as String, v as int));
  }
  return const {};
}

/// L'état d'une partie de "Morpion à Deux", mode à distance (voir
/// TicTacToeController) — reçu au démarrage puis à chaque événement temps
/// réel `TicTacToeUpdated` (voir TicTacToeTransport), le client remplace
/// son état local par celui-ci plutôt que de tenter un patch partiel (même
/// principe que MemoryGameSession).
///
/// [board] : 25 cases (grille 5×5), chacune `null` (vide) ou l'id
/// utilisateur qui l'occupe — pas de symbole X/O stocké, l'app choisit
/// l'affichage par joueur côté client (voir _TicTacToeCell). Jeu à SCORE
/// (voir TicTacToeEngine côté backend) : [scoresByUser] compte les
/// alignements de 3 réussis par chacun, victoire au premier à
/// [targetScore] — [isDraw] reste présent pour compatibilité mais ne peut
/// plus jamais valoir `true` avec ces règles (aucun match nul possible).
class TicTacToeSession {
  final String id;
  // Numéro de version serveur (voir HasStateVersion) : 0 = serveur sans versionnement.
  final int version;
  // `null` pour une partie hors-Box (défi à un ami de jeu via son code,
  // voir demande utilisateur) — [playerOneId]/[playerTwoId] portent alors
  // les deux joueurs à la place de box->creator_id/partner_id (même
  // principe que MemoryGameSession).
  final String? boxId;
  final String? playerOneId;
  final String? playerTwoId;
  final String gameId;
  final String? createdBy;
  final List<String?> board;
  final Map<String, int> piecesRemainingByUser;
  final Map<String, int> scoresByUser;
  final int targetScore;
  final String? currentTurnUserId;
  final String? winnerUserId;
  final bool isDraw;
  final int movesCount;
  final bool abandoned;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime? pausedAt;
  final String? pausedByUserId;

  const TicTacToeSession({
    required this.id,
    this.version = 0,
    this.boxId,
    this.playerOneId,
    this.playerTwoId,
    required this.gameId,
    this.createdBy,
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
    this.abandoned = false,
    this.startedAt,
    this.finishedAt,
    this.pausedAt,
    this.pausedByUserId,
  });

  bool get isFinished => finishedAt != null;
  bool get isPaused => pausedAt != null;
  bool get isFriendSession => boxId == null;

  factory TicTacToeSession.fromJson(Map<String, dynamic> json) => TicTacToeSession(
        id: json['id'] as String,
        version: (json['version'] as num?)?.toInt() ?? 0,
        boxId: json['box_id'] as String?,
        playerOneId: json['player_one_id'] as String?,
        playerTwoId: json['player_two_id'] as String?,
        gameId: json['game_id'] as String,
        createdBy: json['created_by'] as String?,
        board: (json['board'] as List? ?? List.filled(25, null)).map((e) => e as String?).toList(),
        piecesRemainingByUser: _parseIntMap(json['pieces_remaining_by_user']),
        scoresByUser: _parseIntMap(json['scores_by_user']),
        targetScore: json['target_score'] as int? ?? 5,
        currentTurnUserId: json['current_turn_user_id'] as String?,
        winnerUserId: json['winner_user_id'] as String?,
        isDraw: json['is_draw'] as bool? ?? false,
        movesCount: json['moves_count'] as int? ?? 0,
        abandoned: json['abandoned'] as bool? ?? false,
        startedAt: json['started_at'] != null ? DateTime.parse(json['started_at'] as String) : null,
        finishedAt: json['finished_at'] != null ? DateTime.parse(json['finished_at'] as String) : null,
        pausedAt: json['paused_at'] != null ? DateTime.parse(json['paused_at'] as String) : null,
        pausedByUserId: json['paused_by_user_id'] as String?,
      );
}

/// Réponse d'un appel `move` (pose ou déplacement) côté à distance — voir
/// TicTacToeController::move. [scoredLine]/[preScatterBoard] sont
/// transitoires (jamais persistés) : renseignés UNIQUEMENT quand CE coup
/// vient de former un alignement (voir TicTacToeEngine::scoreAndScatter
/// côté backend) — voir demande utilisateur sur le highlight avant
/// dispersion.
class TicTacToeMoveApiResult {
  final TicTacToeSession session;
  final List<int>? scoredLine;
  final List<String?>? preScatterBoard;

  const TicTacToeMoveApiResult({
    required this.session,
    this.scoredLine,
    this.preScatterBoard,
  });

  factory TicTacToeMoveApiResult.fromJson(Map<String, dynamic> json) => TicTacToeMoveApiResult(
        session: TicTacToeSession.fromJson(json),
        scoredLine: (json['scored_line'] as List?)?.map((e) => e as int).toList(),
        preScatterBoard: (json['pre_scatter_board'] as List?)?.map((e) => e as String?).toList(),
      );
}

/// Résultat de fin de partie pour une session donnée (voir
/// TicTacToeController::stats) — pas d'agrégat multi-parties, juste CETTE
/// partie (même principe que MemoryGameMatchStats).
class TicTacToeMatchStats {
  final String? winnerUserId;
  final bool isDraw;
  final int movesCount;
  final int? durationSeconds;

  const TicTacToeMatchStats({
    this.winnerUserId,
    this.isDraw = false,
    this.movesCount = 0,
    this.durationSeconds,
  });

  factory TicTacToeMatchStats.fromJson(Map<String, dynamic> json) => TicTacToeMatchStats(
        winnerUserId: json['winner_user_id'] as String?,
        isDraw: json['is_draw'] as bool? ?? false,
        movesCount: json['moves_count'] as int? ?? 0,
        durationSeconds: json['duration_seconds'] as int?,
      );
}
