import 'dart:math';

/// Résultat d'un drop() — voir ConnectFourEngine.drop.
class ConnectFourDropOutcome {
  final int row;
  final int column;
  final List<int>? winningLine;
  final bool finished;
  final List<String?> board;
  final int movesCount;
  final String? winnerUserId;
  final bool isTie;
  final String? nextTurnUserId;

  const ConnectFourDropOutcome({
    required this.row,
    required this.column,
    this.winningLine,
    required this.finished,
    required this.board,
    required this.movesCount,
    this.winnerUserId,
    this.isTie = false,
    this.nextTurnUserId,
  });
}

/// Copie Dart pure de l'arbitre backend (voir
/// `app/Services/ConnectFourEngine.php`) — utilisée par les modes
/// présentiel (Nearby Connections et pass-and-play), qui ne passent
/// jamais par le serveur pendant la partie. Même raisonnement reproduit
/// fidèlement des deux côtés (même principe que les autres jeux).
class ConnectFourEngine {
  static const cols = 7;
  static const rows = 6;
  static const cellCount = cols * rows;
  static const alignmentLength = 4;
  static const _directions = [(0, 1), (1, 0), (1, 1), (1, -1)];

  static List<String?> generateInitialState() => List<String?>.filled(cellCount, null);

  /// "Tuyaux" (voir demande utilisateur) — permutation ALÉATOIRE de
  /// [0..cols-1], générée UNE FOIS par partie — copie fidèle de
  /// ConnectFourEngine::generateColumnMapping côté PHP.
  static List<int> generateColumnMapping() {
    final mapping = List<int>.generate(cols, (i) => i);
    mapping.shuffle(Random());

    return mapping;
  }

  /// Pose un jeton pour [userId] dans la colonne [column]. Lève une
  /// [ArgumentError] si la colonne est invalide ou pleine (entrées
  /// structurellement invalides).
  static ConnectFourDropOutcome drop({
    required List<String?> board,
    required int column,
    required String userId,
    required int movesCount,
    required String creatorId,
    required String partnerId,
  }) {
    if (column < 0 || column >= cols) {
      throw ArgumentError('Colonne invalide.');
    }

    final newBoard = List<String?>.of(board);
    int? row;
    for (var r = rows - 1; r >= 0; r--) {
      if (newBoard[r * cols + column] == null) {
        row = r;
        break;
      }
    }
    if (row == null) {
      throw ArgumentError('Cette colonne est pleine.');
    }

    newBoard[row * cols + column] = userId;
    final newMovesCount = movesCount + 1;

    final winningLine = _findWinningLine(newBoard, row, column, userId);
    if (winningLine != null) {
      return ConnectFourDropOutcome(
        row: row,
        column: column,
        winningLine: winningLine,
        finished: true,
        board: newBoard,
        movesCount: newMovesCount,
        winnerUserId: userId,
      );
    }

    if (newMovesCount >= cellCount) {
      return ConnectFourDropOutcome(
        row: row,
        column: column,
        finished: true,
        board: newBoard,
        movesCount: newMovesCount,
        isTie: true,
      );
    }

    return ConnectFourDropOutcome(
      row: row,
      column: column,
      finished: false,
      board: newBoard,
      movesCount: newMovesCount,
      nextTurnUserId: userId == creatorId ? partnerId : creatorId,
    );
  }

  static List<int>? _findWinningLine(List<String?> board, int row, int column, String userId) {
    for (final (dr, dc) in _directions) {
      final cells = <int>[_index(row, column)];

      for (final sign in [1, -1]) {
        var r = row + dr * sign;
        var c = column + dc * sign;
        while (_inBounds(r, c) && board[_index(r, c)] == userId) {
          cells.add(_index(r, c));
          r += dr * sign;
          c += dc * sign;
        }
      }

      if (cells.length >= alignmentLength) return cells;
    }
    return null;
  }

  static int _index(int row, int column) => row * cols + column;

  static bool _inBounds(int row, int column) => row >= 0 && row < rows && column >= 0 && column < cols;
}
