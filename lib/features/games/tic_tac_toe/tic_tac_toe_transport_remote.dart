import 'dart:async';

import '../../../core/game_sync_log.dart';
import '../../../core/realtime_client.dart';
import '../../../models/tic_tac_toe_session.dart';
import '../game_service.dart';
import 'tic_tac_toe_engine.dart';
import 'tic_tac_toe_transport.dart';

/// Mode "à distance" — synchronisation via le backend (REST pour les
/// actions, WebSocket Reverb pour recevoir les coups de l'autre) — copie
/// structurelle conforme de RemoteMemoryGameTransport.
class RemoteTicTacToeTransport extends TicTacToeTransport {
  final String sessionId;
  // `null` pour une partie hors-Box (défi à un ami de jeu via son code,
  // voir demande utilisateur) — le canal temps réel devient alors
  // [_friendChannelName] (dédié à CETTE session) plutôt que le canal de la
  // Box, voir le constructeur.
  final String? boxId;
  final String myUserId;
  final String partnerUserId;
  final _controller = StreamController<TicTacToeBoardState>.broadcast();
  late TicTacToeBoardState _state;

  // Filet de sécurité : un évènement temps réel manqué (coupure réseau, app en arrière-plan) laissait ce
  // téléphone figé sur un état ancien alors que l'autre avait avancé (voir demande utilisateur : "un
  // téléphone revient en arrière"). On recale donc régulièrement sur le serveur.
  Timer? _resyncTimer;
  StreamSubscription<void>? _resyncSub;
  // Dernière version serveur appliquée (voir HasStateVersion) : tout état plus ancien est ignoré.
  int _version = 0;

  String get _friendChannelName => 'tic-tac-toe-session.$sessionId';

