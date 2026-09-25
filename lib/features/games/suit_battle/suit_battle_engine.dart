import 'dart:math';

/// Résultat d'un playLead() — voir SuitBattleEngine.playLead.
class SuitBattleLeadOutcome {
  final List<String> spread;
  final String tableCard;
  final String tableOwnerUserId;
  final String turnUserId;
  final String? winnerUserId;
  final bool finished;

  const SuitBattleLeadOutcome({
    required this.spread,
    required this.tableCard,
    required this.tableOwnerUserId,
    required this.turnUserId,
    this.winnerUserId,
    this.finished = false,
  });
}

/// Résultat d'un respondCard() — voir SuitBattleEngine.respondCard. Le
/// vainqueur de l'échange ([winnerId]) est déjà connu, mais PAS fusionné
/// dans sa pile de gains — voir demande utilisateur : "les deux cartes
/// sorties se disposent côte à côte... un bouton Balayer" — sauf si cette
/// carte termine la partie ([finished]), auquel cas [mergedWonPile] porte
/// la fusion déjà faite (pas de pause "reveal" juste avant le tableau des
/// scores, même principe que WarCardEngine).
class SuitBattleRespondOutcome {
  final List<String> spread;
  final String card;
  final String winnerId;
  final int roundsCount;
  final String? winnerUserId;
  final bool finished;
  final List<String>? mergedWonPile;

  const SuitBattleRespondOutcome({
    required this.spread,
    required this.card,
    required this.winnerId,
    required this.roundsCount,
    this.winnerUserId,
    this.finished = false,
    this.mergedWonPile,
  });
}

/// Résultat d'un captureLead() — voir SuitBattleEngine.captureLead.
class SuitBattleCaptureOutcome {
  final List<String> wonPile;
  final String leaderId;
  final int roundsCount;

  const SuitBattleCaptureOutcome({
    required this.wonPile,
    required this.leaderId,
    required this.roundsCount,
  });
}

/// Copie Dart pure de l'arbitre backend (voir
/// `app/Services/SuitBattleEngine.php`) — utilisée par le mode présentiel
/// connecté (Nearby Connections), qui ne passe jamais par le serveur
/// pendant la partie, et pour la prédiction optimiste du mode à distance
/// (voir SuitBattleTransportRemote).
///
/// 52 cartes + 2 Jokers, réparties en deux ÉVENTAILS de 27 cartes chacun,
/// FACE VISIBLE pour les deux joueurs — contrairement aux piles cachées de
/// la Bataille (voir WarCardEngine), chaque carte est ici individuellement
/// adressable, pas seulement celle du dessus.
///
/// - Phase "lead" : celui dont c'est le tour pose N'IMPORTE QUELLE carte de
///   sa main (playLead) — elle devient la carte sur table, la phase passe
///   à "response", le tour passe à l'autre.
/// - Phase "response" : le répondant a exactement deux choix — suivre la
///   couleur de la carte sur table (ou jouer un Joker) via respondCard(),
///   ou capturer la carte sur table directement dans sa pile de gains sans
///   jouer de carte via captureLead() (le meneur ORIGINAL reprend alors la
///   main).
/// - Résolution d'un échange (dans respondCard) : deux Jokers = égalité, le
///   meneur garde la main et les deux cartes ; un seul Joker = son
///   propriétaire gagne automatiquement ; ni l'un ni l'autre = comparaison
///   de rang classique (2 à As, voir rankValue() — la carte de réponse est
///   garantie de la même couleur, jamais d'égalité dans cette branche).
///
/// Victoire : dès qu'une main se vide, son propriétaire gagne
/// immédiatement, peu importe la taille des piles de gains ou à qui le
/// tour revenait nominalement.
class SuitBattleEngine {
  static const deckSize = 54;
  static const handSize = 27;
  static const joker = 'JOK';

  /// 52 cartes standard + 2 Jokers, mélangées.
  static List<String> shuffledDeck() {
    const suits = ['S', 'H', 'D', 'C'];
    const ranks = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];

    final deck = <String>[];
    for (final suit in suits) {
      for (final rank in ranks) {
        deck.add('$rank$suit');
      }
    }
    deck.add(joker);
    deck.add(joker);
    deck.shuffle(Random());

