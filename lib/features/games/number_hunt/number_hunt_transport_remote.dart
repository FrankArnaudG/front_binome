import 'dart:async';

import '../../../core/game_sync_log.dart';
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

  // Filet de sécurité : un évènement temps réel manqué (coupure réseau, app en arrière-plan) laissait ce
  // téléphone figé sur un état ancien alors que l'autre avait avancé (voir demande utilisateur : "un
  // téléphone revient en arrière"). On recale donc régulièrement sur le serveur.
  Timer? _resyncTimer;
  StreamSubscription<void>? _resyncSub;
  // Dernière version serveur appliquée (voir HasStateVersion) : tout état plus ancien est ignoré.
  int _version = 0;

  String get _friendChannelName => 'number-hunt-session.$sessionId';

  RemoteNumberHuntTransport({
    required NumberHuntSession session,
    required this.boxId,
    required this.myUserId,
    required this.partnerUserId,
  }) : sessionId = session.id {
    _state = _stateFrom(session);
    _version = session.version;
    final box = boxId;
    if (box != null) {
      RealtimeClient.instance.subscribeToBox(box, onEvent: _onRealtimeEvent);
    } else {
      RealtimeClient.instance.subscribePrivate(_friendChannelName, onEvent: _onRealtimeEvent);
    }
    _resyncTimer = Timer.periodic(const Duration(seconds: 4), (_) => _resyncIfBehind());
    _resyncSub = RealtimeClient.instance.resyncRequests.listen((_) => _resyncIfBehind());
  }

  /// Un état plus ancien que celui qu'on a déjà (évènement arrivé dans le désordre) ne doit jamais
  /// être appliqué : il faisait revenir l'écran en arrière. Une partie terminée passe toujours.
  bool _isStale(NumberHuntSession session) {
    if (session.version > 0 && _version > 0) return session.version < _version;
    return !(session.isFinished || session.abandoned) && session.movesCount < _state.movesCount;
  }

  /// Vérifie qu'un état serveur n'est pas plus ancien que celui affiché ; sinon le trace et le refuse.
  bool _acceptVersion(NumberHuntSession session) {
    if (_isStale(session)) {
      logStaleGameState('number_hunt', incoming: session.version, current: _version);
      return false;
    }
    if (session.version > _version) _version = session.version;
    return true;
  }

  void _applyServerState(NumberHuntSession session) {
    if (!_acceptVersion(session)) return;
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  Future<void> _resyncIfBehind() async {
    if (_state.finished) return;
    try {
      final session = await GameService.instance.fetchNumberHuntState(sessionId);
      if (_controller.isClosed || _state.finished) return;
      final behind = session.version > _version || session.movesCount > _state.movesCount || ((session.isFinished || session.abandoned) && !_state.finished);
      if (!behind) return;
      _applyServerState(session);
    } catch (_) {
      // best effort — on retente au prochain tour.
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
    if (!_acceptVersion(session)) return;

    _applyServerState(session);
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
      _applyServerState(result.session);
    } catch (_) {
      try {
        final session = await GameService.instance.fetchNumberHuntState(sessionId);
        _applyServerState(session);
      } catch (_) {
        // best effort — voir doc de classe RealtimeClient.
      }
    }
  }

  @override
  Future<void> abandon() async {
    final session = await GameService.instance.abandonNumberHunt(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> pause() async {
    // Application immédiate côté local (voir demande utilisateur) — le
    // binôme le verra dès que le broadcast lui parvient, pas la peine
    // d'attendre la réponse serveur pour geler l'écran ici.
    _state = _state.copyWith(pausedByUserId: myUserId, pausedAt: DateTime.now());
    _controller.add(_state);

    final session = await GameService.instance.pauseNumberHunt(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> resume() async {
    // Réservé à qui a posé la pause — SAUF une pause posée automatiquement par un solde épuisé
    // (voir AuthorizesResume côté serveur : pausedByUserId reste alors NULL, n'importe quel
    // participant peut tenter de la lever, le serveur revérifie lui-même le solde du payeur).
    if (!_state.pausedByMe && _state.pausedByUserId != null) return;
    final session = await GameService.instance.resumeNumberHunt(sessionId);
    _applyServerState(session);
  }

  @override
  void dispose() {
    _resyncTimer?.cancel();
    _resyncSub?.cancel();
    final box = boxId;
    if (box != null) {
      RealtimeClient.instance.unsubscribeFromBox(box, onEvent: _onRealtimeEvent);
    } else {
      RealtimeClient.instance.unsubscribePrivate(_friendChannelName, onEvent: _onRealtimeEvent);
    }
    _controller.close();
  }
}