  RemoteTicTacToeTransport({
    required TicTacToeSession session,
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
  bool _isStale(TicTacToeSession session) {
    if (session.version > 0 && _version > 0) return session.version < _version;
    return !(session.isFinished || session.abandoned) && session.movesCount < _state.movesCount;
  }

  /// Vérifie qu'un état serveur n'est pas plus ancien que celui affiché ; sinon le trace et le refuse.
  bool _acceptVersion(TicTacToeSession session) {
    if (_isStale(session)) {
      logStaleGameState('tic_tac_toe', incoming: session.version, current: _version);
      return false;
    }
    if (session.version > _version) _version = session.version;
    return true;
  }

  void _applyServerState(TicTacToeSession session) {
    if (!_acceptVersion(session)) return;
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  Future<void> _resyncIfBehind() async {
    if (_state.finished) return;
    try {
      final session = await GameService.instance.fetchTicTacToeState(sessionId);
      if (_controller.isClosed || _state.finished) return;
      final behind = session.version > _version || session.movesCount > _state.movesCount || ((session.isFinished || session.abandoned) && !_state.finished);
      if (!behind) return;
      _applyServerState(session);
    } catch (_) {
      // best effort — on retente au prochain tour.
    }
  }

  TicTacToeBoardState _stateFrom(
    TicTacToeSession session, {
    List<int>? scoredLine,
    List<String?>? preScatterBoard,
  }) =>
      TicTacToeBoardState(
        board: session.board,
        piecesRemainingByUser: session.piecesRemainingByUser,
        scoresByUser: session.scoresByUser,
        targetScore: session.targetScore,
        currentTurnUserId: session.currentTurnUserId,
        winnerUserId: session.winnerUserId,
        isDraw: session.isDraw,
        movesCount: session.movesCount,
        finished: session.isFinished || session.abandoned,
        abandoned: session.abandoned,
        startedAt: session.startedAt,
        myUserId: myUserId,
        pausedByUserId: session.pausedByUserId,
        pausedAt: session.pausedAt,
        scoredLine: scoredLine,
        preScatterBoard: preScatterBoard,
      );

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.event != 'TicTacToeUpdated') return;
    final data = event.data;
    if (data == null) return;

    final session = TicTacToeSession.fromJson(data['session'] as Map<String, dynamic>);
    // Un event peut concerner une AUTRE partie de morpion du même box si
    // plusieurs étaient lancées coup sur coup — ignoré si ce n'est pas la
    // nôtre, même principe que RemoteMemoryGameTransport.
    if (session.id != sessionId) return;
    if (!_acceptVersion(session)) return;

    _state = _stateFrom(
      session,
      scoredLine: (data['scored_line'] as List?)?.map((e) => e as int).toList(),
      preScatterBoard: (data['pre_scatter_board'] as List?)?.map((e) => e as String?).toList(),
    );
    _controller.add(_state);
  }

  @override
  Stream<TicTacToeBoardState> get stateStream => _controller.stream;

  @override
  TicTacToeBoardState get currentState => _state;

  // Prédiction locale immédiate (voir RemoteMemoryGameTransport.flip pour le
  // même principe et sa justification) — sûre uniquement parce que ce
  // chemin n'est atteint que si c'est déjà mon tour (voir
  // TicTacToeBoardScreen), donc jamais de coup adverse concurrent à prévoir.
  // La dispersion aléatoire après alignement peut différer de celle du
  // serveur : sans conséquence visible, la réponse HTTP arrive presque
  // aussitôt et écrase cette prédiction avec l'état réel.
  void _applyOptimistic(TicTacToeMoveResult result) {
    _state = _state.copyWith(
      board: result.board,
      piecesRemainingByUser: result.piecesRemainingByUser,
      scoresByUser: result.scoresByUser,
      currentTurnUserId: result.currentTurnUserId,
      winnerUserId: result.winnerUserId,
      movesCount: result.movesCount,
      finished: result.finished,
      scoredLine: result.scoredLine,
      preScatterBoard: result.preScatterBoard,
    );
    _controller.add(_state);
  }

  Future<void> _resyncAfterFailure() async {
    try {
      final session = await GameService.instance.fetchTicTacToeState(sessionId);
      _applyServerState(session);
    } catch (_) {
      // best effort — voir doc de classe RealtimeClient.
    }
  }

  @override
  Future<void> place(int position) async {
    try {
      _applyOptimistic(TicTacToeEngine.place(
        board: _state.board,
        piecesRemainingByUser: _state.piecesRemainingByUser,
        scoresByUser: _state.scoresByUser,
        position: position,
        userId: myUserId,
        otherUserId: partnerUserId,
        movesCount: _state.movesCount,
      ));
    } catch (_) {
      // Coup localement invalide — le serveur tranchera.
    }

    try {
      final result = await GameService.instance.playTicTacToeMove(sessionId, to: position);
      _state = _stateFrom(result.session, scoredLine: result.scoredLine, preScatterBoard: result.preScatterBoard);
      _controller.add(_state);
    } catch (_) {
      await _resyncAfterFailure();
    }
  }

  @override
  Future<void> move(int from, int to) async {
    try {
      _applyOptimistic(TicTacToeEngine.move(
        board: _state.board,
        piecesRemainingByUser: _state.piecesRemainingByUser,
        scoresByUser: _state.scoresByUser,
        from: from,
        to: to,
        userId: myUserId,
        otherUserId: partnerUserId,
        movesCount: _state.movesCount,
      ));
    } catch (_) {
      // Coup localement invalide — le serveur tranchera.
    }

    try {
      final result = await GameService.instance.playTicTacToeMove(sessionId, to: to, from: from);
      _state = _stateFrom(result.session, scoredLine: result.scoredLine, preScatterBoard: result.preScatterBoard);
      _controller.add(_state);
    } catch (_) {
      await _resyncAfterFailure();
    }
  }

  @override
  Future<void> abandon() async {
    final session = await GameService.instance.abandonTicTacToe(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> pause() async {
    // Application immédiate côté local (voir demande utilisateur) — le
    // binôme le verra dès que le broadcast lui parvient, pas la peine
    // d'attendre la réponse serveur pour geler l'écran ici.
    _state = _state.copyWith(pausedByUserId: myUserId, pausedAt: DateTime.now());
    _controller.add(_state);

    final session = await GameService.instance.pauseTicTacToe(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> resume() async {
    // Réservé à qui a posé la pause — le backend renvoie 403 sinon (voir
    // TicTacToeController::resume) ; l'UI ne propose de toute façon jamais
    // ce bouton à l'autre.
    // Réservé à qui a posé la pause — SAUF une pause posée automatiquement par un solde épuisé
    // (voir AuthorizesResume côté serveur : pausedByUserId reste alors NULL, n'importe quel
    // participant peut tenter de la lever, le serveur revérifie lui-même le solde du payeur).
    if (!_state.pausedByMe && _state.pausedByUserId != null) return;
    final session = await GameService.instance.resumeTicTacToe(sessionId);
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
