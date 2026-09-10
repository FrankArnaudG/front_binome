import 'dart:async';

import '../../../core/realtime_client.dart';
import '../../../models/number_hunt_session.dart';
import '../game_service.dart';
import 'number_hunt_engine.dart';
import 'number_hunt_transport.dart';

/// Mode "à distance" — synchronisation via le backend (REST pour les
/// tentatives, WebSocket Reverb pour recevoir celles du binôme). PAS de
/// tour par tour : les deux dispositifs peuvent envoyer une tentative à
/// tout moment, le serveur arbitre les quasi-égalités (voir
/// NumberHuntController::attempt, verrouillage de ligne) — copie
/// structurelle conforme des 3 autres jeux à distance.
class RemoteNumberHuntTransport extends NumberHuntTransport {
  final String sessionId;
  // `null` pour une partie hors-Box (défi à un ami de jeu via son code,
  // voir demande utilisateur) — le canal temps réel devient alors
  // [_friendChannelName] (dédié à CETTE session) plutôt que le canal de la
  // Box, voir le constructeur.
  final String? boxId;
  final String myUserId;
  final String partnerUserId;
  final _controller = StreamController<NumberHuntBoardState>.broadcast();
  late NumberHuntBoardState _state;

  String get _friendChannelName => 'number-hunt-session.$sessionId';

  RemoteNumberHuntTransport({
    required NumberHuntSession session,
    required this.boxId,
    required this.myUserId,
    required this.partnerUserId,
  }) : sessionId = session.id {
    _state = _stateFrom(session);
    final box = boxId;
    if (box != null) {
      RealtimeClient.instance.subscribeToBox(box, onEvent: _onRealtimeEvent);
    } else {
      RealtimeClient.instance.subscribePrivate(_friendChannelName, onEvent: _onRealtimeEvent);
    }
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
        abandoned: session.abandoned,
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
    // Prédiction locale immédiate (voir RemoteMemoryGameTransport.flip) —
    // ici PAS de tour par tour, donc un tir du binôme peut réellement
    // arriver entre-temps (voir doc de classe : "le serveur arbitre les
    // quasi-égalités") ; sans conséquence visible, la réponse HTTP arrive
    // presque aussitôt et écrase cette prédiction avec l'état réel.
    try {
      final outcome = NumberHuntEngine.attempt(
        currentTarget: _state.currentTarget,
        found: _state.found,
        scoresByUser: _state.scoresByUser,
        number: number,
        userId: myUserId,
        movesCount: _state.movesCount,
        creatorId: myUserId,
        partnerId: partnerUserId,
        cellCount: _state.board.length,
      );
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
    } catch (_) {
      // Tentative localement invalide — le serveur tranchera.
    }

    try {
      final result = await GameService.instance.attemptNumberHunt(sessionId, number);
      _state = _stateFrom(result.session);
      _controller.add(_state);
    } catch (_) {
      try {
        final session = await GameService.instance.fetchNumberHuntState(sessionId);
        _state = _stateFrom(session);
        _controller.add(_state);
      } catch (_) {
        // best effort — voir doc de classe RealtimeClient.
      }
    }
  }

  @override
  Future<void> abandon() async {
    final session = await GameService.instance.abandonNumberHunt(sessionId);
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
    final box = boxId;
    if (box != null) {
      RealtimeClient.instance.unsubscribeFromBox(box, onEvent: _onRealtimeEvent);
    } else {
      RealtimeClient.instance.unsubscribePrivate(_friendChannelName, onEvent: _onRealtimeEvent);
    }
    _controller.close();
  }
}
