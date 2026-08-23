import 'dart:math';

/// Pool de 60 émojis couple/amour, validé par l'utilisateur — sert de
/// réservoir pour varier les émojis d'une partie à l'autre plutôt qu'à
/// remplir un seul plateau (le plus grand palier n'utilise que 32 paires,
/// voir memoryGamePairCounts). Aucun contenu admin-curé côté backend : ce
/// pool est un simple const Dart, cohérent avec le fait que "Jeu de
/// Mémoire" ne seed aucune GameBox/GameBoxQuestion.
const List<String> memoryEmojiPool = [
  // Cœurs (20)
  '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💕',
  '💞', '💓', '💗', '💖', '💘', '💝', '💟', '♥️', '💔', '❣️',
  // Visages & gestes (11)
  '😍', '🥰', '😘', '😗', '😙', '😚', '🫶', '🤗', '💏', '💑', '💋',
  // Fleurs & nature (8)
  '🌹', '🌷', '🌸', '🌺', '🌻', '🌼', '💐', '🍀',
  // Symboles & cadeaux (15)
  '💍', '💎', '🎁', '🥂', '🍾', '🍫', '🍬', '🕯️', '✉️', '💌',
  '✨', '🌟', '💫', '🌙', '⭐',
  // Couple & mariage (6)
  '👰', '🤵', '💒', '👫', '👬', '👭',
];

/// Paliers de difficulté validés par l'utilisateur — cartes → paires →
/// grille (colonnes, lignes), voir memory_game_board_screen.dart pour le
/// GridView dimensionné en conséquence.
class MemoryGameDifficulty {
  final int cardCount;
  final int pairCount;
  final int columns;
  final int rows;

  const MemoryGameDifficulty({
    required this.cardCount,
    required this.pairCount,
    required this.columns,
    required this.rows,
  });

  static const all = <MemoryGameDifficulty>[
    MemoryGameDifficulty(cardCount: 12, pairCount: 6, columns: 3, rows: 4),
    MemoryGameDifficulty(cardCount: 16, pairCount: 8, columns: 4, rows: 4),
    MemoryGameDifficulty(cardCount: 24, pairCount: 12, columns: 4, rows: 6),
    MemoryGameDifficulty(cardCount: 32, pairCount: 16, columns: 4, rows: 8),
    MemoryGameDifficulty(cardCount: 48, pairCount: 24, columns: 6, rows: 8),
    MemoryGameDifficulty(cardCount: 64, pairCount: 32, columns: 8, rows: 8),
  ];
}

/// Tire [pairCount] émojis au hasard dans le pool (sans répétition) et
/// renvoie le plateau mélangé (chaque émoji apparaît exactement 2 fois) —
/// appelé côté client qui démarre la partie, quel que soit le mode (voir
/// GameService.startMemoryGame, ou directement en local/nearby).
List<String> generateShuffledMemoryBoard(int pairCount) {
  final chosen = (List<String>.from(memoryEmojiPool)..shuffle()).take(pairCount).toList();
  final board = [...chosen, ...chosen];
  board.shuffle(Random.secure());
  return board;
}
