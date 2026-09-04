import 'dart:async';

import 'number_hunt_engine.dart';
import 'number_hunt_transport.dart';

/// Mode "présentiel, un seul téléphone" (pass-and-play) — aucune
/// connexion, tout se joue en mémoire locale. Comme il n'y a pas de tour
/// par tour, l'appareil ne peut PAS savoir tout seul lequel des deux vient
/// de taper le bon nombre en premier — [askWhoFound] est appelé UNIQUEMENT
/// quand la tentative est effectivement correcte (jamais sur un raté),
/// pour laisser les deux joueurs se mettre d'accord eux-mêmes sur qui a
/// trouvé (voir demande utilisateur : "si c'est sur un seul téléphone pas
/// besoin de demander qui a cliqué" — en fait tout l'inverse, c'est
/// exactement le cas où il FAUT demander, l'app ne pouvant pas le savoir).
class LocalNumberHuntTransport extends NumberHuntTransport {
  final String creatorUserId;
  final String partnerUserId;

  /// Doit renvoyer [creatorUserId] ou [partnerUserId] — voir doc de classe.
  final Future<String> Function() askWhoFound;

  final _controller = StreamController<NumberHuntBoardState>.broadcast();
  late NumberHuntBoardState _state;

  LocalNumberHuntTransport({
    required this.creatorUserId,
    required this.partnerUserId,
    required this.askWhoFound,
    required int cellCount,
  }) {
    final initial = NumberHuntEngine.generateInitialState(cellCount: cellCount);
    _state = NumberHuntBoardState(
      board: initial.board,
      currentTarget: initial.currentTarget,
      scoresByUser: {creatorUserId: 0, partnerUserId: 0},
      startedAt: DateTime.now(),
      myUserId: creatorUserId,
    );
  }

  @override
  Stream<NumberHuntBoardState> get stateStream => _controller.stream;

  @override
  NumberHuntBoardState get currentState => _state;

  @override
  Future<void> attempt(int number) async {
    if (_state.finished || _state.isPaused) return;
    // Vérifie AVANT de solliciter qui a trouvé — jamais de pop-up sur un
    // raté, uniquement sur une tentative qui aurait effectivement compté.
    if (_state.currentTarget != number) return;

    final creditedUserId = await askWhoFound();

    final outcome = NumberHuntEngine.attempt(
      currentTarget: _state.currentTarget,
      found: _state.found,
      scoresByUser: _state.scoresByUser,
      number: number,
      userId: creditedUserId,
      movesCount: _state.movesCount,
      creatorId: creatorUserId,
      partnerId: partnerUserId,
      cellCount: _state.board.length,
    );
    if (!outcome.wasCorrect) return; // la cible a changé entre-temps (improbable en local, mais défensif)

    _state = _state.copyWith(
      found: outcome.found,
      scoresByUser: outcome.scoresByUser,
      currentTarget: outcome.newTarget,
      clearTarget: outcome.newTarget == null,
      movesCount: outcome.movesCount,
      finished: outcome.finished,
      winnerUserId: outcome.winnerUserId,
      isTie: outcome.isTie,
    );
    _controller.add(_state);
  }

  @override
  Future<void> abandon() async {
    _state = _state.copyWith(finished: true);
    _controller.add(_state);
  }

  // myUserId reste fixe pour toute la partie (voir LocalTicTacToeTransport,
  // même correctif) — garantit que `pausedByMe` reste vrai sur cet
  // appareil partagé.
  @override
  Future<void> pause() async {
    if (_state.isPaused || _state.finished) return;
    _state = _state.copyWith(pausedByUserId: _state.myUserId, pausedAt: DateTime.now());
    _controller.add(_state);
  }

  @override
  Future<void> resume() async {
    if (!_state.isPaused) return;
    final paused = _state.pausedAt;
    if (paused != null && _state.startedAt != null) {
      _state = _state.copyWith(startedAt: _state.startedAt!.add(DateTime.now().difference(paused)));
    }
    _state = _state.copyWith(clearPause: true);
    _controller.add(_state);
  }

  @override
  void dispose() {
    _controller.close();
  }
}
