import 'dart:async';

import '../../../core/realtime_client.dart';
import '../../../models/memory_game_session.dart';
import '../game_service.dart';
import 'memory_game_transport.dart';

/// Mode "à distance" — synchronisation via le backend (REST pour les
/// actions, WebSocket Reverb pour recevoir les coups de l'autre). Chaque
/// action locale (flip/abandon) met aussi à jour l'état à partir de la
/// réponse HTTP directement (pas seulement en attendant l'event WS) : sur
/// SA PROPRE action, pas besoin d'attendre un aller-retour réseau
/// supplémentaire pour se sentir réactif.
class RemoteMemoryGameTransport extends MemoryGameTransport {
  final String sessionId;
  final String boxId;
  final String myUserId;
  final _controller = StreamController<MemoryGameBoardState>.broadcast();
  late MemoryGameBoardState _state;

  RemoteMemoryGameTransport({
    required MemoryGameSession session,
    required this.boxId,
    required this.myUserId,
  }) : sessionId = session.id {
    _state = _stateFrom(session);
    RealtimeClient.instance.subscribeToBox(boxId, onEvent: _onRealtimeEvent);
  }

  MemoryGameBoardState _stateFrom(MemoryGameSession session, {List<int>? mismatch}) => MemoryGameBoardState(
        board: session.board ?? const [],
        matched: session.matched,
        flipped: session.flipped,
        mismatch: mismatch,
        currentTurnUserId: session.currentTurnUserId,
        movesCount: session.movesCount,
        movesByUser: session.movesByUser,
        finished: session.isFinished || session.abandoned,
        startedAt: session.startedAt,
        myUserId: myUserId,
        pausedByUserId: session.pausedByUserId,
        pausedAt: session.pausedAt,
      );

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.event != 'MemoryGameUpdated') return;
    final data = event.data;
    if (data == null) return;

    final session = MemoryGameSession.fromJson(data['session'] as Map<String, dynamic>);
    // Un event peut concerner une AUTRE partie de mémoire du même box si
    // plusieurs étaient lancées coup sur coup — même si peu probable, on
    // ignore tout ce qui n'est pas notre session en cours plutôt que de
    // supposer qu'il n'y en a jamais qu'une.
    if (session.id != sessionId) return;

    final mismatchRaw = data['mismatch'] as List?;
    final mismatch = mismatchRaw?.map((e) => e as int).toList();

    _state = _stateFrom(session, mismatch: mismatch);
    _controller.add(_state);
  }

  @override
  Stream<MemoryGameBoardState> get stateStream => _controller.stream;

  @override
  MemoryGameBoardState get currentState => _state;

  @override
  Future<void> flip(int index) async {
    final session = await GameService.instance.flipMemoryCard(sessionId, index);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> abandon() async {
    final session = await GameService.instance.abandonMemoryGame(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> pause() async {
    final session = await GameService.instance.pauseMemoryGame(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> resume() async {
    // Réservé à qui a posé la pause — le backend renvoie 403 sinon (voir
    // MemoryGameController::resume) ; l'UI ne propose de toute façon jamais
    // ce bouton à l'autre (voir MemoryGameBoardState.pausedByMe), donc
    // n'appeler l'API que dans le cas déjà autorisé.
    if (!_state.pausedByMe) return;
    final session = await GameService.instance.resumeMemoryGame(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  void dispose() {
    RealtimeClient.instance.unsubscribeFromBox(boxId, onEvent: _onRealtimeEvent);
    _controller.close();
  }
}
