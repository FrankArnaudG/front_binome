import 'dart:async';

import '../../../core/game_sync_log.dart';
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

  // Filet de sécurité : un évènement temps réel manqué (coupure réseau, app en arrière-plan) laissait ce
  // téléphone figé sur un état ancien alors que l'autre avait avancé (voir demande utilisateur : "un
  // téléphone revient en arrière"). On recale donc régulièrement sur le serveur.
  Timer? _resyncTimer;
  StreamSubscription<void>? _resyncSub;
  // Dernière version serveur appliquée (voir HasStateVersion) : tout état plus ancien est ignoré.
  int _version = 0;

  String get _friendChannelName => 'battleship-session.$sessionId';

  RemoteBattleshipTransport({
    required BattleshipSession session,
    required this.boxId,
    required this.myUserId,
    required this.opponentUserId,
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
  bool _isStale(BattleshipSession session) {
    if (session.version > 0 && _version > 0) return session.version < _version;
    return !(session.isFinished || session.abandoned) && session.movesCount < _state.movesCount;
  }

  /// Vérifie qu'un état serveur n'est pas plus ancien que celui affiché ; sinon le trace et le refuse.
  bool _acceptVersion(BattleshipSession session) {
    if (_isStale(session)) {
      logStaleGameState('battleship', incoming: session.version, current: _version);
      return false;
    }
    if (session.version > _version) _version = session.version;
    return true;
  }

  void _applyServerState(BattleshipSession session) {
    if (!_acceptVersion(session)) return;
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  Future<void> _resyncIfBehind() async {
    if (_state.finished) return;
    try {
      final session = await GameService.instance.fetchBattleshipState(sessionId);
      if (_controller.isClosed || _state.finished) return;
      final behind = session.version > _version || session.movesCount > _state.movesCount || ((session.isFinished || session.abandoned) && !_state.finished);
      if (!behind) return;
      _applyServerState(session);
    } catch (_) {
      // best effort — on retente au prochain tour.
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
    _applyServerState(session);
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
    _applyServerState(session);
  }

  @override
  Future<void> fire(int cell) async {
    final session = await GameService.instance.fireBattleship(sessionId, cell);
    _applyServerState(session);
  }

  @override
  Future<void> abandon() async {
    final session = await GameService.instance.abandonBattleship(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> pause() async {
    // Application immédiate côté local (voir demande utilisateur) — le
    // binôme le verra dès que le broadcast lui parvient, pas la peine
    // d'attendre la réponse serveur pour geler l'écran ici.
    _state = _state.copyWith(pausedByUserId: myUserId, pausedAt: DateTime.now());
    _controller.add(_state);

    final session = await GameService.instance.pauseBattleship(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> resume() async {
    // Réservé à qui a posé la pause — SAUF une pause posée automatiquement par un solde épuisé
    // (voir AuthorizesResume côté serveur : pausedByUserId reste alors NULL, n'importe quel
    // participant peut tenter de la lever, le serveur revérifie lui-même le solde du payeur).
    if (!_state.pausedByMe && _state.pausedByUserId != null) return;
    final session = await GameService.instance.resumeBattleship(sessionId);
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
