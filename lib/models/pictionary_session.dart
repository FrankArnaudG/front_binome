/// Un segment de trait dessiné — voir [PictionarySession.strokes].
class PictionaryStroke {
  final List<List<double>> points;
  final String color;
  final double width;

  const PictionaryStroke({required this.points, required this.color, required this.width});

  factory PictionaryStroke.fromJson(Map<String, dynamic> json) => PictionaryStroke(
        points: (json['points'] as List).map((p) => (p as List).map((e) => (e as num).toDouble()).toList()).toList(),
        color: json['color'] as String,
        width: (json['width'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'points': points, 'color': color, 'width': width};
}

/// L'état d'une partie de "Pictionary à deux", mode à distance (voir
/// PictionaryController) — DEUXIÈME jeu de ce projet à état
/// partiellement caché (voir BattleshipSession pour le premier) : [word]
/// n'est renseigné QUE si [isDrawer] est vrai — le serveur ne l'envoie
/// jamais à celui qui devine (voir PictionaryEngine::toPublicArrayFor).
class PictionarySession {
  final String id;
  final String boxId;
  final String gameId;
  final String? createdBy;
  final bool isDrawer;
  final String? word;
  final List<PictionaryStroke> strokes;
  final Map<String, int> scoresByUser;
  final int targetScore;
  final int roundNumber;
  final DateTime? roundStartedAt;
  final int roundSeconds;
  final String? currentDrawerUserId;
  final String? winnerUserId;
  final int movesCount;
  final bool abandoned;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime? pausedAt;
  final String? pausedByUserId;

  const PictionarySession({
    required this.id,
    required this.boxId,
    required this.gameId,
    this.createdBy,
    this.isDrawer = false,
    this.word,
    this.strokes = const [],
    this.scoresByUser = const {},
    this.targetScore = 5,
    this.roundNumber = 0,
    this.roundStartedAt,
    this.roundSeconds = 70,
    this.currentDrawerUserId,
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

  factory PictionarySession.fromJson(Map<String, dynamic> json) => PictionarySession(
        id: json['id'] as String,
        boxId: json['box_id'] as String,
        gameId: json['game_id'] as String,
        createdBy: json['created_by'] as String?,
        isDrawer: json['is_drawer'] as bool? ?? false,
        word: json['word'] as String?,
        strokes: (json['strokes'] as List?)?.map((e) => PictionaryStroke.fromJson(e as Map<String, dynamic>)).toList() ?? const [],
        scoresByUser: (json['scores_by_user'] is Map)
            ? (json['scores_by_user'] as Map).map((k, v) => MapEntry(k as String, v as int))
            : const {},
        targetScore: json['target_score'] as int? ?? 5,
        roundNumber: json['round_number'] as int? ?? 0,
        roundStartedAt: json['round_started_at'] != null ? DateTime.parse(json['round_started_at'] as String) : null,
        roundSeconds: json['round_seconds'] as int? ?? 70,
        currentDrawerUserId: json['current_drawer_user_id'] as String?,
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
/// PictionaryController::stats).
class PictionaryMatchStats {
  final String? winnerUserId;
  final Map<String, int> scoresByUser;
  final int movesCount;
  final int? durationSeconds;

  const PictionaryMatchStats({this.winnerUserId, this.scoresByUser = const {}, this.movesCount = 0, this.durationSeconds});

  factory PictionaryMatchStats.fromJson(Map<String, dynamic> json) => PictionaryMatchStats(
        winnerUserId: json['winner_user_id'] as String?,
        scoresByUser: (json['scores_by_user'] is Map)
            ? (json['scores_by_user'] as Map).map((k, v) => MapEntry(k as String, v as int))
            : const {},
        movesCount: json['moves_count'] as int? ?? 0,
        durationSeconds: json['duration_seconds'] as int?,
      );
}
