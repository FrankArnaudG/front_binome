import 'dart:math';

/// Résultat d'un flip() — voir WarCardEngine.flip.
class WarCardFlipOutcome {
  final bool resolved;
  final List<String> pileCreator;
  final List<String> pilePartner;
  final bool pendingFlipCreator;
  final bool pendingFlipPartner;
  final List<String> battlePot;
  final int roundsCount;
  final List<Map<String, String>> lastRoundResult;
  final String? winnerUserId;
  final bool isTie;
  final bool finished;
  // Non-null quand une manche vient de se résoudre mais que le pot
  // n'attend plus que d'être ramassé (voir demande utilisateur : "au lieu
  // de ramasser automatiquement, un bouton pour informer" — implique
  // chacun des deux plutôt qu'un ramassage automatique) — `null` si la
  // partie se termine sur cette manche (ramassage immédiat, voir
  // collectPot/_resolveRound, un bouton n'a alors plus de sens juste avant
  // le tableau des scores).
  final String? pendingCollectorId;

  const WarCardFlipOutcome({
    required this.resolved,
    required this.pileCreator,
    required this.pilePartner,
    required this.pendingFlipCreator,
    required this.pendingFlipPartner,
    required this.battlePot,
    required this.roundsCount,
    required this.lastRoundResult,
    this.winnerUserId,
    this.isTie = false,
    this.finished = false,
    this.pendingCollectorId,
  });
}

/// Copie Dart pure de l'arbitre backend (voir `app/Services/WarCardEngine.php`)
/// — utilisée par les modes présentiel (Nearby Connections et
/// pass-and-play), qui ne passent jamais par le serveur pendant la
/// partie. Même raisonnement reproduit fidèlement des deux côtés, y
/// compris le mélange des cartes remportées avant de les rendre en jeu
/// (voir doc PHP : sans ça, la partie peut boucler quasi indéfiniment,
/// propriété mathématique connue du jeu de Bataille).
///
/// TROISIÈME pattern de synchronisation de ce projet : ni tour par tour,
/// ni "n'importe qui n'importe quand", mais "les DEUX doivent taper avant
/// que la manche résolve" (voir flip()).
class WarCardEngine {
  static const deckSize = 52;
  static const halfDeck = 26;
  static const maxRounds = 300;
  /// Paliers de taille de paquet (voir demande utilisateur) — copie
  /// fidèle de WarCardEngine::LEVELS côté PHP.
  static const levels = [24, 52, 104];

  /// Les cartes empilées ENSEMBLE (voir demande utilisateur), jamais
  /// distribuées directement — voir shuffleDeck()/dealAutomatic()/
  /// dealManualStep() pour la suite du cycle. [deckSize] doit être une
  /// valeur de [levels] : 24 (9 à As, un paquet), 52 (2 à As, un paquet)
  /// ou 104 (2 à As, DEUX paquets combinés — doublons acceptés, la
  /// Bataille n'exige pas des cartes uniques).
  static List<String> shuffledDeck({int deckSize = WarCardEngine.deckSize}) {
    const suits = ['S', 'H', 'D', 'C'];
    final ranks = deckSize == 24
        ? const ['9', '10', 'J', 'Q', 'K', 'A']
        : const ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
    final copies = deckSize == 104 ? 2 : 1;

    final deck = <String>[];
    for (var c = 0; c < copies; c++) {
      for (final suit in suits) {
        for (final rank in ranks) {
          deck.add('$rank$suit');
        }
      }
    }
    deck.shuffle(Random());

    return deck;
  }

  /// "Battre" les cartes — remélange RÉEL (pas une simple animation), voir
  /// demande utilisateur.
  static List<String> shuffleDeck(List<String> deck) {
    final copy = List.of(deck);
    copy.shuffle(Random());

    return copy;
  }

