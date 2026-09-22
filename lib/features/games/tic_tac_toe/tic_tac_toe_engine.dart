import 'dart:math';

/// Résultat d'une pose ou d'un déplacement — voir TicTacToeEngine.place/move.
///
/// [scoredLine]/[preScatterBoard] : renseignés UNIQUEMENT quand ce coup
/// vient de former un alignement — transitoires, ne représentent PAS
/// l'état final (déjà dispersé dans [board]) mais l'instant juste avant,
/// pour que l'UI puisse l'afficher quelques secondes (voir demande
/// utilisateur : "des que cest aligner on doit signaler une victoire en
/// marquant les case quelque seconde").
class TicTacToeMoveResult {
  final List<String?> board;
  final Map<String, int> piecesRemainingByUser;
  final Map<String, int> scoresByUser;
  final String? currentTurnUserId;
  final String? winnerUserId;
  final int movesCount;
  final bool finished;
  final List<int>? scoredLine;
  final List<String?>? preScatterBoard;

  const TicTacToeMoveResult({
    required this.board,
    required this.piecesRemainingByUser,
    required this.scoresByUser,
    this.currentTurnUserId,
    this.winnerUserId,
    required this.movesCount,
    required this.finished,
    this.scoredLine,
    this.preScatterBoard,
  });
}

/// Copie Dart pure de l'arbitre backend (voir `app/Services/TicTacToeEngine.php`)
/// — utilisée par les modes présentiel (Nearby Connections et pass-and-play),
/// qui ne passent jamais par le serveur pendant la partie. Même raisonnement
/// reproduit fidèlement des deux côtés, pas de service partagé entre les
/// deux langages (même principe que MemoryGameEngine).
///
/// Grille 5×5, jeu à SCORE (voir demande utilisateur, refonte complète de
/// l'ancien 3×3) : phase de pose ([placementPiecesPerPlayer] pions chacun),
/// puis phase de déplacement une fois les siens tous posés — vers
/// N'IMPORTE QUELLE case vide du plateau, pas de contrainte d'adjacence
/// (voir demande utilisateur : "je doi pouvoir deplacer mes pion partout
/// ou je veux"). Aligner [alignmentLength] (4) pions à la suite (sur une
/// ligne/colonne/diagonale de la grille 5×5, pas forcément toute sa
/// longueur) rapporte 1 point et
/// disperse aussitôt ces pions sur des cases vides tirées au sort — en
/// s'assurant que ce tirage ne crée aucun alignement, pour personne.
/// Victoire au premier à [targetScore] points ; aucun match nul possible
/// par construction.
class TicTacToeEngine {
  static const gridSize = 5;
  static const cellCount = 25;
  static const alignmentLength = 4;
  static const placementPiecesPerPlayer = 6;
  static const targetScore = 5;
  static const _maxScatterAttempts = 200;

  static List<List<int>>? _linesCache;

  /// Toutes les combinaisons de [alignmentLength] cases alignées (lignes,
  /// colonnes, diagonales) sur la grille 5×5 — avec 4 cases alignées :
  /// 10 lignes + 10 colonnes + 8 diagonales = 28 segments au total. Mis
  /// en cache, jamais recalculé deux fois.
  static List<List<int>> winningLines() {
    final cached = _linesCache;
    if (cached != null) return cached;

    final lines = <List<int>>[];
    const directions = [
      [1, 0],
      [0, 1],
      [1, 1],
      [1, -1],
    ];
    const span = alignmentLength - 1;
    for (var r = 0; r < gridSize; r++) {
      for (var c = 0; c < gridSize; c++) {
        for (final dir in directions) {
          final dr = dir[0], dc = dir[1];
          final rEnd = r + span * dr, cEnd = c + span * dc;
          if (rEnd < 0 || rEnd >= gridSize || cEnd < 0 || cEnd >= gridSize) continue;
          lines.add([
            for (var i = 0; i < alignmentLength; i++) (r + i * dr) * gridSize + (c + i * dc),
          ]);
        }
      }
    }
    return _linesCache = lines;
  }

  /// Pose un nouveau pion — réservé tant qu'il reste des pièces à poser pour [userId].
  static TicTacToeMoveResult place({
    required List<String?> board,
    required Map<String, int> piecesRemainingByUser,
    required Map<String, int> scoresByUser,
    required int position,
    required String userId,
    required String otherUserId,
    required int movesCount,
  }) {
    if ((piecesRemainingByUser[userId] ?? 0) <= 0) {
      throw ArgumentError("Tu n'as plus de pion à poser — c'est le moment de déplacer.");
    }
    if (position < 0 || position >= cellCount) {
      throw ArgumentError('Case invalide.');
    }
    if (board[position] != null) {
      throw ArgumentError('Cette case est déjà prise.');
    }

    final newBoard = [...board];
    newBoard[position] = userId;
    final newRemaining = {...piecesRemainingByUser};
    newRemaining[userId] = (newRemaining[userId] ?? 0) - 1;

    return _resolveTurn(
      board: newBoard,
      piecesRemainingByUser: newRemaining,
      scoresByUser: scoresByUser,
      userId: userId,
      otherUserId: otherUserId,
      movesCount: movesCount + 1,
    );
  }

