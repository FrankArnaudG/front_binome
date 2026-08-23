/// Une tentative de devinette pour une EmojiStorySend (voir
/// EmojiStoryGuess côté backend) — plusieurs lignes possibles pour la même
/// story si qui l'a composée redonne une chance après une réponse fausse
/// (voir EmojiStorySend.needsGuess), chacune gardant sa propre trace.
class EmojiStoryGuess {
  final String id;
  final String guess;
  final bool? isCorrect;
  final String? reveal;
  final DateTime? verdictAt;
  final DateTime createdAt;

  const EmojiStoryGuess({
    required this.id,
    required this.guess,
    this.isCorrect,
    this.reveal,
    this.verdictAt,
    required this.createdAt,
  });

  bool get isPending => isCorrect == null;

  factory EmojiStoryGuess.fromJson(Map<String, dynamic> json) => EmojiStoryGuess(
        id: json['id'] as String,
        guess: json['guess'] as String,
        isCorrect: json['is_correct'] as bool?,
        reveal: json['reveal'] as String?,
        verdictAt: json['verdict_at'] != null ? DateTime.parse(json['verdict_at'] as String) : null,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// Une "story" en émojis envoyée au/à la partenaire (voir EmojiStorySend
/// côté backend) — reçue via un envoi (Send.sendableType == 'emoji_story').
/// UN SEUL Send porte toute la story du début à la fin : deviner et rendre
/// un verdict ne créent jamais de nouveau Send, seulement de nouvelles
/// tentatives dans [guesses] (voir EmojiStoryController) — la bulle qui
/// porte cette story évolue donc en place au fil des tentatives, jamais
/// remplacée par une nouvelle.
class EmojiStorySend {
  final String id;
  final String gameId;
  final String? sessionId;
  final String emojis;
  final DateTime? editedAt;
  final DateTime? resolvedAt;
  final bool? won;
  final DateTime? deletedAt;
  final List<EmojiStoryGuess> guesses;

  const EmojiStorySend({
    required this.id,
    required this.gameId,
    this.sessionId,
    required this.emojis,
    this.editedAt,
    this.resolvedAt,
    this.won,
    this.deletedAt,
    this.guesses = const [],
  });

  bool get isEdited => editedAt != null;
  bool get isDeleted => deletedAt != null;
  bool get isResolved => resolvedAt != null;

  EmojiStoryGuess? get latestGuess => guesses.isEmpty ? null : guesses.last;

  /// La story attend une NOUVELLE devinette — soit aucune tentative n'a
  /// encore été faite, soit la dernière a été tranchée (juste ou fausse
  /// avec une nouvelle chance donnée) sans clore la story.
  bool get needsGuess => !isResolved && (latestGuess == null || latestGuess!.isCorrect != null);

  /// Une devinette vient d'être proposée, pas encore confirmée/infirmée.
  bool get needsVerdict => !isResolved && latestGuess != null && latestGuess!.isPending;

  factory EmojiStorySend.fromJson(Map<String, dynamic> json) => EmojiStorySend(
        id: json['id'] as String,
        gameId: json['game_id'] as String,
        sessionId: json['emoji_story_session_id'] as String?,
        emojis: json['emojis'] as String,
        editedAt: json['edited_at'] != null ? DateTime.parse(json['edited_at'] as String) : null,
        resolvedAt: json['resolved_at'] != null ? DateTime.parse(json['resolved_at'] as String) : null,
        won: json['won'] as bool?,
        deletedAt: json['deleted_at'] != null ? DateTime.parse(json['deleted_at'] as String) : null,
        guesses: json['guesses'] != null
            ? (json['guesses'] as List).map((e) => EmojiStoryGuess.fromJson(e as Map<String, dynamic>)).toList()
            : const [],
      );
}
