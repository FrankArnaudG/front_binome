import 'dart:async';

import '../../../core/realtime_client.dart';
import '../../../models/dot_square_session.dart';
import '../game_service.dart';
import 'dot_squares_transport.dart';

/// Mode "à distance" — synchronisation via le backend (REST pour les
/// actions, WebSocket Reverb pour recevoir les coups de l'autre) — copie
/// structurelle conforme de RemoteTicTacToeTransport.
class RemoteDotSquaresTransport extends DotSquaresTransport {
  final String sessionId;
  final String boxId;
  final String myUserId;
  final _controller = StreamController<DotSquaresBoardState>.broadcast();
  late DotSquaresBoardState _state;

  RemoteDotSquaresTransport({
    required DotSquareSession session,
    required this.boxId,
    required this.myUserId,
  }) : sessionId = session.id {
    _state = _stateFrom(session);
    RealtimeClient.instance.subscribeToBox(boxId, onEvent: _onRealtimeEvent);
  }

  DotSquaresBoardState _stateFrom(DotSquareSession session) => DotSquaresBoardState(
        points: session.points ?? List<String?>.filled(session.gridRows * session.gridCols, null),
        gridCols: session.gridCols,
        rectangles: session.rectangles,
        scoresByUser: session.scoresByUser,
        currentTurnUserId: session.currentTurnUserId,
        winnerUserId: session.winnerUserId,
        isTie: session.isTie,
        movesCount: session.movesCount,
        finished: session.isFinished || session.abandoned,
        startedAt: session.startedAt,
        myUserId: myUserId,
        pausedByUserId: session.pausedByUserId,
        pausedAt: session.pausedAt,
        closeRequestedByUserId: session.closeRequestedByUserId,
      );

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.event != 'DotSquaresUpdated') return;
    final data = event.data;
    if (data == null) return;

    final session = DotSquareSession.fromJson(data['session'] as Map<String, dynamic>);
    // Un event peut concerner une AUTRE feuille du même box si plusieurs
    // étaient lancées coup sur coup — ignoré si ce n'est pas la nôtre,
    // même principe que RemoteTicTacToeTransport.
    if (session.id != sessionId) return;

    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Stream<DotSquaresBoardState> get stateStream => _controller.stream;

  @override
  DotSquaresBoardState get currentState => _state;

  @override
  Future<void> place(int position) async {
    final session = await GameService.instance.playDotSquaresMove(sessionId, position);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> requestClose() async {
    final session = await GameService.instance.requestCloseDotSquares(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> cancelCloseRequest() async {
    if (!_state.closeRequestedByMe) return;
    final session = await GameService.instance.cancelCloseDotSquares(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> abandon() async {
    final session = await GameService.instance.abandonDotSquares(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> pause() async {
    final session = await GameService.instance.pauseDotSquares(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> resume() async {
    if (!_state.pausedByMe) return;
    final session = await GameService.instance.resumeDotSquares(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  void dispose() {
    RealtimeClient.instance.unsubscribeFromBox(boxId, onEvent: _onRealtimeEvent);
    _controller.close();
  }
}
