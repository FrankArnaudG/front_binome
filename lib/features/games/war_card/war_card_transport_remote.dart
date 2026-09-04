import 'dart:async';

import '../../../core/realtime_client.dart';
import '../../../models/war_card_session.dart';
import '../game_service.dart';
import 'war_card_transport.dart';

/// Mode "à distance" — synchronisation via le backend (REST pour les
/// taps, WebSocket Reverb pour recevoir ceux du binôme). Le serveur ne
/// résout la manche que quand LES DEUX ont tapé (voir
/// WarCardController::flip, verrouillage de ligne) — copie structurelle
/// conforme des autres jeux à distance.
class RemoteWarCardTransport extends WarCardTransport {
  final String sessionId;
  final String boxId;
  final String myUserId;
  final String creatorId;
  final String partnerId;
  final _controller = StreamController<WarCardBoardState>.broadcast();
  late WarCardBoardState _state;

  RemoteWarCardTransport({
    required WarCardSession session,
    required this.boxId,
    required this.myUserId,
    required this.creatorId,
    required this.partnerId,
  }) : sessionId = session.id {
    _state = _stateFrom(session);
    RealtimeClient.instance.subscribeToBox(boxId, onEvent: _onRealtimeEvent);
  }

  WarCardBoardState _stateFrom(WarCardSession session) => WarCardBoardState(
        deck: session.deck,
        dealt: session.dealt,
        readyCreator: session.readyCreator,
        readyPartner: session.readyPartner,
        started: session.started,
        pileCreator: session.pileCreator ?? const [],
        pilePartner: session.pilePartner ?? const [],
        pendingFlipCreator: session.pendingFlipCreator,
        pendingFlipPartner: session.pendingFlipPartner,
        lastRoundResult: session.lastRoundResult,
        roundsCount: session.roundsCount,
        winnerUserId: session.winnerUserId,
        isTie: session.isTie,
        finished: session.isFinished || session.abandoned,
        startedAt: session.startedAt,
        myUserId: myUserId,
        creatorId: creatorId,
        partnerId: partnerId,
        pausedByUserId: session.pausedByUserId,
        pausedAt: session.pausedAt,
      );

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.event != 'WarCardUpdated') return;
    final data = event.data;
    if (data == null) return;

    final session = WarCardSession.fromJson(data['session'] as Map<String, dynamic>);
    if (session.id != sessionId) return;

    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Stream<WarCardBoardState> get stateStream => _controller.stream;

  @override
  WarCardBoardState get currentState => _state;

  @override
  Future<void> shuffleDeck() async {
    final session = await GameService.instance.shuffleWarCard(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> dealAutomatic() async {
    final session = await GameService.instance.dealAutoWarCard(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> dealManualStep() async {
    final session = await GameService.instance.dealManualWarCard(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> readyUp() async {
    final session = await GameService.instance.readyUpWarCard(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> flip(String userId) async {
    final result = await GameService.instance.flipWarCard(sessionId);
    _state = _stateFrom(result.session);
    _controller.add(_state);
  }

  @override
  Future<void> shufflePile(String userId) async {
    final session = await GameService.instance.shufflePileWarCard(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> abandon() async {
    final session = await GameService.instance.abandonWarCard(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> pause() async {
    final session = await GameService.instance.pauseWarCard(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> resume() async {
    if (!_state.pausedByMe) return;
    final session = await GameService.instance.resumeWarCard(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  void dispose() {
    RealtimeClient.instance.unsubscribeFromBox(boxId, onEvent: _onRealtimeEvent);
    _controller.close();
  }
}
