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

  static WarCardFlipOutcome _resolveRound({
    required List<String> pileCreator,
    required List<String> pilePartner,
    required List<String> battlePot,
    required int roundsCount,
    required String creatorId,
    required String partnerId,
  }) {
    final pot = List.of(battlePot);
    final rounds = <Map<String, String>>[];

    while (pileCreator.isNotEmpty && pilePartner.isNotEmpty) {
      final creatorCard = pileCreator.removeAt(0);
      final partnerCard = pilePartner.removeAt(0);
      pot.addAll([creatorCard, partnerCard]);
      rounds.add({'creator': creatorCard, 'partner': partnerCard});

      final creatorValue = _rankValue(creatorCard);
      final partnerValue = _rankValue(partnerCard);

      if (creatorValue > partnerValue) {
        pot.shuffle(Random());
        pileCreator.addAll(pot);
        pot.clear();
        break;
      }
      if (partnerValue > creatorValue) {
        pot.shuffle(Random());
        pilePartner.addAll(pot);
        pot.clear();
        break;
      }

      // Égalité → bataille : 3 cartes cachées de chaque côté (moins si
      // l'un des deux n'en a plus assez), puis la boucle rejoue une
      // carte visible.
      final creatorHidden = pileCreator.take(3).toList();
      pileCreator.removeRange(0, creatorHidden.length);
      final partnerHidden = pilePartner.take(3).toList();
      pilePartner.removeRange(0, partnerHidden.length);
      pot.addAll([...creatorHidden, ...partnerHidden]);
    }

    // Un des deux s'est retrouvé à sec PENDANT une bataille (pot non
    // soldé) — l'autre remporte tout ce qui reste en jeu.
    if (pot.isNotEmpty) {
      pot.shuffle(Random());
      if (pileCreator.isEmpty) {
        pilePartner.addAll(pot);
      } else {
        pileCreator.addAll(pot);
      }
      pot.clear();
    }

    final newRoundsCount = roundsCount + 1;
    String? winnerUserId;
    var isTie = false;
    var finished = false;

    if (pileCreator.isEmpty) {
      winnerUserId = partnerId;
      finished = true;
    } else if (pilePartner.isEmpty) {
      winnerUserId = creatorId;
      finished = true;
    } else if (newRoundsCount >= maxRounds) {
      finished = true;
      if (pileCreator.length > pilePartner.length) {
        winnerUserId = creatorId;
      } else if (pilePartner.length > pileCreator.length) {
        winnerUserId = partnerId;
      } else {
        isTie = true;
      }
    }

    return WarCardFlipOutcome(
      resolved: true,
      pileCreator: pileCreator,
      pilePartner: pilePartner,
      pendingFlipCreator: false,
      pendingFlipPartner: false,
      battlePot: pot,
      roundsCount: newRoundsCount,
      lastRoundResult: rounds,
      winnerUserId: winnerUserId,
      isTie: isTie,
      finished: finished,
    );
  }

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