  /// "Battre" SA PROPRE pile en cours de partie (voir demande
  /// utilisateur) — chacun ne mélange que sa propre pile, jamais celle
  /// de l'autre. Copie fidèle de WarCardEngine::shufflePile côté PHP.
  static List<String> shufflePile(List<String> pile) {
    final copy = List.of(pile);
    copy.shuffle(Random());

    return copy;
  }

  /// Partage automatique et instantané — coupe le paquet en deux moitiés
  /// égales.
  static ({List<String> pileCreator, List<String> pilePartner}) dealAutomatic(List<String> deck) {
    final half = deck.length ~/ 2;

    return (pileCreator: deck.sublist(0, half), pilePartner: deck.sublist(half));
  }

  /// Partage manuel — UN appel distribue DEUX cartes (une prise du
  /// DESSUS du paquet restant, une prise du DESSOUS) à la MÊME personne,
  /// en alternance d'un appel à l'autre (voir demande utilisateur) —
  /// copie fidèle de WarCardEngine::dealManualStep côté PHP.
  static ({List<String> deck, List<String> pileCreator, List<String> pilePartner}) dealManualStep({
    required List<String> deck,
    required List<String> pileCreator,
    required List<String> pilePartner,
  }) {
    if (deck.isEmpty) return (deck: deck, pileCreator: pileCreator, pilePartner: pilePartner);

    final doneTaps = (pileCreator.length + pilePartner.length) ~/ 2;
    final creatorTurn = doneTaps % 2 == 0;

    final newDeck = List.of(deck);
    final top = newDeck.removeAt(0);
    final bottom = newDeck.isNotEmpty ? newDeck.removeLast() : null;

    final newPileCreator = List.of(pileCreator);
    final newPilePartner = List.of(pilePartner);
    if (creatorTurn) {
      newPileCreator.add(top);
      if (bottom != null) newPileCreator.add(bottom);
    } else {
      newPilePartner.add(top);
      if (bottom != null) newPilePartner.add(bottom);
    }

    return (deck: newDeck, pileCreator: newPileCreator, pilePartner: newPilePartner);
  }

  /// "Commencer" (voir demande utilisateur) — une fois le paquet
  /// distribué, LES DEUX joueurs doivent confirmer avant que la partie ne
  /// démarre réellement (même principe que flip()) — copie fidèle de
  /// WarCardEngine::readyUp côté PHP.
  static ({bool readyCreator, bool readyPartner, bool started}) readyUp({
    required bool readyCreator,
    required bool readyPartner,
    required String userId,
    required String creatorId,
  }) {
    final isCreator = userId == creatorId;
    final newReadyCreator = isCreator ? true : readyCreator;
    final newReadyPartner = isCreator ? readyPartner : true;

    return (readyCreator: newReadyCreator, readyPartner: newReadyPartner, started: newReadyCreator && newReadyPartner);
  }

  /// [userId] tape "Retourner". Ne fait RIEN de plus que marquer son
  /// intention tant que l'autre n'a pas fait de même (`resolved: false`)
  /// — idempotent si déjà en attente. Dès que les deux ont tapé, résout
  /// la manche IMMÉDIATEMENT, cascade de bataille comprise.
  static WarCardFlipOutcome flip({
    required List<String> pileCreator,
    required List<String> pilePartner,
    required bool pendingFlipCreator,
    required bool pendingFlipPartner,
    required List<String> battlePot,
    required int roundsCount,
    required String userId,
    required String creatorId,
    required String partnerId,
  }) {
    final isCreator = userId == creatorId;
    final alreadyPending = isCreator ? pendingFlipCreator : pendingFlipPartner;

    if (alreadyPending) {
      return WarCardFlipOutcome(
        resolved: false,
        pileCreator: pileCreator,
        pilePartner: pilePartner,
        pendingFlipCreator: pendingFlipCreator,
        pendingFlipPartner: pendingFlipPartner,
        battlePot: battlePot,
        roundsCount: roundsCount,
        lastRoundResult: const [],
      );
    }

    final newPendingCreator = isCreator ? true : pendingFlipCreator;
    final newPendingPartner = isCreator ? pendingFlipPartner : true;

    if (!(newPendingCreator && newPendingPartner)) {
      return WarCardFlipOutcome(
        resolved: false,
        pileCreator: pileCreator,
        pilePartner: pilePartner,
        pendingFlipCreator: newPendingCreator,
        pendingFlipPartner: newPendingPartner,
        battlePot: battlePot,
        roundsCount: roundsCount,
        lastRoundResult: const [],
      );
    }

    return _resolveRound(
      pileCreator: List.of(pileCreator),
      pilePartner: List.of(pilePartner),
      battlePot: List.of(battlePot),
      roundsCount: roundsCount,
      creatorId: creatorId,
      partnerId: partnerId,
    );
  }