  /// Déplace un pion déjà posé vers n'importe quelle case vide du plateau
  /// — réservé une fois qu'il n'y a plus rien à poser pour [userId]. Pas
  /// de contrainte d'adjacence (voir doc de classe).
  static TicTacToeMoveResult move({
    required List<String?> board,
    required Map<String, int> piecesRemainingByUser,
    required Map<String, int> scoresByUser,
    required int from,
    required int to,
    required String userId,
    required String otherUserId,
    required int movesCount,
  }) {
    if ((piecesRemainingByUser[userId] ?? 0) > 0) {
      throw ArgumentError('Il te reste des pions à poser avant de pouvoir en déplacer.');
    }
    if (from < 0 || from >= cellCount || board[from] != userId) {
      throw ArgumentError("Ce pion ne t'appartient pas.");
    }
    if (to < 0 || to >= cellCount) {
      throw ArgumentError('Case invalide.');
    }
    if (board[to] != null) {
      throw ArgumentError('Cette case est déjà prise.');
    }

    final newBoard = [...board];
    newBoard[from] = null;
    newBoard[to] = userId;

    return _resolveTurn(
      board: newBoard,
      piecesRemainingByUser: piecesRemainingByUser,
      scoresByUser: scoresByUser,
      userId: userId,
      otherUserId: otherUserId,
      movesCount: movesCount + 1,
    );
  }

  static TicTacToeMoveResult _resolveTurn({
    required List<String?> board,
    required Map<String, int> piecesRemainingByUser,
    required Map<String, int> scoresByUser,
    required String userId,
    required String otherUserId,
    required int movesCount,
  }) {
    final scattered = _scoreAndScatter(board, scoresByUser, userId);

    if ((scattered.scores[userId] ?? 0) >= targetScore) {
      return TicTacToeMoveResult(
        board: scattered.board,
        piecesRemainingByUser: piecesRemainingByUser,
        scoresByUser: scattered.scores,
        winnerUserId: userId,
        movesCount: movesCount,
        finished: true,
        scoredLine: scattered.scoredLine,
        preScatterBoard: scattered.preScatterBoard,
      );
    }

    return TicTacToeMoveResult(
      board: scattered.board,
      piecesRemainingByUser: piecesRemainingByUser,
      scoresByUser: scattered.scores,
      currentTurnUserId: otherUserId,
      movesCount: movesCount,
      finished: false,
      scoredLine: scattered.scoredLine,
      preScatterBoard: scattered.preScatterBoard,
    );
  }

  /// Cherche un alignement de [alignmentLength] pour [userId] ; s'il y en a
  /// un : +1 point, les pions alignés repartent aussitôt sur des cases
  /// vides tirées au sort — en s'assurant que ce nouveau tirage ne crée
  /// AUCUN alignement, pour personne, quitte à retirer au sort.
  static ({
    List<String?> board,
    Map<String, int> scores,
    List<int>? scoredLine,
    List<String?>? preScatterBoard,
  }) _scoreAndScatter(
    List<String?> board,
    Map<String, int> scoresByUser,
    String userId,
  ) {
    final line = _firstAlignedLine(board, userId);
    if (line == null) {
      return (board: board, scores: scoresByUser, scoredLine: null, preScatterBoard: null);
    }

    // Capturé AVANT dispersion — c'est ce plateau, avec l'alignement encore
    // visible, que l'UI affiche quelques secondes avant de basculer sur le
    // plateau final dispersé (voir demande utilisateur).
    final preScatterBoard = [...board];

    final newScores = {...scoresByUser};
    newScores[userId] = (newScores[userId] ?? 0) + 1;

    final cleared = [...board];
    for (final index in line) {
      cleared[index] = null;
    }

    final random = Random();
    var candidate = cleared;
    for (var attempt = 0; attempt < _maxScatterAttempts; attempt++) {
      final emptyPositions = [
        for (var i = 0; i < cleared.length; i++)
          if (cleared[i] == null) i,
      ]..shuffle(random);
      final chosen = emptyPositions.take(line.length).toList();

      candidate = [...cleared];
      for (final index in chosen) {
        candidate[index] = userId;
      }

      if (!_hasAnyAlignment(candidate)) break;
    }

    return (board: candidate, scores: newScores, scoredLine: line, preScatterBoard: preScatterBoard);
  }

  static List<int>? _firstAlignedLine(List<String?> board, String userId) {
    for (final line in winningLines()) {
      if (_lineBelongsTo(board, line, userId)) return line;
    }
    return null;
  }

  static bool _hasAnyAlignment(List<String?> board) {
    for (final line in winningLines()) {
      final first = board[line[0]];
      if (first != null && _lineBelongsTo(board, line, first)) return true;
    }
    return false;
  }

  static bool _lineBelongsTo(List<String?> board, List<int> line, String userId) {
    for (final index in line) {
      if (board[index] != userId) return false;
    }
    return true;
  }

  /// La ligne alignée par [userId] (pour un éventuel affichage), ou `null`.
  static List<int>? winningLineFor(List<String?> board, String userId) => _firstAlignedLine(board, userId);
}
