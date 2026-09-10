import 'dart:async';

import '../../../core/realtime_client.dart';
import '../../../models/battleship_session.dart';
import '../game_service.dart';
import 'battleship_transport.dart';

/// Mode "à distance" — synchronisation via le backend. CONTRAIREMENT aux
/// autres jeux à distance, l'événement WebSocket `BattleshipUpdated` ne
/// transporte JAMAIS l'état lui-même (qui contiendrait les deux flottes
/// en clair côté serveur) — juste un signal "quelque chose a changé sur
/// CETTE session", à charge pour ce transport de rappeler `state()` en
/// authentifié pour obtenir sa propre vue déjà filtrée (voir
/// BattleshipEngine::toPublicArrayFor côté PHP).
class RemoteBattleshipTransport extends BattleshipTransport {
  final String sessionId;
  // `null` pour une partie hors-Box (défi à un ami de jeu via son code,
  // voir demande utilisateur) — le canal temps réel devient alors
  // [_friendChannelName] (dédié à CETTE session) plutôt que le canal de la
  // Box, voir le constructeur (même principe que RemoteTicTacToeTransport).
  final String? boxId;
  final String myUserId;
  final String opponentUserId;
  final _controller = StreamController<BattleshipBoardState>.broadcast();
  late BattleshipBoardState _state;

  String get _friendChannelName => 'battleship-session.$sessionId';

  RemoteBattleshipTransport({
    required BattleshipSession session,
    required this.boxId,
    required this.myUserId,
    required this.opponentUserId,
  }) : sessionId = session.id {
    _state = _stateFrom(session);
    final box = boxId;
    if (box != null) {
      RealtimeClient.instance.subscribeToBox(box, onEvent: _onRealtimeEvent);
    } else {
      RealtimeClient.instance.subscribePrivate(_friendChannelName, onEvent: _onRealtimeEvent);
    }
  }

  BattleshipBoardState _stateFrom(BattleshipSession session) => BattleshipBoardState(
        gridSize: session.gridSize,
        myFleet: session.myFleet,
        myShots: session.myShots,
        opponentSunkShips: session.opponentSunkShips,
        myReady: session.myReady,
        opponentReady: session.opponentReady,
        isBattlePhase: session.isBattlePhase,
        currentTurnUserId: session.currentTurnUserId,
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
    final session = await GameService.instance.fetchBattleshipState(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.event != 'BattleshipUpdated') return;
    final data = event.data;
    if (data == null || data['session_id'] != sessionId) return;

    // Pas de payload à parser (voir doc de classe) — on resynchronise
    // simplement via un appel authentifié.
    unawaited(_refetch());
  }

  @override
  Stream<BattleshipBoardState> get stateStream => _controller.stream;

  @override
  BattleshipBoardState get currentState => _state;

  @override
  Future<void> submitFleet(List<BattleshipShip> ships) async {
    final session = await GameService.instance.placeBattleshipFleet(sessionId, ships);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> fire(int cell) async {
    final session = await GameService.instance.fireBattleship(sessionId, cell);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> abandon() async {
    final session = await GameService.instance.abandonBattleship(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> pause() async {
    // Application immédiate côté local (voir demande utilisateur) — le
    // binôme le verra dès que le broadcast lui parvient, pas la peine
    // d'attendre la réponse serveur pour geler l'écran ici.
    _state = _state.copyWith(pausedByUserId: myUserId, pausedAt: DateTime.now());
    _controller.add(_state);

    final session = await GameService.instance.pauseBattleship(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> resume() async {
    if (!_state.pausedByMe) return;
    final session = await GameService.instance.resumeBattleship(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  void dispose() {
    final box = boxId;
    if (box != null) {
      RealtimeClient.instance.unsubscribeFromBox(box, onEvent: _onRealtimeEvent);
    } else {
      RealtimeClient.instance.unsubscribePrivate(_friendChannelName, onEvent: _onRealtimeEvent);
    }
    _controller.close();
  }
}
