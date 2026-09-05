import '../../../models/dot_square_session.dart';
import 'dot_squares_engine.dart';

/// État unifié d'une feuille de "Le Jeu des Carrés", quel que soit le mode
/// — [DotSquaresBoardScreen] ne connaît que cette forme, jamais les
/// détails de synchronisation sous-jacents (voir DotSquaresTransport),
/// même principe que TicTacToeBoardState/MemoryGameBoardState.
class DotSquaresBoardState {
  final List<String?> points;
  // Largeur DE CETTE partie (voir demande utilisateur : paliers de
  // largeur, la hauteur ne change jamais) — jamais la constante statique
  // DotSquaresEngine.gridCols, qui ne reflète que la valeur par défaut.
  final int gridCols;
  final List<DotSquareRectangle> rectangles;
  final Map<String, int> scoresByUser;
  final String? currentTurnUserId;
  final String? winnerUserId;
  final bool isTie;
  final int movesCount;
  final bool finished;
  // Distinct d'une fin normale (feuille pleine/close volontairement) — voir
  // DotSquaresBoardScreen._onState : seule cette valeur déclenche la pop-up
  // "{partenaire} a mis fin à cette partie" plutôt que le scoreboard
  // habituel (voir demande utilisateur, même principe que
  // MemoryGameBoardState.abandoned).
  final bool abandoned;
  final DateTime? startedAt;
  final String myUserId;
  final String? pausedByUserId;
  final DateTime? pausedAt;
  // Non-null tant qu'une proposition de clôture volontaire est en attente
  // (voir demande utilisateur : "les deux doivent être d'accord") — id de
  // qui l'a proposée ; toujours `null` en pass-and-play (clôture immédiate,
  // voir LocalDotSquaresTransport).
  final String? closeRequestedByUserId;
  // Renseigné UNIQUEMENT sur l'état émis juste après un coup qui vient de
  // marquer au moins un rectangle — transitoire, pour un toast (voir
  // demande utilisateur : les rectangles sont tracés/numérotés
  // IMMÉDIATEMENT, contrairement au Morpion il n'y a pas de délai avant
  // affichage définitif).
  final List<DotSquareRectangle> newlyScored;

  const DotSquaresBoardState({
    this.points = const [],
    this.gridCols = DotSquaresEngine.gridCols,
    this.rectangles = const [],
    this.scoresByUser = const {},
    this.currentTurnUserId,
    this.winnerUserId,
    this.isTie = false,
    this.movesCount = 0,
    this.finished = false,
    this.abandoned = false,
    this.startedAt,
    required this.myUserId,
    this.pausedByUserId,
    this.pausedAt,
    this.closeRequestedByUserId,
    this.newlyScored = const [],
  });

  bool get isMyTurn => currentTurnUserId == myUserId;
  bool get isPaused => pausedByUserId != null;
  bool get pausedByMe => pausedByUserId == myUserId;
  bool get iWon => winnerUserId == myUserId;
  bool get closeRequested => closeRequestedByUserId != null;
  bool get closeRequestedByMe => closeRequestedByUserId == myUserId;

  int scoreFor(String userId) => scoresByUser[userId] ?? 0;

  DotSquaresBoardState copyWith({
    List<String?>? points,
    List<DotSquareRectangle>? rectangles,
    int? gridCols,
    Map<String, int>? scoresByUser,
    String? currentTurnUserId,
    String? winnerUserId,
    bool? isTie,
    int? movesCount,
    bool? finished,
    bool? abandoned,
    DateTime? startedAt,
    String? pausedByUserId,
    DateTime? pausedAt,
    bool clearPause = false,
    String? closeRequestedByUserId,
    bool clearCloseRequest = false,
    List<DotSquareRectangle>? newlyScored,
  }) =>
      DotSquaresBoardState(
        points: points ?? this.points,
        gridCols: gridCols ?? this.gridCols,
        rectangles: rectangles ?? this.rectangles,
        scoresByUser: scoresByUser ?? this.scoresByUser,
        currentTurnUserId: currentTurnUserId ?? this.currentTurnUserId,
        winnerUserId: winnerUserId ?? this.winnerUserId,
        isTie: isTie ?? this.isTie,
        movesCount: movesCount ?? this.movesCount,
        finished: finished ?? this.finished,
        abandoned: abandoned ?? this.abandoned,
        startedAt: startedAt ?? this.startedAt,
        myUserId: myUserId,
        pausedByUserId: clearPause ? null : (pausedByUserId ?? this.pausedByUserId),
        pausedAt: clearPause ? null : (pausedAt ?? this.pausedAt),
        closeRequestedByUserId: clearCloseRequest ? null : (closeRequestedByUserId ?? this.closeRequestedByUserId),
        newlyScored: newlyScored ?? const [],
      );

  factory DotSquaresBoardState.initial({
    required String myUserId,
    required String partnerUserId,
    int cols = DotSquaresEngine.gridCols,
  }) =>
      DotSquaresBoardState(
        points: List<String?>.filled(DotSquaresEngine.gridRows * cols, null),
        gridCols: cols,
        scoresByUser: {myUserId: 0, partnerUserId: 0},
        currentTurnUserId: myUserId,
        startedAt: DateTime.now(),
        myUserId: myUserId,
      );
}

/// Abstraction commune aux 3 modes de "Le Jeu des Carrés" — encapsule
/// UNIQUEMENT la façon dont les coups sont synchronisés entre les deux
/// joueurs (REST+WebSocket à distance, messages P2P en Nearby, état local
/// en pass-and-play) ; la logique de règles elle-même est identique
/// partout (voir DotSquaresEngine côté Dart, ou son pendant PHP pour le
/// mode à distance) — copie structurelle conforme de TicTacToeTransport.
abstract class DotSquaresTransport {
  Stream<DotSquaresBoardState> get stateStream;

  DotSquaresBoardState get currentState;

  /// `false` uniquement pour le pass-and-play (voir
  /// LocalDotSquaresTransport) : les deux partenaires se passent le MÊME
  /// appareil, donc "à qui le tour" n'a de sens que comme indicateur
  /// visuel, jamais comme condition d'accès à la feuille.
  bool get requiresTurnToPlay => true;

  Future<void> place(int position);

  /// Propose de clôturer la feuille avant qu'elle soit pleine ; si le
  /// binôme avait déjà proposé, vaut confirmation et clôture immédiatement
  /// — sauf en pass-and-play où un seul appel clôture directement (voir
  /// demande utilisateur : "si on joue sur un seul téléphone, c'est un
  /// seul clic").
  Future<void> requestClose();

  /// Annule sa propre proposition de clôture — no-op en pass-and-play (pas
  /// de proposition en attente possible, voir requestClose()).
  Future<void> cancelCloseRequest();

  Future<void> abandon();

  /// Met la partie en pause — n'importe lequel des deux peut la déclencher,
  /// mais seule cette personne pourra la lever (voir resume()).
  Future<void> pause();

  /// Lève la pause — réservé à qui l'a posée ; chaque implémentation refuse
  /// silencieusement (no-op) un appel par l'autre plutôt que de planter.
  Future<void> resume();

  void dispose();
}
