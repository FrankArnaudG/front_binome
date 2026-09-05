import 'dart:async';

import '../../../core/realtime_client.dart';
import '../../../models/pictionary_session.dart';
import '../game_service.dart';
import 'pictionary_transport.dart';

/// Mode "à distance" — synchronisation via le backend. `word` ne
/// transite JAMAIS par l'événement WebSocket `PictionaryUpdated` (voir
/// doc PHP) : ce transport rappelle `state()` en authentifié pour obtenir
/// sa propre vue filtrée à chaque signal. Les traits, eux, arrivent en
/// direct via `PictionaryStrokeAdded` (contenu réel, sans risque de
/// fuite) — copie structurelle de RemoteBattleshipTransport, avec un
/// second canal pour le dessin en temps réel.
class RemotePictionaryTransport extends PictionaryTransport {
  final String sessionId;
  final String boxId;
  final String myUserId;
  final String opponentUserId;
  final _controller = StreamController<PictionaryBoardState>.broadcast();
  late PictionaryBoardState _state;

  RemotePictionaryTransport({
    required PictionarySession session,
    required this.boxId,
    required this.myUserId,
    required this.opponentUserId,
  }) : sessionId = session.id {
    _state = _stateFrom(session);
    RealtimeClient.instance.subscribeToBox(boxId, onEvent: _onRealtimeEvent);
  }

  PictionaryBoardState _stateFrom(PictionarySession session) => PictionaryBoardState(
        isDrawer: session.isDrawer,
        word: session.word,
        strokes: session.strokes,
        scoresByUser: session.scoresByUser,
        targetScore: session.targetScore,
        roundNumber: session.roundNumber,
        roundStartedAt: session.roundStartedAt,
        roundSeconds: session.roundSeconds,
        currentDrawerUserId: session.currentDrawerUserId,
        winnerUserId: session.winnerUserId,
        movesCount: session.movesCount,
        finished: session.isFinished || session.abandoned,
        abandoned: session.abandoned,
        startedAt: session.startedAt,
        myUserId: myUserId,
        opponentUserId: opponentUserId,
        pausedByUserId: session.pausedByUserId,
        pausedAt: session.pausedAt,
      );

  Future<void> _refetch() async {
    final session = await GameService.instance.fetchPictionaryState(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    final data = event.data;
    if (data == null || data['session_id'] != sessionId) return;

    if (event.event == 'PictionaryUpdated') {
      unawaited(_refetch());
    } else if (event.event == 'PictionaryStrokeAdded') {
      // Contenu direct (voir doc de classe) — pas de refetch, juste
      // l'ajout du trait reçu à l'état courant.
      final stroke = PictionaryStroke.fromJson(data['stroke'] as Map<String, dynamic>);
      _state = _state.copyWith(strokes: [..._state.strokes, stroke]);
      _controller.add(_state);
    }
  }

  @override
  Stream<PictionaryBoardState> get stateStream => _controller.stream;

  @override
  PictionaryBoardState get currentState => _state;

  @override
  Future<void> addStroke(PictionaryStroke stroke) async {
    if (!_state.isDrawer) return;
    // Optimiste : on l'ajoute localement tout de suite (c'est NOUS qui
    // dessinons, pas besoin d'attendre le broadcast), puis on l'envoie.
    _state = _state.copyWith(strokes: [..._state.strokes, stroke]);
    _controller.add(_state);
    try {
      await GameService.instance.sendPictionaryStroke(sessionId, stroke);
    } catch (_) {
      // Best-effort : un trait perdu n'est pas grave, l'essentiel du
      // dessin reste visible.
    }
  }

  @override
  Future<void> markFound() async {
    if (!_state.isDrawer) return;
    final session = await GameService.instance.markPictionaryFound(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> skipRound() async {
    final session = await GameService.instance.skipPictionaryRound(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> abandon() async {
    final session = await GameService.instance.abandonPictionary(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> pause() async {
    final session = await GameService.instance.pausePictionary(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> resume() async {
    if (!_state.pausedByMe) return;
    final session = await GameService.instance.resumePictionary(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  void dispose() {
    RealtimeClient.instance.unsubscribeFromBox(boxId, onEvent: _onRealtimeEvent);
    _controller.close();
  }
}
