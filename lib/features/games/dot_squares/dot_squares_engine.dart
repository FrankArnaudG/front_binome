import '../../../models/dot_square_session.dart';

/// Résultat d'une pose — voir DotSquaresEngine.place.
class DotSquaresMoveResult {
  final List<String?> points;
  final List<DotSquareRectangle> rectangles;
  final Map<String, int> scoresByUser;
  final String? currentTurnUserId;
  final String? winnerUserId;
  final bool isTie;
  final int movesCount;
  final bool finished;
  final List<DotSquareRectangle> newlyScored;

  const DotSquaresMoveResult({
    required this.points,
    required this.rectangles,
    required this.scoresByUser,
    this.currentTurnUserId,
    this.winnerUserId,
    this.isTie = false,
    required this.movesCount,
    required this.finished,
    this.newlyScored = const [],
  });
}

/// Copie Dart pure de l'arbitre backend (voir
/// `app/Services/DotSquaresEngine.php`) — utilisée par les modes présentiel
/// (Nearby Connections et pass-and-play), qui ne passent jamais par le
/// serveur pendant la partie. Même raisonnement reproduit fidèlement des
/// deux côtés, pas de service partagé entre les deux langages (même
/// principe que MemoryGameEngine/TicTacToeEngine).
///
/// Voir la doc PHP pour le détail des règles : poser un point, former un
/// rectangle aligné sur la grille (sans point adverse à l'intérieur ni sur
/// le bord) marque un point et le trace/numérote (numérotation PROPRE À
/// CHAQUE COULEUR, voir demande utilisateur) — les 4 coins restent en jeu,
/// réutilisables pour un rectangle plus grand, MAIS le bord (coins compris)
/// d'un rectangle déjà formé — par n'importe qui — ne peut plus jamais
/// recevoir de nouveau point (voir _isPositionBlocked) : ça garantit qu'un
/// coup ne marque jamais plus d'une figure pour la même paire de coins. Le
/// tour passe toujours. Fin par grille pleine ou clôture volontaire à deux ;
/// égalité possible.
class DotSquaresEngine {
  // La hauteur ne varie JAMAIS (voir demande utilisateur) — seule la
  // largeur change selon le palier choisi à la création de la partie
  // (voir levels), portée par chaque état de partie (voir
  // DotSquaresBoardState.gridCols), jamais une constante statique.
  static const gridRows = 20;
  static const gridCols = 45;
  static const pointCount = gridRows * gridCols;
  /// Paliers de largeur proposés au choix — voir DotSquaresEngine::LEVELS côté PHP (doivent rester synchronisés).
  static const levels = [45, 70, 120, 200, 300];

  /// Pose un point sur [position] pour [userId]. [cols] est la largeur DE
  /// CETTE partie (voir doc de classe) — jamais la constante [gridCols].
  static DotSquaresMoveResult place({
    required List<String?> points,
    required List<DotSquareRectangle> rectangles,
    required Map<String, int> scoresByUser,
    required int position,
    required String userId,
    required String otherUserId,
    required int movesCount,
    required int cols,
  }) {
    if (position < 0 || position >= points.length) {
      throw ArgumentError('Case invalide.');
    }
    if (points[position] != null) {
      throw ArgumentError('Cette case est déjà prise.');
    }

    final r = position ~/ cols;
    final c = position % cols;
    if (isPositionBlocked(rectangles, r, c)) {
      throw ArgumentError("Cette case fait partie d'un rectangle déjà formé.");
    }

    final newPoints = [...points];
    newPoints[position] = userId;

    final newRectangles = [...rectangles];
    final newScores = {...scoresByUser};
    final newlyScored = _detectRectangles(newPoints, rectangles, r, c, userId, cols);
    var myNumber = rectangles.where((rect) => rect.ownerUserId == userId).length;
    for (final rect in newlyScored) {
      myNumber++;
      final numbered = DotSquareRectangle(
        number: myNumber,
        ownerUserId: rect.ownerUserId,
        r1: rect.r1,
        c1: rect.c1,
        r2: rect.r2,
        c2: rect.c2,
      );
      newRectangles.add(numbered);
      newScores[userId] = (newScores[userId] ?? 0) + 1;
    }
    final numberedNewlyScored = newRectangles.sublist(newRectangles.length - newlyScored.length);

    final newMovesCount = movesCount + 1;

    if (!newPoints.contains(null)) {
      final finished = _finish(scoresByUser: newScores, userId: userId, otherUserId: otherUserId);
      return DotSquaresMoveResult(
        points: newPoints,
        rectangles: newRectangles,
        scoresByUser: newScores,
        winnerUserId: finished.winnerUserId,
        isTie: finished.isTie,
        movesCount: newMovesCount,
        finished: true,
        newlyScored: numberedNewlyScored,
      );
    }

    return DotSquaresMoveResult(
      points: newPoints,
      rectangles: newRectangles,
      scoresByUser: newScores,
      currentTurnUserId: otherUserId,
      movesCount: newMovesCount,
      finished: false,
      newlyScored: numberedNewlyScored,
    );
  }

  /// Calcule gagnant/égalité à partir des scores des deux [userId]/[otherUserId].
  static ({String? winnerUserId, bool isTie}) _finish({
    required Map<String, int> scoresByUser,
    required String userId,
    required String otherUserId,
  }) {
    final myScore = scoresByUser[userId] ?? 0;
    final otherScore = scoresByUser[otherUserId] ?? 0;
    if (myScore == otherScore) return (winnerUserId: null, isTie: true);
    return (winnerUserId: myScore > otherScore ? userId : otherUserId, isTie: false);
  }

