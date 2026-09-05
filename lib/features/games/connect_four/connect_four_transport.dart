import 'connect_four_engine.dart';

/// État unifié d'une partie de "Puissance 4", quel que soit le mode —
/// [ConnectFourBoardScreen] ne connaît que cette forme, jamais les
/// détails de synchronisation sous-jacents (voir ConnectFourTransport),
/// même principe que DotSquaresBoardState/TicTacToeBoardState.
class ConnectFourBoardState {
  final List<String?> board;
  final String? currentTurnUserId;
  final String? winnerUserId;
  final bool isTie;
  final int movesCount;
  final bool finished;
  // Distinct d'une fin normale (alignement de 4/grille pleine) — voir
  // ConnectFourBoardScreen._onState : seule cette valeur déclenche la
  // pop-up "{partenaire} a mis fin à cette partie" plutôt que le
  // scoreboard habituel (voir demande utilisateur, même principe que
  // MemoryGameBoardState.abandoned).
  final bool abandoned;
  final DateTime? startedAt;
  final String myUserId;
  final String? pausedByUserId;
  final DateTime? pausedAt;
  // Renseigné UNIQUEMENT sur l'état émis juste après le coup gagnant —
  // transitoire, pour surligner l'alignement côté client.
  final List<int>? winningLine;

  const ConnectFourBoardState({
    this.board = const [],
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
    this.winningLine,
  });

  bool get isMyTurn => currentTurnUserId == myUserId;
  bool get isPaused => pausedByUserId != null;
  bool get pausedByMe => pausedByUserId == myUserId;
  bool get iWon => winnerUserId == myUserId;

  ConnectFourBoardState copyWith({
    List<String?>? board,
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
    List<int>? winningLine,
  }) =>
      ConnectFourBoardState(
        board: board ?? this.board,
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
        winningLine: winningLine ?? this.winningLine,
      );

  factory ConnectFourBoardState.initial({required String myUserId}) => ConnectFourBoardState(
        board: ConnectFourEngine.generateInitialState(),
        currentTurnUserId: myUserId,
        startedAt: DateTime.now(),
        myUserId: myUserId,
      );
}

/// Abstraction commune aux 3 modes de "Puissance 4" — encapsule
/// UNIQUEMENT la façon dont les coups sont synchronisés entre les deux
/// joueurs ; la logique de règles elle-même est identique partout (voir
/// ConnectFourEngine côté Dart, ou son pendant PHP pour le mode à
/// distance) — copie structurelle conforme de DotSquaresTransport.
abstract class ConnectFourTransport {
  Stream<ConnectFourBoardState> get stateStream;

  ConnectFourBoardState get currentState;

  /// `false` uniquement pour le pass-and-play : les deux partenaires se
  /// passent le MÊME appareil, donc "à qui le tour" n'a de sens que comme
  /// indicateur visuel, jamais comme condition d'accès à la grille.
  bool get requiresTurnToPlay => true;

  /// Pose un jeton dans le TUYAU [pipe] (0..ConnectFourEngine.cols-1) —
  /// voir demande utilisateur : la vraie colonne où le jeton tombe est
  /// cachée derrière une correspondance aléatoire, jamais révélée au
  /// client. Retourne `false` si ce tuyau menait à une colonne déjà
  /// pleine (coup refusé, aucun jeton posé, le tour ne change pas) —
  /// jamais d'exception pour ce cas normal du jeu.
  Future<bool> drop(int pipe);

  Future<void> abandon();

  Future<void> pause();

  Future<void> resume();

  void dispose();
}
