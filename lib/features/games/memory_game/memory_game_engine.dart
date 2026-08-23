import '../../../models/memory_game_session.dart';

/// Résultat d'un retournement de carte — [mismatch] est éphémère (à
/// afficher un instant côté UI avant de recacher les deux cartes), jamais
/// reflété dans [flipped] qui repasse à `[]` immédiatement (voir doc de
/// classe MemoryGameEngine).
class MemoryGameTurnResult {
  final List<MemoryGameMatchedPair> matched;
  final List<int> flipped;
  final String currentTurnUserId;
  final int movesCount;
  final Map<String, int> movesByUser;
  final bool finished;
  final List<int>? mismatch;

  const MemoryGameTurnResult({
    required this.matched,
    required this.flipped,
    required this.currentTurnUserId,
    required this.movesCount,
    required this.movesByUser,
    required this.finished,
    this.mismatch,
  });
}

/// Copie Dart pure de l'arbitre backend (voir
/// `app/Services/MemoryGameEngine.php`) — utilisée par les modes
/// présentiel (Nearby Connections et pass-and-play), qui ne passent jamais
/// par le serveur pendant la partie. Même raisonnement reproduit
/// fidèlement des deux côtés, pas de service partagé entre les deux
/// langages.
///
/// [flipped] ne contient JAMAIS plus d'un élément dans le résultat — c'est
/// l'invariant qui évite tout timer pour "cacher la paire ratée après
/// 1.5s" : un flip suivant tombe toujours sur un état non ambigu.
class MemoryGameEngine {
  static MemoryGameTurnResult flip({
    required List<String> board,
    required List<MemoryGameMatchedPair> matched,
    required List<int> flipped,
    required String currentTurnUserId,
    required int movesCount,
    required Map<String, int> movesByUser,
    required int index,
    required String userId,
    required String otherUserId,
  }) {
    if (index < 0 || index >= board.length) {
      throw ArgumentError('Index de carte invalide.');
    }

    final matchedIndices = matched.expand((pair) => pair.indices ?? const <int>[]).toSet();
    if (matchedIndices.contains(index)) {
      throw ArgumentError('Cette carte est déjà trouvée.');
    }
    if (flipped.contains(index)) {
      throw ArgumentError('Cette carte est déjà retournée.');
    }

    if (flipped.isEmpty) {
      // Premier retournement de ce tour — aucun changement de tour, aucun
      // coup comptabilisé.
      return MemoryGameTurnResult(
        matched: matched,
        flipped: [index],
        currentTurnUserId: currentTurnUserId,
        movesCount: movesCount,
        movesByUser: movesByUser,
        finished: false,
      );
    }

    // Second retournement du tour : on compare aux valeurs du plateau.
    final firstIndex = flipped.first;
    final isMatch = board[firstIndex] == board[index];

    if (isMatch) {
      final newMatched = [
        ...matched,
        MemoryGameMatchedPair(indices: [firstIndex, index], userId: userId),
      ];
      final newMatchedIndices = newMatched.expand((pair) => pair.indices ?? const <int>[]).toSet();

      return MemoryGameTurnResult(
        matched: newMatched,
        flipped: const [],
        // Même joueur rejoue — tour inchangé.
        currentTurnUserId: currentTurnUserId,
        movesCount: movesCount,
        movesByUser: movesByUser,
        finished: newMatchedIndices.length == board.length,
      );
    }

    // Pas de match : jamais persisté à 2 éléments (voir doc de classe).
    final newMovesByUser = {...movesByUser, userId: (movesByUser[userId] ?? 0) + 1};
    return MemoryGameTurnResult(
      matched: matched,
      flipped: const [],
      currentTurnUserId: otherUserId,
      movesCount: movesCount + 1,
      movesByUser: newMovesByUser,
      finished: false,
      mismatch: [firstIndex, index],
    );
  }
}
