import 'dart:math';

/// Pool de 60 émojis couple/amour, validé par l'utilisateur — sert de
/// réservoir pour varier les émojis d'une partie à l'autre plutôt qu'à
/// remplir un seul plateau (le plus grand palier n'utilise que 40 paires,
/// voir MemoryGameDifficulty.all). Aucun contenu admin-curé côté backend : ce
/// pool est un simple const Dart, cohérent avec le fait que "Jeu de
/// Mémoire" ne seed aucune GameBox/GameBoxQuestion.
const List<String> memoryEmojiPool = [
  // Cœurs (20)
  '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💕',
  '💞', '💓', '💗', '💖', '💘', '💝', '💟', '♥️', '💔', '❣️',
  // Visages & gestes (11)
  // 🥰 est le plus récent de ce groupe (Unicode 11.0, 2018) — encore
  // largement pris en charge. 🫶 ("heart hands", Unicode 14.0, 2022) a été
  // retiré : trop récent pour le rendu emoji système de certains appareils
  // Android d'entrée de gamme (constaté en test réel — case rendue vide/
  // cassée sur un téléphone, correcte sur l'autre), remplacé par 😉 (l'un
  // des tout premiers emoji, universellement pris en charge).
  '😍', '🥰', '😘', '😗', '😙', '😚', '😉', '🤗', '💏', '💑', '💋',
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
    MemoryGameDifficulty(cardCount: 80, pairCount: 40, columns: 8, rows: 10),
    // Palier "expert" — l'entête resserrée (voir demande utilisateur)
    // dégage assez de hauteur pour ce palier plus dense sans passer sous
    // un format de carte inconfortable ; au-delà, les cartes deviendraient
    // trop petites pour rester tapables (grille toujours adaptée
    // automatiquement à l'espace disponible, jamais de défilement, voir
    // memory_game_board_screen.dart).
    MemoryGameDifficulty(cardCount: 96, pairCount: 48, columns: 8, rows: 12),
    // Deux paliers "extrême" au-delà — le pool d'émojis, une fois les
    // groupes confondables réduits à un représentant chacun (voir
    // _confusableEmojiGroups), ne fournit que 57 émojis distincts par
    // partie : 56 paires est donc quasiment le plafond technique (56/57),
    // cartes minuscules mais encore jouables (voir demande utilisateur).
    MemoryGameDifficulty(cardCount: 104, pairCount: 52, columns: 8, rows: 13),
    MemoryGameDifficulty(cardCount: 112, pairCount: 56, columns: 8, rows: 14),
  ];
}

/// Groupes d'émojis visuellement trop proches pour être distingués d'un
/// coup d'œil sur une petite carte (voir demande utilisateur : "j'avais
/// l'impression que des paires d'émoji sont utilisées plusieurs fois" —
/// pas un vrai doublon, juste deux émojis différents qui se ressemblent
/// trop). Un seul membre de chaque groupe est retenu par partie (voir
/// _drawPool ci-dessous), jamais deux ensemble sur le même plateau.
const List<List<String>> _confusableEmojiGroups = [
  ['❤️', '♥️'], // même cœur rouge plein, juste un point de code différent
  ['👫', '👬', '👭'], // couple qui se tient la main, ne diffère que par le genre
];

/// Réduit chaque groupe confondable à UN SEUL représentant (tiré au hasard
/// à chaque partie, pour garder de la variété d'une partie à l'autre) —
/// combiné aux émojis hors groupe, ça donne 57 émojis utilisables par
/// tirage (60 - 5 regroupés + 2 représentants), largement au-dessus du
/// plus grand palier (40 paires, voir MemoryGameDifficulty.all).
List<String> _drawPool() {
  final grouped = _confusableEmojiGroups.expand((group) => group).toSet();
  final singles = memoryEmojiPool.where((emoji) => !grouped.contains(emoji));
  final representatives = [
    for (final group in _confusableEmojiGroups) (List<String>.from(group)..shuffle()).first,
  ];
  return [...singles, ...representatives];
}

/// Tire [pairCount] émojis au hasard dans le pool (sans répétition, et sans
/// jamais deux émojis trop proches visuellement dans le même tirage, voir
/// _drawPool) et renvoie le plateau mélangé (chaque émoji apparaît
/// exactement 2 fois) — appelé côté client qui démarre la partie, quel que
/// soit le mode (voir GameService.startMemoryGame, ou directement en
/// local/nearby).
List<String> generateShuffledMemoryBoard(int pairCount) {
  final chosen = (_drawPool()..shuffle()).take(pairCount).toList();
  final board = [...chosen, ...chosen];
  board.shuffle(Random.secure());
  return board;
}
