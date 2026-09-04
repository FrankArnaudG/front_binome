/// Laravel encode un tableau PHP associatif VIDE (`[]`) en JSON comme un
/// tableau `[]`, pas un objet `{}` — `as Map?` plante net dans ce cas
/// précis (voir MemoryGameSession, où ce piège a été rencontré en premier
/// pour `moves_by_user`) ; durci ici aussi par précaution.
Map<String, int> _parseIntMap(dynamic value) {
  if (value is Map) {
    return value.map((key, v) => MapEntry(key as String, v as int));
  }
  return const {};
}

/// L'état d'une partie de "Chasse aux Chiffres", mode à distance (voir
/// NumberHuntController) — reçu au démarrage puis à chaque événement temps
/// réel `NumberHuntUpdated`, le client remplace son état local par
/// celui-ci plutôt que de tenter un patch partiel (même principe que les
/// 3 autres jeux).
///
/// [board] : 100 cases FIXES pour toute la partie, chacune un nombre
/// 1..100 (jamais rebattu, voir demande utilisateur). [found] : nombre
/// (en clé) → id utilisateur qui l'a trouvé. [currentTarget] : le nombre
/// à chercher MAINTENANT — `null` seulement une fois la partie terminée.
/// PAS de tour par tour (contrairement aux 3 autres jeux) : n'importe
/// lequel des deux peut tenter à tout moment.
class NumberHuntSession {
  final String id;
  final String boxId;
  final String gameId;
  final String? createdBy;
  final List<int>? board;
  final int cellCount;
  final Map<String, String> found;
  final int? currentTarget;
  final Map<String, int> scoresByUser;
  final String? winnerUserId;
  final bool isTie;
  final int movesCount;
  final bool abandoned;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime? pausedAt;
  final String? pausedByUserId;

  const NumberHuntSession({
    required this.id,
    required this.boxId,
    required this.gameId,
    this.createdBy,
    this.board,
    this.cellCount = 100,
    this.found = const {},
    this.currentTarget,
    this.scoresByUser = const {},
    this.winnerUserId,
    this.isTie = false,
    this.movesCount = 0,
    this.abandoned = false,
    this.startedAt,
    this.finishedAt,
    this.pausedAt,
    this.pausedByUserId,
  });

  bool get isFinished => finishedAt != null;
  bool get isPaused => pausedAt != null;

  factory NumberHuntSession.fromJson(Map<String, dynamic> json) => NumberHuntSession(
        id: json['id'] as String,
        boxId: json['box_id'] as String,
        gameId: json['game_id'] as String,
        createdBy: json['created_by'] as String?,
        board: (json['board'] as List?)?.map((e) => e as int).toList(),
        cellCount: json['cell_count'] as int? ?? 100,
        found: (json['found'] is Map)
            ? (json['found'] as Map).map((k, v) => MapEntry(k as String, v as String))
            : const {},
        currentTarget: json['current_target'] as int?,
        scoresByUser: _parseIntMap(json['scores_by_user']),
        winnerUserId: json['winner_user_id'] as String?,
        isTie: json['is_tie'] as bool? ?? false,
        movesCount: json['moves_count'] as int? ?? 0,
        abandoned: json['abandoned'] as bool? ?? false,
        startedAt: json['started_at'] != null ? DateTime.parse(json['started_at'] as String) : null,
        finishedAt: json['finished_at'] != null ? DateTime.parse(json['finished_at'] as String) : null,
        pausedAt: json['paused_at'] != null ? DateTime.parse(json['paused_at'] as String) : null,
        pausedByUserId: json['paused_by_user_id'] as String?,
      );
}

/// Réponse d'un appel `attempt` côté à distance — [wasCorrect] indique si
/// CE tirage a été le bon (voir NumberHuntController::attempt) ; permet à
/// l'appelant de savoir si SA tentative a effectivement marqué le point
/// (utile en cas de quasi-égalité avec le binôme).
class NumberHuntAttemptResult {
  final NumberHuntSession session;
  final bool wasCorrect;

  const NumberHuntAttemptResult({required this.session, required this.wasCorrect});

  factory NumberHuntAttemptResult.fromJson(Map<String, dynamic> json) => NumberHuntAttemptResult(
        session: NumberHuntSession.fromJson(json),
        wasCorrect: json['was_correct'] as bool? ?? false,
      );
}

/// Résultat de fin de partie pour une session donnée (voir
/// NumberHuntController::stats).
class NumberHuntMatchStats {
  final String? winnerUserId;
  final bool isTie;
  final Map<String, int> scoresByUser;
  final int movesCount;
  final int? durationSeconds;

  const NumberHuntMatchStats({
    this.winnerUserId,
    this.isTie = false,
    this.scoresByUser = const {},
    this.movesCount = 0,
    this.durationSeconds,
  });

  factory NumberHuntMatchStats.fromJson(Map<String, dynamic> json) => NumberHuntMatchStats(
        winnerUserId: json['winner_user_id'] as String?,
        isTie: json['is_tie'] as bool? ?? false,
        scoresByUser: _parseIntMap(json['scores_by_user']),
        movesCount: json['moves_count'] as int? ?? 0,
        durationSeconds: json['duration_seconds'] as int?,
      );
}
