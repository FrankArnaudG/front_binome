import 'dart:math';

/// Résultat d'une tentative — voir NumberHuntEngine.attempt.
class NumberHuntAttemptOutcome {
  final bool wasCorrect;
  final Map<String, String> found;
  final Map<String, int> scoresByUser;
  final int? newTarget;
  final int movesCount;
  final bool finished;
  final String? winnerUserId;
  final bool isTie;

  const NumberHuntAttemptOutcome({
    required this.wasCorrect,
    required this.found,
    required this.scoresByUser,
    this.newTarget,
    required this.movesCount,
    required this.finished,
    this.winnerUserId,
    this.isTie = false,
  });
}

/// Copie Dart pure de l'arbitre backend (voir
/// `app/Services/NumberHuntEngine.php`) — utilisée par les modes
/// présentiel (Nearby Connections et pass-and-play), qui ne passent jamais
/// par le serveur pendant la partie. Même raisonnement reproduit
/// fidèlement des deux côtés, pas de service partagé entre les deux
/// langages (même principe que les 3 autres jeux).
///
/// Grille FIXE de [cellCount] cases (1..[cellCount] mélangés une seule
/// fois), un nombre-cible tiré au hasard parmi ceux pas encore trouvés —
/// PAS de tour par tour, n'importe lequel des deux peut tenter à tout
/// moment (voir doc PHP pour l'arbitrage des quasi-égalités en mode à
/// distance, propre au contrôleur ; les modes présentiel n'ont pas ce
/// souci, un seul moteur Dart local fait autorité).
class NumberHuntEngine {
  /// Paliers de difficulté proposés au choix — voir NumberHuntEngine::LEVELS
  /// côté PHP (doivent rester synchronisés).
  static const levels = [60, 80, 100, 150, 200, 230, 255];

  /// @return (board: permutation de 1..[cellCount], currentTarget: le premier nombre à chercher)
  static ({List<int> board, int currentTarget}) generateInitialState({required int cellCount}) {
    final board = List<int>.generate(cellCount, (i) => i + 1)..shuffle(Random());
    return (board: board, currentTarget: board[Random().nextInt(board.length)]);
  }

  /// Tentative de [userId] pour [number] contre le nombre cible courant
  /// [currentTarget]. Ne fait RIEN (retourne `wasCorrect: false`, état
  /// inchangé) si ce n'est pas le bon nombre — jamais d'exception pour une
  /// tentative simplement ratée. [cellCount] vient de la partie EN COURS
  /// (`state.board.length`), pas d'une constante fixe.
  static NumberHuntAttemptOutcome attempt({
    required int? currentTarget,
    required Map<String, String> found,
    required Map<String, int> scoresByUser,
    required int number,
    required String userId,
    required int movesCount,
    required String creatorId,
    required String partnerId,
    required int cellCount,
  }) {
    if (currentTarget == null || number != currentTarget) {
      return NumberHuntAttemptOutcome(
        wasCorrect: false,
        found: found,
        scoresByUser: scoresByUser,
        newTarget: currentTarget,
        movesCount: movesCount,
        finished: false,
      );
    }

    final newFound = {...found, '$number': userId};
    final newScores = {...scoresByUser};
    newScores[userId] = (newScores[userId] ?? 0) + 1;
    final newMovesCount = movesCount + 1;

    if (newFound.length >= cellCount) {
      final creatorScore = newScores[creatorId] ?? 0;
      final partnerScore = newScores[partnerId] ?? 0;
      final isTie = creatorScore == partnerScore;
      return NumberHuntAttemptOutcome(
        wasCorrect: true,
        found: newFound,
        scoresByUser: newScores,
        newTarget: null,
        movesCount: newMovesCount,
        finished: true,
        winnerUserId: isTie ? null : (creatorScore > partnerScore ? creatorId : partnerId),
        isTie: isTie,
      );
    }

    final remaining = [
      for (var n = 1; n <= cellCount; n++)
        if (!newFound.containsKey('$n')) n,
    ];
    final newTarget = remaining[Random().nextInt(remaining.length)];

    return NumberHuntAttemptOutcome(
      wasCorrect: true,
      found: newFound,
      scoresByUser: newScores,
      newTarget: newTarget,
      movesCount: newMovesCount,
      finished: false,
    );
  }
}
