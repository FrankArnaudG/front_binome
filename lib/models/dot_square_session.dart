/// Laravel encode un tableau PHP associatif VIDE (`[]`) en JSON comme un
/// tableau `[]`, pas un objet `{}` — `as Map?` plante net dans ce cas
/// précis (voir MemoryGameSession, où ce piège a été rencontré en premier
/// pour `moves_by_user`) ; durci ici aussi par précaution même si
/// `scores_by_user` n'est en pratique jamais vide (toujours créé avec les
/// deux id du couple, voir DotSquaresController::start).
Map<String, int> _parseIntMap(dynamic value) {
  if (value is Map) {
    return value.map((key, v) => MapEntry(key as String, v as int));
  }
  return const {};
}

/// Un rectangle marqué — 4 coins de la même couleur ([ownerUserId]), tracé
/// et numéroté dès qu'il est formé (voir DotSquaresEngine côté backend/
/// dot_squares_engine.dart côté Dart). [r1]/[c1]/[r2]/[c2] : coin
/// haut-gauche et bas-droit (toujours `r1<=r2`, `c1<=c2`).
class DotSquareRectangle {
  final int number;
  final String ownerUserId;
  final int r1;
  final int c1;
  final int r2;
  final int c2;

  const DotSquareRectangle({
    required this.number,
    required this.ownerUserId,
    required this.r1,
    required this.c1,
    required this.r2,
    required this.c2,
  });

  factory DotSquareRectangle.fromJson(Map<String, dynamic> json) => DotSquareRectangle(
        number: json['number'] as int,
        ownerUserId: json['ownerUserId'] as String? ?? json['owner_user_id'] as String,
        r1: json['r1'] as int,
        c1: json['c1'] as int,
        r2: json['r2'] as int,
        c2: json['c2'] as int,
      );

  Map<String, dynamic> toJson() => {
        'number': number,
        'owner_user_id': ownerUserId,
        'r1': r1,
        'c1': c1,
        'r2': r2,
        'c2': c2,
      };
}

/// L'état d'une partie de "Le Jeu des Carrés", mode à distance (voir
/// DotSquaresController) — reçu au démarrage puis à chaque événement temps
/// réel `DotSquaresUpdated`, le client remplace son état local par
/// celui-ci plutôt que de tenter un patch partiel (même principe que
/// TicTacToeSession/MemoryGameSession).
///
/// [points] : [gridRows]×[gridCols] cases, chacune `null` (vide) ou l'id
/// utilisateur qui y a posé son point — jamais retiré (contrairement au
/// Morpion). [isTie] : contrairement aux autres jeux, une égalité est
/// possible en fin de partie (pas de gagnant net).
class DotSquareSession {
  final String id;
  // `null` pour une partie hors-Box (défi à un ami de jeu via son code,
  // voir demande utilisateur) — [playerOneId]/[playerTwoId] portent alors
  // les deux joueurs à la place de box->creator_id/partner_id (même
  // principe que TicTacToeSession).
  final String? boxId;
  final String? playerOneId;
  final String? playerTwoId;
  final String gameId;
  final String? createdBy;
  final int gridRows;
  final int gridCols;
  final List<String?>? points;
  final List<DotSquareRectangle> rectangles;
  // Décompte final, conservé même une fois `rectangles` vidé côté serveur
  // en fin de partie (voir demande utilisateur : le détail du tracé n'a
  // aucun intérêt à être conservé, mais le nombre de rectangles si — voir
  // DotSquaresController::clearDetailIfFinished). Source de vérité pour
  // l'historique (dot_squares_history_screen.dart) ; pendant une partie EN
  // COURS, `rectangles.length` reste équivalent puisque rien n'a encore
  // été vidé.
  final int rectanglesCount;
  final Map<String, int> scoresByUser;
  final String? currentTurnUserId;
  final String? winnerUserId;
  final bool isTie;
  final int movesCount;
  final bool abandoned;
  final String? closeRequestedByUserId;
  final bool closedEarly;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime? pausedAt;
  final String? pausedByUserId;

