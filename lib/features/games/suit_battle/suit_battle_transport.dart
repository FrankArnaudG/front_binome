/// État unifié d'une partie de "Jeu de Carte Classique", quel que soit le
/// mode — [SuitBattleBoardScreen] ne connaît que cette forme, jamais les
/// détails de synchronisation sous-jacents (voir SuitBattleTransport),
/// même principe que les autres jeux.
///
/// QUATRIÈME pattern de synchronisation de ce projet : tour par tour
/// classique ([turnUserId]), mais avec un sous-état explicite [phase]
/// ('lead' ou 'response') — chaque échange se joue en deux temps
/// distincts.
class SuitBattleBoardState {
  final List<String> deck;
  final bool dealt;
  final bool readyCreator;
  final bool readyPartner;
  final bool started;
  final List<String> spreadCreator;
  final List<String> spreadPartner;
  final List<String> wonCreator;
  final List<String> wonPartner;
  final String? tableCard;
  final String? tableOwnerUserId;
  final String? turnUserId;
  final String? phase;
  final int roundsCount;
  final String? winnerUserId;
  final bool isTie;
  final bool finished;
  // Distinct d'une fin normale (main vidée) — voir demande utilisateur,
  // même principe que WarCardBoardState.abandoned.
  final bool abandoned;
  final DateTime? startedAt;
  final String myUserId;
  final String creatorId;
  final String partnerId;
  final String? pausedByUserId;
  final DateTime? pausedAt;

  const SuitBattleBoardState({
    this.deck = const [],
    this.dealt = false,
    this.readyCreator = false,
    this.readyPartner = false,
    this.started = false,
    this.spreadCreator = const [],
    this.spreadPartner = const [],
    this.wonCreator = const [],
    this.wonPartner = const [],
    this.tableCard,
    this.tableOwnerUserId,
    this.turnUserId,
    this.phase,
    this.roundsCount = 0,
    this.winnerUserId,
    this.isTie = false,
    this.finished = false,
    this.abandoned = false,
    this.startedAt,
    required this.myUserId,
    required this.creatorId,
    required this.partnerId,
    this.pausedByUserId,
    this.pausedAt,
  });

  bool get isPaused => pausedByUserId != null;
  bool get pausedByMe => pausedByUserId == myUserId;
  bool get iWon => winnerUserId == myUserId;
  bool get iAmCreator => myUserId == creatorId;

  bool get iAmReady => iAmCreator ? readyCreator : readyPartner;
  bool get partnerIsReady => iAmCreator ? readyPartner : readyCreator;

  bool get isMyTurn => turnUserId == myUserId;

  List<String> get mySpread => iAmCreator ? spreadCreator : spreadPartner;
  List<String> get partnerSpread => iAmCreator ? spreadPartner : spreadCreator;
  List<String> get myWonPile => iAmCreator ? wonCreator : wonPartner;
  List<String> get partnerWonPile => iAmCreator ? wonPartner : wonCreator;

  SuitBattleBoardState copyWith({
    List<String>? deck,
    bool? dealt,
    bool? readyCreator,
    bool? readyPartner,
    bool? started,
    List<String>? spreadCreator,
    List<String>? spreadPartner,
    List<String>? wonCreator,
    List<String>? wonPartner,
    String? tableCard,
    String? tableOwnerUserId,
    String? turnUserId,
    String? phase,
    int? roundsCount,
    String? winnerUserId,
    bool? isTie,
    bool? finished,
    bool? abandoned,
    DateTime? startedAt,
    String? pausedByUserId,
    DateTime? pausedAt,
    bool clearTable = false,
    bool clearPause = false,
  }) =>
      SuitBattleBoardState(
        deck: deck ?? this.deck,
        dealt: dealt ?? this.dealt,
        readyCreator: readyCreator ?? this.readyCreator,
        readyPartner: readyPartner ?? this.readyPartner,
        started: started ?? this.started,
        spreadCreator: spreadCreator ?? this.spreadCreator,
        spreadPartner: spreadPartner ?? this.spreadPartner,
        wonCreator: wonCreator ?? this.wonCreator,
        wonPartner: wonPartner ?? this.wonPartner,
        tableCard: clearTable ? null : (tableCard ?? this.tableCard),
        tableOwnerUserId: clearTable ? null : (tableOwnerUserId ?? this.tableOwnerUserId),
        turnUserId: turnUserId ?? this.turnUserId,
        phase: phase ?? this.phase,
        roundsCount: roundsCount ?? this.roundsCount,
        winnerUserId: winnerUserId ?? this.winnerUserId,
        isTie: isTie ?? this.isTie,
        finished: finished ?? this.finished,
        abandoned: abandoned ?? this.abandoned,
        startedAt: startedAt ?? this.startedAt,
        myUserId: myUserId,
        creatorId: creatorId,
        partnerId: partnerId,
        pausedByUserId: clearPause ? null : (pausedByUserId ?? this.pausedByUserId),
        pausedAt: clearPause ? null : (pausedAt ?? this.pausedAt),
      );
}

/// Abstraction commune aux 2 modes du "Jeu de Carte Classique" — encapsule
/// UNIQUEMENT la façon dont les coups sont synchronisés entre les deux
/// joueurs ; la logique de règles elle-même est identique partout (voir
/// SuitBattleEngine côté Dart, ou son pendant PHP pour le mode à distance)
/// — copie structurelle conforme des autres jeux.
abstract class SuitBattleTransport {
  Stream<SuitBattleBoardState> get stateStream;

  SuitBattleBoardState get currentState;

  /// "Battre" les cartes — n'importe lequel des deux joueurs peut le
  /// déclencher, autant de fois qu'il veut, tant que
  /// [SuitBattleBoardState.dealt] est faux.
  Future<void> shuffleDeck();

  /// Partage automatique et instantané.
  Future<void> dealAutomatic();

  /// "Commencer" — LES DEUX doivent l'appeler avant que
  /// [SuitBattleBoardState.started] ne passe à `true`.
  Future<void> readyUp();

  /// Le meneur pose [card] — devient la carte sur table, phase → réponse.
  Future<void> playLead(String userId, String card);

  /// Le répondant joue [card] (même couleur que la carte sur table, ou un
  /// Joker) — résout l'échange.
  Future<void> respondCard(String userId, String card);

  /// Le répondant capture la carte sur table sans jouer — le meneur
  /// original reprend la main.
  Future<void> captureLead(String userId);

  Future<void> abandon();

  Future<void> pause();

  Future<void> resume();

  void dispose();
}