  /// Cherche tous les rectangles alignés sur la grille dont [r]/[c] (la
  /// case qui vient d'être posée par [userId]) est l'un des 4 coins, les 3
  /// autres étant déjà occupés par [userId], sans aucun point adverse à
  /// l'intérieur ni sur le bord.
  static List<DotSquareRectangle> _detectRectangles(
    List<String?> points,
    List<DotSquareRectangle> rectangles,
    int r,
    int c,
    String userId,
    int cols,
  ) {
    final rowMatches = <int>[];
    for (var c2 = 0; c2 < cols; c2++) {
      if (c2 == c) continue;
      if (points[r * cols + c2] == userId) rowMatches.add(c2);
    }

    final colMatches = <int>[];
    for (var r2 = 0; r2 < gridRows; r2++) {
      if (r2 == r) continue;
      if (points[r2 * cols + c] == userId) colMatches.add(r2);
    }

    final found = <DotSquareRectangle>[];
    for (final r2 in colMatches) {
      for (final c2 in rowMatches) {
        if (points[r2 * cols + c2] != userId) continue;

        final minR = r < r2 ? r : r2;
        final maxR = r > r2 ? r : r2;
        final minC = c < c2 ? c : c2;
        final maxC = c > c2 ? c : c2;

        if (_hasBlockingPoint(points, minR, minC, maxR, maxC, cols)) continue;
        if (_crossesExistingRectangle(rectangles, minR, minC, maxR, maxC)) continue;

        found.add(DotSquareRectangle(number: 0, ownerUserId: userId, r1: minR, c1: minC, r2: maxR, c2: maxC));
      }
    }
    return found;
  }

  /// `true` si le rectangle candidat [minR,minC]-[maxR,maxC] chevauche une
  /// AIRE (surface strictement positive dans les deux dimensions) en
  /// commun avec un rectangle DÉJÀ FORMÉ — CONTRAIREMENT à
  /// [_hasBlockingPoint], qui ne regarde que les points RÉELLEMENT posés :
  /// un rectangle déjà marqué a la plupart de ses cases
  /// intérieures/bordure VIDES (seuls ses 4 coins portent un point), donc
  /// un grand rectangle pourrait "traverser" un petit déjà formé sans
  /// qu'aucun point ne s'y trouve — jamais détecté par [_hasBlockingPoint]
  /// seul (copie Dart du correctif PHP, voir
  /// DotSquaresEngine::crossesExistingRectangle).
  ///
  /// Test d'aire (pas un scan case par case, voir historique) : deux
  /// rectangles [r1,r2]×[c1,c2] et [R1,R2]×[C1,C2] partagent une aire ssi
  /// max(r1,R1) < min(r2,R2) ET max(c1,C1) < min(c2,C2) (inégalités
  /// STRICTES) — deux rectangles simplement ACCOLÉS bord à bord ne
  /// partagent qu'une LIGNE, pas une aire, et restent donc AUTORISÉS
  /// (sinon un rectangle légitime entre deux figures voisines serait
  /// bloqué à tort, voir demande utilisateur).
  static bool _crossesExistingRectangle(List<DotSquareRectangle> rectangles, int minR, int minC, int maxR, int maxC) {
    for (final rect in rectangles) {
      final rowOverlap = (minR > rect.r1 ? minR : rect.r1) < (maxR < rect.r2 ? maxR : rect.r2);
      final colOverlap = (minC > rect.c1 ? minC : rect.c1) < (maxC < rect.c2 ? maxC : rect.c2);
      if (rowOverlap && colOverlap) return true;
    }
    return false;
  }

  /// `true` si (r,c) tombe N'IMPORTE OÙ dans un rectangle déjà formé —
  /// bord (coins compris) ET intérieur — par n'importe qui — donc plus
  /// jamais disponible pour un nouveau point (voir demande utilisateur :
  /// "au niveau de la case [déjà formée] on ne devait pas pouvoir cliquer
  /// pour mettre des point rouge ou bleu à l'intérieur encore"). Public :
  /// réutilisé côté UI pour griser ces cases et ignorer un tap dessus
  /// AVANT d'appeler place() (voir DotSquaresBoardScreen._onTapPoint).
  static bool isPositionBlocked(List<DotSquareRectangle> rectangles, int r, int c) {
    for (final rect in rectangles) {
      if (r >= rect.r1 && r <= rect.r2 && c >= rect.c1 && c <= rect.c2) return true;
    }
    return false;
  }

  /// `true` si ce candidat ne doit PAS être marqué : un point de
  /// N'IMPORTE QUELLE COULEUR n'importe où dans le rectangle — bord OU
  /// intérieur, coins exclus (voir demande utilisateur : "il y avait déjà
  /// un ou des points au milieu, peu importe la couleur du point" — un
  /// point AU MILIEU, même de la même couleur, empêche désormais la
  /// formation, pas seulement sur le bord).
  ///
  /// Ce test seul suffit aussi à écarter les figures fictives "qui
  /// sautent" par-dessus des points intermédiaires alignés (voir demande
  /// utilisateur historique : "des numéro fictif sajoutent... on doit
  /// avoir 3 case pour le bleu") : un tel point intermédiaire tombe
  /// TOUJOURS sur le bord du candidat, jamais strictement à l'intérieur,
  /// donc déjà couvert ici.
  static bool _hasBlockingPoint(List<String?> points, int minR, int minC, int maxR, int maxC, int cols) {
    for (var rr = minR; rr <= maxR; rr++) {
      for (var cc = minC; cc <= maxC; cc++) {
        final isCorner = (rr == minR || rr == maxR) && (cc == minC || cc == maxC);
        if (isCorner) continue;
        if (points[rr * cols + cc] != null) return true;
      }
    }
    return false;
  }
}