  /// Une SEULE comparaison par appel — voir demande utilisateur : "si y'a
  /// deux cartes de même valeur... les deux cartes restent toujours en
  /// place et on attend que les gens sortent d'autre carte, si y'a guerre
  /// encore c'est pareil, jusqu'à ce que l'un gagne à ramasser". Pas de
  /// cartes cachées : en cas d'égalité, les deux cartes rejoignent le pot
  /// (qui reste en jeu) et [pendingFlipCreator]/[pendingFlipPartner]
  /// repassent à `false` — chacun doit retaper pour jouer sa carte
  /// suivante, autant de fois qu'il le faut, jusqu'à une comparaison
  /// décisive (voir collectPot() pour le ramassage final).
  static WarCardFlipOutcome _resolveRound({
    required List<String> pileCreator,
    required List<String> pilePartner,
    required List<String> battlePot,
    required int roundsCount,
    required String creatorId,
    required String partnerId,
  }) {
    var pot = List.of(battlePot);
    final creatorCard = pileCreator.removeAt(0);
    final partnerCard = pilePartner.removeAt(0);
    pot.addAll([creatorCard, partnerCard]);
    final rounds = [
      {'creator': creatorCard, 'partner': partnerCard},
    ];

    final creatorValue = _rankValue(creatorCard);
    final partnerValue = _rankValue(partnerCard);
    final newRoundsCount = roundsCount + 1;

    // 'creator' | 'partner' | null — qui remporte CE pot. Reste `null`
    // tant que c'est une égalité ET que les deux ont encore au moins une
    // carte pour continuer la guerre (voir isOngoingWar ci-dessous) ;
    // sinon (décisif, OU l'un des deux ne peut plus continuer la guerre)
    // désigne le vainqueur de ce pot.
    String? potWinner;
    if (creatorValue > partnerValue) {
      potWinner = 'creator';
    } else if (partnerValue > creatorValue) {
      potWinner = 'partner';
    } else if (pileCreator.isEmpty && pilePartner.isEmpty) {
      potWinner = null; // égalité totale, traité plus bas (partie nulle).
    } else if (pileCreator.isEmpty) {
      potWinner = 'partner'; // ne peut plus continuer la guerre, perd par défaut.
    } else if (pilePartner.isEmpty) {
      potWinner = 'creator';
    }

    final isOngoingWar =
        potWinner == null && creatorValue == partnerValue && !(pileCreator.isEmpty && pilePartner.isEmpty);

    if (isOngoingWar) {
      // Guerre en cours : ni vainqueur ni ramassage, le pot grossit et
      // attend la prochaine paire de cartes (voir demande utilisateur :
      // "les deux cartes restent toujours en place").
      return WarCardFlipOutcome(
        resolved: true,
        pileCreator: pileCreator,
        pilePartner: pilePartner,
        pendingFlipCreator: false,
        pendingFlipPartner: false,
        battlePot: pot,
        roundsCount: newRoundsCount,
        lastRoundResult: rounds,
      );
    }

    String? winnerUserId;
    var isTie = false;
    var finished = false;

    if (pileCreator.isEmpty && pilePartner.isEmpty) {
      // Rarissime : les deux tombent à sec exactement à la même manche.
      finished = true;
      isTie = true;
    } else if (pileCreator.isEmpty) {
      winnerUserId = partnerId;
      finished = true;
    } else if (pilePartner.isEmpty) {
      winnerUserId = creatorId;
      finished = true;
    } else if (newRoundsCount >= maxRounds) {
      finished = true;
      // Le pot pas encore ramassé compte quand même pour départager au
      // décompte maximum, sinon un gros pot en attente fausserait le
      // résultat.
      final creatorTotal = pileCreator.length + (potWinner == 'creator' ? pot.length : 0);
      final partnerTotal = pilePartner.length + (potWinner == 'partner' ? pot.length : 0);
      if (creatorTotal > partnerTotal) {
        winnerUserId = creatorId;
      } else if (partnerTotal > creatorTotal) {
        winnerUserId = partnerId;
      } else {
        isTie = true;
      }
    } else {
      winnerUserId = potWinner == 'creator' ? creatorId : partnerId;
    }

    if (potWinner != null) pot.shuffle(Random());

    String? pendingCollectorId;
    if (potWinner != null) {
      if (finished) {
        // Partie terminée sur cette manche : ramassage immédiat, pas de
        // bouton (voir demande utilisateur — n'a de sens qu'en cours de
        // partie, jamais juste avant le tableau des scores).
        if (potWinner == 'creator') {
          pileCreator = [...pileCreator, ...pot];
        } else {
          pilePartner = [...pilePartner, ...pot];
        }
        pot = [];
      } else {
        pendingCollectorId = potWinner == 'creator' ? creatorId : partnerId;
      }
    }

    return WarCardFlipOutcome(
      resolved: true,
      pileCreator: pileCreator,
      pilePartner: pilePartner,
      pendingFlipCreator: false,
      pendingFlipPartner: false,
      battlePot: pot,
      pendingCollectorId: pendingCollectorId,
      roundsCount: newRoundsCount,
      lastRoundResult: rounds,
      winnerUserId: winnerUserId,
      isTie: isTie,
      finished: finished,
    );
  }

