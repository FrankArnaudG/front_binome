/// État unifié d'une partie de "Bataille", quel que soit le mode —
/// [WarCardBoardScreen] ne connaît que cette forme, jamais les détails de
/// synchronisation sous-jacents (voir WarCardTransport), même principe
/// que les autres jeux.
///
/// TROISIÈME pattern de synchronisation de ce projet : ni tour par tour
/// (`currentTurnUserId`), ni "n'importe qui n'importe quand" (Chasse aux
/// Chiffres), mais [pendingFlipCreator]/[pendingFlipPartner] — les DEUX
/// doivent taper avant qu'une manche ne résolve.
class WarCardBoardState {
  /// Les 52 cartes empilées ENSEMBLE, avant tout partage (voir demande
  /// utilisateur) — `dealt == false` tant qu'il en reste ; `deck[0]` = la
  /// carte du dessus.
  final List<String> deck;
  final bool dealt;
  // "Commencer" (voir demande utilisateur) — une fois [dealt], LES DEUX
  // doivent confirmer avant que [started] ne passe à `true` et que la
  // vraie partie (flip()) ne commence.
  final bool readyCreator;
  final bool readyPartner;
  final bool started;
  final List<String> pileCreator;
  final List<String> pilePartner;
  final bool pendingFlipCreator;
  final bool pendingFlipPartner;
  final List<Map<String, String>> lastRoundResult;
  final int roundsCount;
  final String? winnerUserId;
  final bool isTie;
  final bool finished;
  // Distinct d'une fin normale (paquet remporté en entier) — voir
  // WarCardBoardScreen._onState : seule cette valeur déclenche la pop-up
  // "{partenaire} a mis fin à cette partie" plutôt que le scoreboard
  // habituel (voir demande utilisateur, même principe que
  // MemoryGameBoardState.abandoned).
  final bool abandoned;
  final DateTime? startedAt;
  final String myUserId;
  final String creatorId;
  final String partnerId;
  final String? pausedByUserId;
  final DateTime? pausedAt;

  const WarCardBoardState({
    this.deck = const [],
    this.dealt = false,
    this.readyCreator = false,
    this.readyPartner = false,
    this.started = false,
    this.pileCreator = const [],
    this.pilePartner = const [],
    this.pendingFlipCreator = false,
    this.pendingFlipPartner = false,
    this.lastRoundResult = const [],
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

  /// Dernière carte révélée pour [userId] (voir [lastRoundResult], la
  /// DERNIÈRE manche de la cascade — la finale, celle qui a vraiment
  /// tranché) — `null` si aucune manche n'a encore été jouée.
  String? lastCardFor(String userId) {
    if (lastRoundResult.isEmpty) return null;
    final key = userId == creatorId ? 'creator' : 'partner';
    return lastRoundResult.last[key];
  }

  /// Vrai si la DERNIÈRE manche jouée a comporté une bataille (plus d'un
  /// tirage dans la cascade) — pour afficher "Bataille !" côté client.
  bool get lastRoundWasBattle => lastRoundResult.length > 1;

  WarCardBoardState copyWith({
    List<String>? deck,
    bool? dealt,
    bool? readyCreator,
    bool? readyPartner,
    bool? started,
    List<String>? pileCreator,
    List<String>? pilePartner,
    bool? pendingFlipCreator,
    bool? pendingFlipPartner,
    List<Map<String, String>>? lastRoundResult,
    int? roundsCount,
    String? winnerUserId,
    bool? isTie,
    bool? finished,
    bool? abandoned,
    DateTime? startedAt,
    String? pausedByUserId,
    DateTime? pausedAt,
    bool clearPause = false,
  }) =>
      WarCardBoardState(
        deck: deck ?? this.deck,
        dealt: dealt ?? this.dealt,
        readyCreator: readyCreator ?? this.readyCreator,
        readyPartner: readyPartner ?? this.readyPartner,
        started: started ?? this.started,
        pileCreator: pileCreator ?? this.pileCreator,
        pilePartner: pilePartner ?? this.pilePartner,
        pendingFlipCreator: pendingFlipCreator ?? this.pendingFlipCreator,
        pendingFlipPartner: pendingFlipPartner ?? this.pendingFlipPartner,
        lastRoundResult: lastRoundResult ?? this.lastRoundResult,
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

/// Abstraction commune aux 3 modes de "Bataille" — encapsule UNIQUEMENT
/// la façon dont les taps sont synchronisés entre les deux joueurs ; la
/// logique de règles elle-même est identique partout (voir WarCardEngine
/// côté Dart, ou son pendant PHP pour le mode à distance) — copie
/// structurelle conforme des autres jeux.
abstract class WarCardTransport {
  Stream<WarCardBoardState> get stateStream;

  WarCardBoardState get currentState;

  /// "Battre" les cartes (voir demande utilisateur) — n'importe lequel des
  /// deux joueurs peut le déclencher, autant de fois qu'il veut, tant que
  /// [WarCardBoardState.dealt] est faux.
  Future<void> shuffleDeck();

  /// Partage automatique et instantané.
  Future<void> dealAutomatic();

  /// Partage manuel — UN appel distribue deux cartes (voir
  /// WarCardEngine.dealManualStep) ; répété jusqu'à ce que le paquet soit
  /// vide.
  Future<void> dealManualStep();

  /// "Commencer" (voir demande utilisateur) — en pass-and-play un seul
  /// appel suffit (voir [LocalWarCardTransport], les deux rôles sont sur
  /// le même appareil) ; à distance/présentiel connecté, LES DEUX doivent
  /// l'appeler avant que [WarCardBoardState.started] ne passe à `true`.
  Future<void> readyUp();

  /// [userId] tape "Retourner" — en mode à distance/présentiel connecté,
  /// toujours l'utilisateur de CET appareil ; en pass-and-play, l'un ou
  /// l'autre des deux boutons affichés à l'écran (voir doc de classe :
  /// pas de tour par tour, donc pas moyen de déduire "qui" autrement que
  /// par le bouton physiquement tapé).
  Future<void> flip(String userId);

  /// "Battre" SA PROPRE pile en cours de partie (voir demande
  /// utilisateur) — [userId] toujours celui à qui appartient la pile à
  /// mélanger (même principe que [flip] : en pass-and-play, l'un ou
  /// l'autre selon la pile tapée). Refusé si cette personne a déjà joué
  /// sa carte pour la manche en cours.
  Future<void> shufflePile(String userId);

  Future<void> abandon();

  Future<void> pause();

  Future<void> resume();

  void dispose();
}
