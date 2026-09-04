import 'dart:async';

import '../../../core/realtime_client.dart';
import '../../../models/number_hunt_session.dart';
import '../game_service.dart';
import 'number_hunt_transport.dart';

/// Mode "à distance" — synchronisation via le backend (REST pour les
/// tentatives, WebSocket Reverb pour recevoir celles du binôme). PAS de
/// tour par tour : les deux dispositifs peuvent envoyer une tentative à
/// tout moment, le serveur arbitre les quasi-égalités (voir
/// NumberHuntController::attempt, verrouillage de ligne) — copie
/// structurelle conforme des 3 autres jeux à distance.
class RemoteNumberHuntTransport extends NumberHuntTransport {
  final String sessionId;
  final String boxId;
  final String myUserId;
  final _controller = StreamController<NumberHuntBoardState>.broadcast();
  late NumberHuntBoardState _state;

  RemoteNumberHuntTransport({
    required NumberHuntSession session,
    required this.boxId,
    required this.myUserId,
  }) : sessionId = session.id {
    _state = _stateFrom(session);
    RealtimeClient.instance.subscribeToBox(boxId, onEvent: _onRealtimeEvent);
  }

  NumberHuntBoardState _stateFrom(NumberHuntSession session) => NumberHuntBoardState(
        board: session.board ?? const [],
        found: session.found,
        currentTarget: session.currentTarget,
        scoresByUser: session.scoresByUser,
        winnerUserId: session.winnerUserId,
        isTie: session.isTie,
        movesCount: session.movesCount,
        finished: session.isFinished || session.abandoned,
        startedAt: session.startedAt,
        myUserId: myUserId,
        pausedByUserId: session.pausedByUserId,
        pausedAt: session.pausedAt,
      );

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.event != 'NumberHuntUpdated') return;
    final data = event.data;
    if (data == null) return;

    final session = NumberHuntSession.fromJson(data['session'] as Map<String, dynamic>);
    // Un event peut concerner une AUTRE partie de ce jeu du même box si
    // plusieurs étaient lancées coup sur coup — ignoré si ce n'est pas la
    // nôtre, même principe que les 3 autres jeux.
    if (session.id != sessionId) return;

    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Stream<NumberHuntBoardState> get stateStream => _controller.stream;

  @override
  NumberHuntBoardState get currentState => _state;

  @override
  Future<void> attempt(int number) async {
    final result = await GameService.instance.attemptNumberHunt(sessionId, number);
    _state = _stateFrom(result.session);
    _controller.add(_state);
  }

  @override
  Future<void> abandon() async {
    final session = await GameService.instance.abandonNumberHunt(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> pause() async {
    final session = await GameService.instance.pauseNumberHunt(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> resume() async {
    if (!_state.pausedByMe) return;
    final session = await GameService.instance.resumeNumberHunt(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  void dispose() {
    RealtimeClient.instance.unsubscribeFromBox(boxId, onEvent: _onRealtimeEvent);
    _controller.close();
  }
}