  /// Ramasse un pot en attente (voir demande utilisateur : le gagnant de
  /// la manche doit taper pour ramasser plutôt qu'un ramassage
  /// automatique) — l'appelant doit avoir déjà vérifié que c'est bien à
  /// [collectorIsCreator] de le faire (voir NearbyWarCardTransport.
  /// collectPot / WarCardController::collect côté serveur).
  static ({List<String> pileCreator, List<String> pilePartner}) collectPot({
    required List<String> pileCreator,
    required List<String> pilePartner,
    required List<String> pot,
    required bool collectorIsCreator,
  }) {
    if (collectorIsCreator) {
      return (pileCreator: [...pileCreator, ...pot], pilePartner: pilePartner);
    }
    return (pileCreator: pileCreator, pilePartner: [...pilePartner, ...pot]);
  }

  /// Vrai si les deux cartes d'une manche jouée sont à égalité (même rang)
  /// — voir demande utilisateur : distinguer une manche "guerre" d'une
  /// manche décisive doit rester possible même quand le transport ne peut
  /// pas exposer `pendingCollectorId` de façon fiable (voir
  /// LocalWarCardTransport, qui ramasse toujours automatiquement et ne
  /// l'expose donc jamais) — dérivé directement des deux cartes réellement
  /// jouées (voir `WarCardBoardState.lastRoundResult`), donc toujours
  /// correct quel que soit le transport.
  static bool isTieRound(String cardA, String cardB) => _rankValue(cardA) == _rankValue(cardB);

  static int _rankValue(String card) {
    final rank = card.substring(0, card.length - 1);
    return switch (rank) {
      'J' => 11,
      'Q' => 12,
      'K' => 13,
      'A' => 14,
      _ => int.parse(rank),
    };
  }
}
