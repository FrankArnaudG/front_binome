class Game {
  final String id;
  final Map<String, String> name;
  final Map<String, String>? description;
  final Map<String, String>? rules;
  final String? iconPath;
  // Réglables depuis l'espace admin, sans effet hors type "Vérité ou Défi"
  // (voir truth_or_dare_session_screen.dart, _CategoryTile) — remplacent
  // l'icône/couleur fixes des deux tuiles de choix quand renseignées.
  final String? truthImagePath;
  final String? dareImagePath;
  // Si faux, l'image (quand renseignée) reste sur la tuile de choix mais
  // n'apparaît PAS dans l'éventail de sélection des cartes (voir
  // _CategoryCardFace).
  final bool truthImageInFan;
  final bool dareImageInFan;
  final String mode; // remote | in_person | both
  final String status; // active | inactive
  // classic | truth_or_dare | emoji_story | charades | prompt_reveal |
  // timed_challenge | blind_poll
  final String sessionType;
  // 'interactive' (les 8 mini-jeux à état partagé, joués en temps réel à
  // deux) ou 'classic' (boîtes à cartes/prompts) — voir GamesMenuScreen,
  // deux sections séparées dans le catalogue.
  final String category;
  final int consecutiveChoiceLimit;
  final int challengeSeconds;

  const Game({
    required this.id,
    required this.name,
    this.description,
    this.rules,
    this.iconPath,
    this.truthImagePath,
    this.dareImagePath,
    this.truthImageInFan = true,
    this.dareImageInFan = true,
    required this.mode,
    required this.status,
    this.sessionType = 'classic',
    this.category = 'classic',
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
  // "Morpion à Deux" — plateau 3x3 partagé, mêmes 3 modes que
  // isMemoryGame (voir TicTacToeModeScreen), écran dédié entièrement à
  // part lui aussi.
  bool get isTicTacToe => sessionType == 'tic_tac_toe';
  // "Le Jeu des Carrés" — grande feuille de points partagée, mêmes 3 modes
  // que isMemoryGame/isTicTacToe (voir DotSquaresModeScreen), écran dédié
  // entièrement à part lui aussi.
  bool get isDotSquares => sessionType == 'dot_squares';
  bool get isNumberHunt => sessionType == 'number_hunt';
  bool get isWarCard => sessionType == 'war_card';
  bool get isSuitBattle => sessionType == 'suit_battle';
  bool get isBattleship => sessionType == 'battleship';

  bool get isInteractiveCategory => category == 'interactive';

  /// Jeux dont la navigation dépend d'une liste de boîtes/catégories (voir
  /// GamesMenuScreen._playGame) — classic/truth_or_dare/charades/quiz/
  /// blind_poll (voir "Le Sondage Surprise", envoyé et répondu dans la
  /// discussion comme une carte classique depuis sa refonte). Contrairement
  /// aux gabarits à prompt unique restants (prompt_reveal/timed_challenge)
  /// ou à "Devine mon émoji"/"Jeu de Mémoire"/"Morpion à Deux"/"Le Jeu des
  /// Carrés" (composition libre / écran dédié), ces jeux ne doivent JAMAIS
  /// retomber sur le gabarit générique GameSessionScreen — un échec de
  /// chargement des boîtes y est une vraie erreur à signaler, pas une
  /// raison de rediriger vers un écran obsolète.
  bool get usesBoxes =>
      !isEmojiStory &&
      !isPromptReveal &&
      !isTimedChallenge &&
      !isMemoryGame &&
      !isTicTacToe &&
      !isDotSquares &&
      !isNumberHunt &&
      !isWarCard &&
      !isSuitBattle &&
      !isBattleship;

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
        truthImagePath: json['truth_image_path'] as String?,
        dareImagePath: json['dare_image_path'] as String?,
        truthImageInFan: json['truth_image_in_fan'] as bool? ?? true,
        dareImageInFan: json['dare_image_in_fan'] as bool? ?? true,
        mode: json['mode'] as String,
        status: json['status'] as String,
        sessionType: json['session_type'] as String? ?? 'classic',
        category: json['category'] as String? ?? 'classic',
        consecutiveChoiceLimit: json['consecutive_choice_limit'] as int? ?? 3,
        challengeSeconds: json['challenge_seconds'] as int? ?? 60,
      );

  static Map<String, String> _localeMap(dynamic value) =>
      (value as Map).map((k, v) => MapEntry(k as String, v as String));
}
