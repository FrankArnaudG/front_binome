import 'dart:async';

import '../../../models/pictionary_session.dart';
import 'pictionary_engine.dart';
import 'pictionary_transport.dart';

/// Mode "présentiel, un seul téléphone" (pass-and-play) — aucune
/// connexion, tout se joue en mémoire locale. CONTRAIREMENT à
/// [LocalBattleshipTransport], pas besoin de "passe le téléphone" au
/// niveau du TRANSPORT ici : les deux joueurs regardent le MÊME écran de
/// dessin en même temps (comme au vrai jeu, le·la dessinateur·rice
/// dessine devant l'autre). Le seul secret est LE MOT — voir
/// [PictionaryBoardScreen], qui affiche un écran de révélation privée
/// AVANT chaque manche (jamais le mot affiché en dehors de ce gate).
///
/// `myUserId` reste fixe au créateur pour toute la partie (même correctif
/// que les autres transports locaux) — [currentState.isDrawer] n'a donc
/// pas vraiment de sens ici, voir plutôt `currentDrawerUserId` pour
/// savoir qui dessine.
class LocalPictionaryTransport extends PictionaryTransport {
  final String creatorUserId;
  final String partnerUserId;
  final String locale;
  final _controller = StreamController<PictionaryBoardState>.broadcast();
  late PictionaryBoardState _state;

  LocalPictionaryTransport({required this.creatorUserId, required this.partnerUserId, required this.locale}) {
    _state = PictionaryBoardState(
      isDrawer: true,
      word: PictionaryEngine.pickWord(locale),
      scoresByUser: {creatorUserId: 0, partnerUserId: 0},
      targetScore: PictionaryEngine.targetScore,
      roundNumber: 1,
      roundStartedAt: DateTime.now(),
      roundSeconds: PictionaryEngine.roundSeconds,
      currentDrawerUserId: creatorUserId,
      startedAt: DateTime.now(),
      myUserId: creatorUserId,
      opponentUserId: partnerUserId,
    );
  }

  void _startRound(String drawerUserId) {
    _state = _state.copyWith(
      word: PictionaryEngine.pickWord(locale),
      strokes: const [],
      currentDrawerUserId: drawerUserId,
      roundNumber: _state.roundNumber + 1,
      roundStartedAt: DateTime.now(),
    );
  }

  @override
  Stream<PictionaryBoardState> get stateStream => _controller.stream;

  @override
  PictionaryBoardState get currentState => _state;

  @override
  Future<void> addStroke(PictionaryStroke stroke) async {
    if (_state.finished || _state.isPaused) return;
    _state = _state.copyWith(strokes: [..._state.strokes, stroke]);
    _controller.add(_state);
  }

  @override
  Future<void> markFound() async {
    if (_state.finished || _state.isPaused) return;
    final finderUserId = _state.currentDrawerUserId == creatorUserId ? partnerUserId : creatorUserId;
    final newScores = {..._state.scoresByUser};
    newScores[finderUserId] = (newScores[finderUserId] ?? 0) + 1;

    if (newScores[finderUserId]! >= _state.targetScore) {
      _state = _state.copyWith(scoresByUser: newScores, winnerUserId: finderUserId, finished: true, clearWord: true);
      _controller.add(_state);
      return;
    }

    _state = _state.copyWith(scoresByUser: newScores, movesCount: _state.movesCount + 1);
    _startRound(finderUserId);
    _controller.add(_state);
  }

  @override
  Future<void> skipRound() async {
    if (_state.finished || _state.isPaused) return;
    final nextDrawer = _state.currentDrawerUserId == creatorUserId ? partnerUserId : creatorUserId;
    _state = _state.copyWith(movesCount: _state.movesCount + 1);
    _startRound(nextDrawer);
    _controller.add(_state);
  }

  @override
  Future<void> abandon() async {
    _state = _state.copyWith(finished: true);
    _controller.add(_state);
  }

  @override
  Future<void> pause() async {
    if (_state.isPaused || _state.finished) return;
    _state = _state.copyWith(pausedByUserId: creatorUserId, pausedAt: DateTime.now());
    _controller.add(_state);
  }

  @override
  Future<void> resume() async {
    if (!_state.isPaused) return;
    final paused = _state.pausedAt;
    if (paused != null && _state.roundStartedAt != null) {
      _state = _state.copyWith(roundStartedAt: _state.roundStartedAt!.add(DateTime.now().difference(paused)));
    }
    _state = _state.copyWith(clearPause: true);
    _controller.add(_state);
  }

  @override
  void dispose() {
    _controller.close();
  }
}