  const DotSquareSession({
    required this.id,
    this.boxId,
    this.playerOneId,
    this.playerTwoId,
    required this.gameId,
    this.createdBy,
    this.gridRows = 20,
    this.gridCols = 15,
    this.points,
    this.rectangles = const [],
    this.rectanglesCount = 0,
    this.scoresByUser = const {},
    this.currentTurnUserId,
    this.winnerUserId,
    this.isTie = false,
    this.movesCount = 0,
    this.abandoned = false,
    this.closeRequestedByUserId,
    this.closedEarly = false,
    this.startedAt,
    this.finishedAt,
    this.pausedAt,
    this.pausedByUserId,
  });

  bool get isFinished => finishedAt != null;
  bool get isPaused => pausedAt != null;
  bool get isFriendSession => boxId == null;

  factory DotSquareSession.fromJson(Map<String, dynamic> json) {
    final rectangles = (json['rectangles'] as List? ?? [])
        .map((e) => DotSquareRectangle.fromJson(e as Map<String, dynamic>))
        .toList();

    return DotSquareSession(
        id: json['id'] as String,
        boxId: json['box_id'] as String?,
        playerOneId: json['player_one_id'] as String?,
        playerTwoId: json['player_two_id'] as String?,
        gameId: json['game_id'] as String,
        createdBy: json['created_by'] as String?,
        gridRows: json['grid_rows'] as int? ?? 20,
        gridCols: json['grid_cols'] as int? ?? 15,
        points: (json['points'] as List?)?.map((e) => e as String?).toList(),
        rectangles: rectangles,
        // Absent (anciennes réponses en cache) → retombe sur la taille de
        // `rectangles` reçue, correcte tant que le backend ne l'a pas vidé.
        rectanglesCount: json['rectangles_count'] as int? ?? rectangles.length,
        scoresByUser: _parseIntMap(json['scores_by_user']),
        currentTurnUserId: json['current_turn_user_id'] as String?,
        winnerUserId: json['winner_user_id'] as String?,
        isTie: json['is_tie'] as bool? ?? false,
        movesCount: json['moves_count'] as int? ?? 0,
        abandoned: json['abandoned'] as bool? ?? false,
        closeRequestedByUserId: json['close_requested_by_user_id'] as String?,
        closedEarly: json['closed_early'] as bool? ?? false,
        startedAt: json['started_at'] != null ? DateTime.parse(json['started_at'] as String) : null,
        finishedAt: json['finished_at'] != null ? DateTime.parse(json['finished_at'] as String) : null,
        pausedAt: json['paused_at'] != null ? DateTime.parse(json['paused_at'] as String) : null,
        pausedByUserId: json['paused_by_user_id'] as String?,
      );
  }
}

/// Résultat de fin de partie pour une session donnée (voir
/// DotSquaresController::stats) — pas d'agrégat multi-parties (voir
/// DotSquareHistoryPage pour ça), juste CETTE feuille.
class DotSquareMatchStats {
  final String? winnerUserId;
  final bool isTie;
  final Map<String, int> scoresByUser;
  final int movesCount;
  final int? durationSeconds;
  final bool closedEarly;

  const DotSquareMatchStats({
    this.winnerUserId,
    this.isTie = false,
    this.scoresByUser = const {},
    this.movesCount = 0,
    this.durationSeconds,
    this.closedEarly = false,
  });

  factory DotSquareMatchStats.fromJson(Map<String, dynamic> json) => DotSquareMatchStats(
        winnerUserId: json['winner_user_id'] as String?,
        isTie: json['is_tie'] as bool? ?? false,
        scoresByUser: _parseIntMap(json['scores_by_user']),
        movesCount: json['moves_count'] as int? ?? 0,
        durationSeconds: json['duration_seconds'] as int?,
        closedEarly: json['closed_early'] as bool? ?? false,
      );
}

/// Une page de l'historique des feuilles terminées (voir
/// DotSquaresController::index) — demande utilisateur : "ajouter un
/// historique pour conserver chaque feuille avec ces statistiques".
class DotSquareHistoryPage {
  final List<DotSquareSession> items;
  final bool hasMore;

  const DotSquareHistoryPage({required this.items, required this.hasMore});

  factory DotSquareHistoryPage.fromJson(Map<String, dynamic> json) => DotSquareHistoryPage(
        items: (json['items'] as List).map((e) => DotSquareSession.fromJson(e as Map<String, dynamic>)).toList(),
        hasMore: json['has_more'] as bool? ?? false,
      );
}
