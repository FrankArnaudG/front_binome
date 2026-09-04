import '../../../models/pictionary_session.dart';

/// État unifié d'une partie de "Pictionary à deux", quel que soit le mode
/// — [PictionaryBoardScreen] ne connaît que cette forme, jamais les
/// détails de synchronisation sous-jacents (voir PictionaryTransport).
///
/// DÉJÀ FILTRÉE pour [myUserId] — [word] n'est renseigné QUE si
/// [isDrawer] est vrai (voir BattleshipBoardState pour le même principe
/// appliqué à la flotte adverse) : aucune implémentation de
/// [PictionaryTransport] ne doit jamais construire un état qui
/// exposerait le mot à qui devine.
class PictionaryBoardState {
  final bool isDrawer;
  final String? word;
  final List<PictionaryStroke> strokes;
  final Map<String, int> scoresByUser;
  final int targetScore;
  final int roundNumber;
  final DateTime? roundStartedAt;
  final int roundSeconds;
  final String? currentDrawerUserId;
  final String? winnerUserId;
  final int movesCount;
  final bool finished;
  final DateTime? startedAt;
  final String myUserId;
  final String opponentUserId;
  final String? pausedByUserId;
  final DateTime? pausedAt;

  const PictionaryBoardState({
    this.isDrawer = false,
    this.word,
    this.strokes = const [],
    this.scoresByUser = const {},
    this.targetScore = 5,
    this.roundNumber = 0,
    this.roundStartedAt,
    this.roundSeconds = 70,
    this.currentDrawerUserId,
    this.winnerUserId,
    this.movesCount = 0,
    this.finished = false,
    this.startedAt,
    required this.myUserId,
    required this.opponentUserId,
    this.pausedByUserId,
    this.pausedAt,
  });

  bool get isPaused => pausedByUserId != null;
  bool get pausedByMe => pausedByUserId == myUserId;
  bool get iWon => winnerUserId == myUserId;
  int scoreFor(String userId) => scoresByUser[userId] ?? 0;

  PictionaryBoardState copyWith({
    bool? isDrawer,
    String? word,
    bool clearWord = false,
    List<PictionaryStroke>? strokes,
    Map<String, int>? scoresByUser,
    int? roundNumber,
    DateTime? roundStartedAt,
    String? currentDrawerUserId,
    String? winnerUserId,
    int? movesCount,
    bool? finished,
    DateTime? startedAt,
    String? pausedByUserId,
    DateTime? pausedAt,
    bool clearPause = false,
  }) =>
      PictionaryBoardState(
        isDrawer: isDrawer ?? this.isDrawer,
        word: clearWord ? null : (word ?? this.word),
        strokes: strokes ?? this.strokes,
        scoresByUser: scoresByUser ?? this.scoresByUser,
        targetScore: targetScore,
        roundNumber: roundNumber ?? this.roundNumber,
        roundStartedAt: roundStartedAt ?? this.roundStartedAt,
        roundSeconds: roundSeconds,
        currentDrawerUserId: currentDrawerUserId ?? this.currentDrawerUserId,
        winnerUserId: winnerUserId ?? this.winnerUserId,
        movesCount: movesCount ?? this.movesCount,
        finished: finished ?? this.finished,
        startedAt: startedAt ?? this.startedAt,
        myUserId: myUserId,
        opponentUserId: opponentUserId,
        pausedByUserId: clearPause ? null : (pausedByUserId ?? this.pausedByUserId),
        pausedAt: clearPause ? null : (pausedAt ?? this.pausedAt),
      );
}

/// Abstraction commune aux 3 modes de "Pictionary à deux" — encapsule
/// UNIQUEMENT la façon dont les traits/manches sont synchronisés entre
/// les deux joueurs.
abstract class PictionaryTransport {
  Stream<PictionaryBoardState> get stateStream;

  PictionaryBoardState get currentState;

  /// Ajoute un segment de trait — réservé au·à la dessinateur·rice
  /// courant·e, no-op silencieux sinon.
  Future<void> addStroke(PictionaryStroke stroke);

  /// Le·la dessinateur·rice valide que son binôme a trouvé le mot —
  /// crédite le point à l'AUTRE personne (voir doc de classe).
  Future<void> markFound();

  /// Manche passée sans trouvaille (temps écoulé).
  Future<void> skipRound();

  Future<void> abandon();

  Future<void> pause();

  Future<void> resume();

  void dispose();
}
