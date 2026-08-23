/// Une tentative de devinette pour une GameCardSend (voir GameCardGuess
/// côté backend) — réservé aux jeux `session_type = 'quiz'` (voir
/// Game.isQuiz). Copie conforme d'EmojiStoryGuess.
class GameCardGuess {
  final String id;
  final String guess;
  final bool? isCorrect;
  final String? reveal;
  final DateTime? verdictAt;
  final DateTime createdAt;

  const GameCardGuess({
    required this.id,
    required this.guess,
    this.isCorrect,
    this.reveal,
    this.verdictAt,
    required this.createdAt,
  });

  bool get isPending => isCorrect == null;

  factory GameCardGuess.fromJson(Map<String, dynamic> json) => GameCardGuess(
        id: json['id'] as String,
        guess: json['guess'] as String,
        isCorrect: json['is_correct'] as bool?,
        reveal: json['reveal'] as String?,
        verdictAt: json['verdict_at'] != null ? DateTime.parse(json['verdict_at'] as String) : null,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// Une carte-question du jeu "à boîtes" envoyée au/à la partenaire (voir
/// GameCardSend côté backend) — reçue via un envoi (Send.sendableType ==
/// 'game_card'). Peut être une relance ("retourner la question") d'un envoi
/// précédent, voir [bouncedFromId].
///
/// Pour les jeux `session_type = 'quiz'` (voir Game.isQuiz), [answer] reste
/// la toute première réponse (inchangé, partagé avec les jeux classiques)
/// mais [guesses] porte en plus les tentatives suivantes ainsi que le
/// verdict — mêmes getters que EmojiStorySend, pour un rendu identique
/// côté écran de fil de discussion.
class GameCardSend {
  final String id;
  final String gameId;
  final String gameBoxId;
  final String gameBoxQuestionId;
  final Map<String, String> questionText;
  final Map<String, String> gameBoxTitle;
  final String? answer;
  final DateTime? answeredAt;
  final String? bouncedFromId;
  final String? category; // verite | defi | null (jeux "classiques")
  final DateTime? resolvedAt;
  final bool? won;
  final List<GameCardGuess> guesses;
  // "Le Sondage Surprise" (session_type = 'blind_poll') uniquement — voir
  // Game.isBlindPoll. [options] vient de la question (voir
  // GameBoxQuestion.options), dupliqué ici pour ne pas exiger une requête
  // séparée pour afficher les boutons de réponse dans la discussion.
  final String? senderAnswer;
  final List<String> options;
  // "Ai-je le droit ?"/"Sans Détour" uniquement (voir Game.isYesNo/
  // isYesNoOnly) — horodatage de l'invitation lancée par qui a répondu vers
  // qui a envoyé la carte, pour qu'il/elle réponde aussi à LA MÊME
  // question (voir GameCardController::inviteSender/answerAsSender). Une
  // fois [senderAnswer] posé en retour, la révélation réutilise
  // [isPollRevealed] ci-dessous, comme pour "Le Sondage Surprise".
  final DateTime? senderInvitedAt;

  const GameCardSend({
    required this.id,
    required this.gameId,
    required this.gameBoxId,
    required this.gameBoxQuestionId,
    required this.questionText,
    required this.gameBoxTitle,
    this.answer,
    this.answeredAt,
    this.bouncedFromId,
    this.category,
    this.resolvedAt,
    this.won,
    this.guesses = const [],
    this.senderAnswer,
    this.options = const [],
    this.senderInvitedAt,
  });

  bool get isAnswered => answer != null;
  bool get isDefi => category == 'defi';
  bool get isResolved => resolvedAt != null;

  /// Les deux réponses cachées sont réunies — la bulle peut se révéler.
  bool get isPollRevealed => senderAnswer != null && answer != null;

  /// Vrai/fausse pas raccord — n'a de sens qu'une fois révélé.
  bool get pollAligned => senderAnswer != null && senderAnswer == answer;

  /// Le binôme (jamais qui a envoyé, voir sender_answer déjà posé à
  /// l'envoi) doit encore choisir sa réponse cachée.
  bool get needsBlindAnswer => answer == null;

  /// Qui a envoyé la carte a été invité·e à répondre aussi (voir
  /// senderInvitedAt) mais n'a pas encore répondu — affiche le picker
  /// Oui/Non de son côté (voir _pendingSenderAnswerSend côté Flutter).
  bool get needsSenderAnswer => senderInvitedAt != null && senderAnswer == null;

  GameCardGuess? get latestGuess => guesses.isEmpty ? null : guesses.last;

  String questionTextFor(String localeCode) {
    if (questionText.containsKey(localeCode)) return questionText[localeCode]!;
    if (questionText.containsKey('fr')) return questionText['fr']!;
    return questionText.values.isNotEmpty ? questionText.values.first : '';
  }

  String gameBoxTitleFor(String localeCode) {
    if (gameBoxTitle.containsKey(localeCode)) return gameBoxTitle[localeCode]!;
    if (gameBoxTitle.containsKey('fr')) return gameBoxTitle['fr']!;
    return gameBoxTitle.values.isNotEmpty ? gameBoxTitle.values.first : '';
  }

  /// La carte attend une NOUVELLE devinette — soit aucune tentative n'a
  /// encore été faite, soit la dernière a été tranchée (juste ou fausse
  /// avec une nouvelle chance donnée) sans clore la carte.
  bool get needsGuess => !isResolved && (latestGuess == null || latestGuess!.isCorrect != null);

  /// Une devinette vient d'être proposée, pas encore confirmée/infirmée.
  bool get needsVerdict => !isResolved && latestGuess != null && latestGuess!.isPending;

  factory GameCardSend.fromJson(Map<String, dynamic> json) => GameCardSend(
        id: json['id'] as String,
        gameId: json['game_id'] as String,
        gameBoxId: json['game_box_id'] as String,
        gameBoxQuestionId: json['game_box_question_id'] as String,
        questionText: _localeMap(json['question_text']),
        gameBoxTitle: _localeMap(json['game_box_title']),
        answer: json['answer'] as String?,
        answeredAt: json['answered_at'] != null ? DateTime.parse(json['answered_at'] as String) : null,
        bouncedFromId: json['bounced_from_id'] as String?,
        category: json['category'] as String?,
        resolvedAt: json['resolved_at'] != null ? DateTime.parse(json['resolved_at'] as String) : null,
        won: json['won'] as bool?,
        guesses: json['guesses'] != null
            ? (json['guesses'] as List).map((e) => GameCardGuess.fromJson(e as Map<String, dynamic>)).toList()
            : const [],
        senderAnswer: json['sender_answer'] as String?,
        options: json['options'] != null ? (json['options'] as List).map((e) => e as String).toList() : const [],
        senderInvitedAt: json['sender_invited_at'] != null ? DateTime.parse(json['sender_invited_at'] as String) : null,
      );

  static Map<String, String> _localeMap(dynamic value) =>
      (value as Map).map((k, v) => MapEntry(k as String, v as String));
}