    return deck;
  }

  /// Partage automatique et instantané — coupe le paquet en deux éventails
  /// égaux de 27 cartes.
  static ({List<String> spreadCreator, List<String> spreadPartner}) dealAutomatic(List<String> deck) {
    final half = deck.length ~/ 2;

    return (spreadCreator: deck.sublist(0, half), spreadPartner: deck.sublist(half));
  }

  /// "Commencer" — une fois le paquet distribué, LES DEUX joueurs doivent
  /// confirmer avant que la partie ne démarre réellement (même principe
  /// que WarCardEngine.readyUp). Dès que les deux sont prêts, le CRÉATEUR
  /// de la Box prend la main en premier.
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

  static bool isJoker(String card) => card == joker;

  static String? suitOf(String card) {
    if (isJoker(card)) return null;
    return card.substring(card.length - 1);
  }

  /// Copie de WarCardEngine._rankValue() — les Jokers n'entrent jamais dans
  /// une comparaison de rang (voir respondCard(), branche "ni l'un ni
  /// l'autre n'est Joker"), la valeur retournée ici pour un Joker n'est
  /// qu'un sentinel jamais réellement comparé.
  static int rankValue(String card) {
    if (isJoker(card)) return 15;
    final rank = card.substring(0, card.length - 1);
    return switch (rank) {
      'J' => 11,
      'Q' => 12,
      'K' => 13,
      'A' => 14,
      _ => int.parse(rank),
    };
  }

  /// Le meneur pose n'importe quelle carte de sa main — elle devient la
  /// carte sur table, en attente de réponse.
  static SuitBattleLeadOutcome playLead({
    required List<String> spread,
    required String userId,
    required String card,
    required String otherUserId,
  }) {
    final index = spread.indexOf(card);
    if (index == -1) {
      throw ArgumentError("Cette carte n'est pas dans ta main.");
    }

    final newSpread = List.of(spread)..removeAt(index);
    final finished = newSpread.isEmpty;

    return SuitBattleLeadOutcome(
      spread: newSpread,
      tableCard: card,
      tableOwnerUserId: userId,
      turnUserId: otherUserId,
      winnerUserId: finished ? userId : null,
      finished: finished,
    );
  }

  /// Le répondant joue une carte de la même couleur que la carte sur
  /// table, ou un Joker — sinon rejeté. Le vainqueur de l'échange est
  /// déterminé tout de suite, mais PAS fusionné dans sa pile de gains
  /// (voir doc de classe [SuitBattleRespondOutcome]) — sauf si cette carte
  /// vide la main du répondant, auquel cas la partie se termine
  /// immédiatement et la fusion est faite ici (pas de pause "reveal" juste
  /// avant le tableau des scores).
  static SuitBattleRespondOutcome respondCard({
    required List<String> spread,
    required String userId,
    required String card,
    required String tableCard,
    required String leaderId,
    required List<String> leaderWonPile,
    required List<String> responderWonPile,
    required int roundsCount,
  }) {
    final index = spread.indexOf(card);
    if (index == -1) {
      throw ArgumentError("Cette carte n'est pas dans ta main.");
    }
    if (!isJoker(card) && suitOf(card) != suitOf(tableCard)) {
      throw ArgumentError('Cette carte ne correspond pas à la couleur demandée.');
    }

    final newSpread = List.of(spread)..removeAt(index);

    final leaderIsJoker = isJoker(tableCard);
    final responderIsJoker = isJoker(card);
    final String winnerId;
    if (leaderIsJoker) {
      winnerId = leaderId;
    } else if (responderIsJoker) {
      winnerId = userId;
    } else {
      winnerId = rankValue(tableCard) > rankValue(card) ? leaderId : userId;
    }

    final finished = newSpread.isEmpty;
    final mergedWonPile = finished
        ? (List.of(winnerId == leaderId ? leaderWonPile : responderWonPile)
          ..add(tableCard)
          ..add(card))
        : null;

    return SuitBattleRespondOutcome(
      spread: newSpread,
      card: card,
      winnerId: winnerId,
      roundsCount: roundsCount + 1,
      winnerUserId: finished ? userId : null,
      finished: finished,
      mergedWonPile: mergedWonPile,
    );
  }

  /// Fusionne l'échange révélé ([tableCard] + [responseCard]) dans la pile
  /// de gains du vainqueur déjà déterminé — voir demande utilisateur :
  /// bouton "Balayer".
  static List<String> sweepExchange({
    required String tableCard,
    required String responseCard,
    required List<String> currentWinnerWonPile,
  }) {
    return List.of(currentWinnerWonPile)
      ..add(tableCard)
      ..add(responseCard);
  }

  /// Le répondant capture la carte sur table directement, sans jouer de
  /// carte — le meneur ORIGINAL reprend la main (pas le capturant).
  static SuitBattleCaptureOutcome captureLead({
    required String tableCard,
    required String leaderId,
    required List<String> responderWonPile,
    required int roundsCount,
  }) {
    final wonPile = List.of(responderWonPile)..add(tableCard);

    return SuitBattleCaptureOutcome(wonPile: wonPile, leaderId: leaderId, roundsCount: roundsCount + 1);
  }
}
