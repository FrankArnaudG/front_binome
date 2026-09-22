import 'dart:async';

import '../../../core/game_sync_log.dart';
import '../../../core/realtime_client.dart';
import '../../../models/dot_square_session.dart';
import '../game_service.dart';
import 'dot_squares_engine.dart';
import 'dot_squares_transport.dart';

/// Mode "à distance" — synchronisation via le backend (REST pour les
/// actions, WebSocket Reverb pour recevoir les coups de l'autre) — copie
/// structurelle conforme de RemoteTicTacToeTransport.
class RemoteDotSquaresTransport extends DotSquaresTransport {
  final String sessionId;
  // `null` pour une partie hors-Box (défi à un ami de jeu via son code,
  // voir demande utilisateur) — le canal temps réel devient alors
  // [_friendChannelName] (dédié à CETTE session) plutôt que le canal de la
  // Box, voir le constructeur.
  final String? boxId;
  final String myUserId;
  final String partnerUserId;
  final _controller = StreamController<DotSquaresBoardState>.broadcast();
  late DotSquaresBoardState _state;

  // Filet de sécurité : un évènement temps réel manqué (coupure réseau, app en arrière-plan) laissait ce
  // téléphone figé sur un état ancien alors que l'autre avait avancé (voir demande utilisateur : "un
  // téléphone revient en arrière"). On recale donc régulièrement sur le serveur.
  Timer? _resyncTimer;
  StreamSubscription<void>? _resyncSub;
  // Dernière version serveur appliquée (voir HasStateVersion) : tout état plus ancien est ignoré.
  int _version = 0;

  String get _friendChannelName => 'dot-squares-session.$sessionId';

  RemoteDotSquaresTransport({
    required DotSquareSession session,
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
  bool _isStale(DotSquareSession session) {
    if (session.version > 0 && _version > 0) return session.version < _version;
    return !(session.isFinished || session.abandoned) && session.movesCount < _state.movesCount;
  }

  /// Vérifie qu'un état serveur n'est pas plus ancien que celui affiché ; sinon le trace et le refuse.
  bool _acceptVersion(DotSquareSession session) {
    if (_isStale(session)) {
      logStaleGameState('dot_squares', incoming: session.version, current: _version);
      return false;
    }
    if (session.version > _version) _version = session.version;
    return true;
  }

  void _applyServerState(DotSquareSession session) {
    if (!_acceptVersion(session)) return;
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  Future<void> _resyncIfBehind() async {
    if (_state.finished) return;
    try {
      final session = await GameService.instance.fetchDotSquaresState(sessionId);
      if (_controller.isClosed || _state.finished) return;
      final behind = session.version > _version || session.movesCount > _state.movesCount || ((session.isFinished || session.abandoned) && !_state.finished);
      if (!behind) return;
      _applyServerState(session);
    } catch (_) {
      // best effort — on retente au prochain tour.
    }
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
        abandoned: session.abandoned,
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
    if (!_acceptVersion(session)) return;

    _applyServerState(session);
  }

  @override
  Stream<DotSquaresBoardState> get stateStream => _controller.stream;

  @override
  DotSquaresBoardState get currentState => _state;

  @override
  Future<void> place(int position) async {
    // Prédiction locale immédiate (voir RemoteMemoryGameTransport.flip pour
    // le principe) — déterministe ici (pas de tirage aléatoire dans
    // DotSquaresEngine), donc toujours identique au résultat serveur tant
    // que l'état local était à jour.
    try {
      final result = DotSquaresEngine.place(
        points: _state.points,
        rectangles: _state.rectangles,
        scoresByUser: _state.scoresByUser,
        position: position,
        userId: myUserId,
        otherUserId: partnerUserId,
        movesCount: _state.movesCount,
        cols: _state.gridCols,
      );
      _state = _state.copyWith(
        points: result.points,
        rectangles: result.rectangles,
        scoresByUser: result.scoresByUser,
        currentTurnUserId: result.currentTurnUserId,
        winnerUserId: result.winnerUserId,
        isTie: result.isTie,
        movesCount: result.movesCount,
        finished: result.finished,
        newlyScored: result.newlyScored,
      );
      _controller.add(_state);
    } catch (_) {
      // Coup localement invalide — le serveur tranchera.
    }

    try {
      final session = await GameService.instance.playDotSquaresMove(sessionId, position);
      _applyServerState(session);
    } catch (_) {
      try {
        final session = await GameService.instance.fetchDotSquaresState(sessionId);
        _applyServerState(session);
      } catch (_) {
        // best effort — voir doc de classe RealtimeClient.
      }
    }
  }

  @override
  Future<void> requestClose() async {
    final session = await GameService.instance.requestCloseDotSquares(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> cancelCloseRequest() async {
    if (!_state.closeRequestedByMe) return;
    final session = await GameService.instance.cancelCloseDotSquares(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> abandon() async {
    final session = await GameService.instance.abandonDotSquares(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> pause() async {
    // Application immédiate côté local (voir demande utilisateur) — le
    // binôme le verra dès que le broadcast lui parvient, pas la peine
    // d'attendre la réponse serveur pour geler l'écran ici.
    _state = _state.copyWith(pausedByUserId: myUserId, pausedAt: DateTime.now());
    _controller.add(_state);

    final session = await GameService.instance.pauseDotSquares(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> resume() async {
    // Réservé à qui a posé la pause — SAUF une pause posée automatiquement par un solde épuisé
    // (voir AuthorizesResume côté serveur : pausedByUserId reste alors NULL, n'importe quel
    // participant peut tenter de la lever, le serveur revérifie lui-même le solde du payeur).
    if (!_state.pausedByMe && _state.pausedByUserId != null) return;
    final session = await GameService.instance.resumeDotSquares(sessionId);
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
