/// Une paire déjà trouvée — [indices] vaut `null` pour les parties
/// enregistrées après coup via `recordResult` (présentiel connecté/pass-
/// and-play), où aucun plateau n'a jamais transité par le serveur ; seul
/// [userId] compte alors pour le score (voir MemoryGamePlayerStats).
class MemoryGameMatchedPair {
  final List<int>? indices;
  final String userId;

  const MemoryGameMatchedPair({this.indices, required this.userId});

  factory MemoryGameMatchedPair.fromJson(Map<String, dynamic> json) => MemoryGameMatchedPair(
        indices: json['indices'] != null ? (json['indices'] as List).map((e) => e as int).toList() : null,
        userId: json['user_id'] as String,
      );
}

/// L'état d'une partie de "Jeu de Mémoire", mode à distance (voir
/// MemoryGameController) — reçu au démarrage puis à chaque événement
/// temps réel `MemoryGameUpdated` (voir MemoryGameTransport), le client
/// remplace son état local par celui-ci plutôt que de tenter un patch
/// partiel (même principe que les autres jeux synchronisés de l'app).
///
/// [flipped] ne contient jamais plus d'un élément (voir l'arbitre
/// MemoryGameEngine côté backend, reproduit en Dart pur dans
/// memory_game_engine.dart pour les modes présentiel) — une paire ratée
/// est effacée avant même d'être persistée/diffusée, [mismatch] porte
/// alors la paire éphémère à afficher un instant avant de la recacher.
class MemoryGameSession {
  final String id;
  final String boxId;
  final String gameId;
  final String? createdBy;
  final int pairCount;
  final List<String>? board;
  final List<MemoryGameMatchedPair> matched;
  final List<int> flipped;
  final String? currentTurnUserId;
  final int movesCount;
  final Map<String, int> movesByUser;
  final bool abandoned;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  const MemoryGameSession({
    required this.id,
    required this.boxId,
    required this.gameId,
    this.createdBy,
    required this.pairCount,
    this.board,
    this.matched = const [],
    this.flipped = const [],
    this.currentTurnUserId,
    this.movesCount = 0,
    this.movesByUser = const {},
    this.abandoned = false,
    this.startedAt,
    this.finishedAt,
  });

  bool get isFinished => finishedAt != null;

  Set<int> get matchedIndices => matched
      .expand((pair) => pair.indices ?? const <int>[])
      .toSet();

  factory MemoryGameSession.fromJson(Map<String, dynamic> json) => MemoryGameSession(
        id: json['id'] as String,
        boxId: json['box_id'] as String,
        gameId: json['game_id'] as String,
        createdBy: json['created_by'] as String?,
        pairCount: json['pair_count'] as int,
        board: json['board'] != null ? (json['board'] as List).map((e) => e as String).toList() : null,
        matched: (json['matched'] as List? ?? const [])
            .map((e) => MemoryGameMatchedPair.fromJson(e as Map<String, dynamic>))
            .toList(),
        flipped: (json['flipped'] as List? ?? const []).map((e) => e as int).toList(),
        currentTurnUserId: json['current_turn_user_id'] as String?,
        movesCount: json['moves_count'] as int? ?? 0,
        movesByUser: (json['moves_by_user'] as Map<String, dynamic>? ?? const {})
            .map((key, value) => MapEntry(key, value as int)),
        abandoned: json['abandoned'] as bool? ?? false,
        startedAt: json['started_at'] != null ? DateTime.parse(json['started_at'] as String) : null,
        finishedAt: json['finished_at'] != null ? DateTime.parse(json['finished_at'] as String) : null,
      );
}
