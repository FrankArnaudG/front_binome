/// L'état d'une partie de "Puissance 4", mode à distance (voir
/// ConnectFourController) — reçu au démarrage puis à chaque événement
/// temps réel `ConnectFourUpdated`, le client remplace son état local par
/// celui-ci plutôt que de tenter un patch partiel (même principe que les
/// autres jeux).
///
/// Tour par tour classique (voir [currentTurnUserId]) — grille [board]
/// de 42 cases (7 colonnes × 6 lignes), `row` 0 étant la ligne du HAUT
/// (voir ConnectFourEngine côté PHP pour le détail de l'indexation).
class ConnectFourSession {
  final String id;
  final String boxId;
  final String gameId;
  final String? createdBy;
  final List<String?> board;
  final String? currentTurnUserId;
  final int movesCount;
  final String? winnerUserId;
  final bool isTie;
  final bool abandoned;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime? pausedAt;
  final String? pausedByUserId;

  const ConnectFourSession({
    required this.id,
    required this.boxId,
    required this.gameId,
    this.createdBy,
    this.board = const [],
    this.currentTurnUserId,
    this.movesCount = 0,
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

  factory ConnectFourSession.fromJson(Map<String, dynamic> json) => ConnectFourSession(
        id: json['id'] as String,
        boxId: json['box_id'] as String,
        gameId: json['game_id'] as String,
        createdBy: json['created_by'] as String?,
        board: (json['board'] as List?)?.map((e) => e as String?).toList() ?? const [],
        currentTurnUserId: json['current_turn_user_id'] as String?,
        movesCount: json['moves_count'] as int? ?? 0,
        winnerUserId: json['winner_user_id'] as String?,
        isTie: json['is_tie'] as bool? ?? false,
        abandoned: json['abandoned'] as bool? ?? false,
        startedAt: json['started_at'] != null ? DateTime.parse(json['started_at'] as String) : null,
        finishedAt: json['finished_at'] != null ? DateTime.parse(json['finished_at'] as String) : null,
        pausedAt: json['paused_at'] != null ? DateTime.parse(json['paused_at'] as String) : null,
        pausedByUserId: json['paused_by_user_id'] as String?,
      );
}

/// Réponse d'un appel `drop` côté à distance — [winningLine] porte les
/// indices de l'alignement gagnant (pour l'animation côté client),
/// `null` si le coup n'a pas terminé la partie.
class ConnectFourDropResult {
  final ConnectFourSession session;
  final List<int>? winningLine;

  const ConnectFourDropResult({required this.session, this.winningLine});

  factory ConnectFourDropResult.fromJson(Map<String, dynamic> json) => ConnectFourDropResult(
        session: ConnectFourSession.fromJson(json),
        winningLine: (json['winning_line'] as List?)?.map((e) => e as int).toList(),
      );
}

/// Résultat de fin de partie pour une session donnée (voir
/// ConnectFourController::stats).
class ConnectFourMatchStats {
  final String? winnerUserId;
  final bool isTie;
  final int movesCount;
  final int? durationSeconds;

  const ConnectFourMatchStats({
    this.winnerUserId,
    this.isTie = false,
    this.movesCount = 0,
    this.durationSeconds,
  });

  factory ConnectFourMatchStats.fromJson(Map<String, dynamic> json) => ConnectFourMatchStats(
        winnerUserId: json['winner_user_id'] as String?,
        isTie: json['is_tie'] as bool? ?? false,
        movesCount: json['moves_count'] as int? ?? 0,
        durationSeconds: json['duration_seconds'] as int?,
      );
}
