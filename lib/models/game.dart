class Game {
  final String id;
  final Map<String, String> name;
  final Map<String, String>? description;
  final Map<String, String>? rules;
  final String? iconPath;
  final String mode; // remote | in_person | both
  final String status; // active | inactive
  // classic | truth_or_dare | emoji_story | charades | prompt_reveal |
  // timed_challenge | blind_poll
  final String sessionType;
  final int consecutiveChoiceLimit;
  final int challengeSeconds;

  const Game({
    required this.id,
    required this.name,
    this.description,
    this.rules,
    this.iconPath,
    required this.mode,
    required this.status,
    this.sessionType = 'classic',
    this.consecutiveChoiceLimit = 3,
    this.challengeSeconds = 60,
  });

  bool get isTruthOrDare => sessionType == 'truth_or_dare';
  bool get isEmojiStory => sessionType == 'emoji_story';
  bool get isCharades => sessionType == 'charades';
  bool get isPromptReveal => sessionType == 'prompt_reveal';
  bool get isTimedChallenge => sessionType == 'timed_challenge';
  bool get isBlindPoll => sessionType == 'blind_poll';
  bool get isQuiz => sessionType == 'quiz';
  bool get isYesNo => sessionType == 'yes_no';
  // "Sans Détour" — même mécanisme Oui/Non que Game.isYesNo, mais la zone de
  // texte libre classique n'apparaît JAMAIS après (voir
  // GameBoxHistoryScreen._buildComposer) : pas de "pourquoi" invité, la
  // réponse brute est la finalité du jeu.
  bool get isYesNoOnly => sessionType == 'yes_no_only';
  // "Jeu de Mémoire" — plateau de paires partagé, 3 modes (voir
  // MemoryGameModeScreen) ; ni boîtes/prompts ni fil de discussion, un
  // écran dédié entièrement à part (voir GamesMenuScreen._playGame).
  bool get isMemoryGame => sessionType == 'memory_game';

  /// Jeux dont la navigation dépend d'une liste de boîtes/catégories (voir
  /// GamesMenuScreen._playGame) — classic/truth_or_dare/charades/quiz/
  /// blind_poll (voir "Le Sondage Surprise", envoyé et répondu dans la
  /// discussion comme une carte classique depuis sa refonte). Contrairement
  /// aux gabarits à prompt unique restants (prompt_reveal/timed_challenge)
  /// ou à "Devine mon émoji"/"Jeu de Mémoire" (composition libre / écran
  /// dédié), ces jeux ne doivent JAMAIS retomber sur le gabarit générique
  /// GameSessionScreen — un échec de chargement des boîtes y est une vraie
  /// erreur à signaler, pas une raison de rediriger vers un écran obsolète.
  bool get usesBoxes => !isEmojiStory && !isPromptReveal && !isTimedChallenge && !isMemoryGame;

  String nameFor(String localeCode) {
    if (name.containsKey(localeCode)) return name[localeCode]!;
    if (name.containsKey('fr')) return name['fr']!;
    return name.values.isNotEmpty ? name.values.first : '';
  }

  String? descriptionFor(String localeCode) => description?[localeCode] ?? description?['fr'];

  String? rulesFor(String localeCode) => rules?[localeCode] ?? rules?['fr'];

  factory Game.fromJson(Map<String, dynamic> json) => Game(
        id: json['id'] as String,
        name: _localeMap(json['name']),
        description: json['description'] != null ? _localeMap(json['description']) : null,
        rules: json['rules'] != null ? _localeMap(json['rules']) : null,
        iconPath: json['icon_path'] as String?,
        mode: json['mode'] as String,
        status: json['status'] as String,
        sessionType: json['session_type'] as String? ?? 'classic',
        consecutiveChoiceLimit: json['consecutive_choice_limit'] as int? ?? 3,
        challengeSeconds: json['challenge_seconds'] as int? ?? 60,
      );

  static Map<String, String> _localeMap(dynamic value) =>
      (value as Map).map((k, v) => MapEntry(k as String, v as String));
}
