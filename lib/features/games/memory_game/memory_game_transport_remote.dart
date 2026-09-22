import 'dart:async';

import '../../../core/game_sync_log.dart';
import '../../../core/realtime_client.dart';
import '../../../models/memory_game_session.dart';
import '../game_service.dart';
import 'memory_game_engine.dart';
import 'memory_game_transport.dart';

/// Mode "à distance" — synchronisation via le backend (REST pour les
/// actions, WebSocket Reverb pour recevoir les coups de l'autre). Chaque
/// action locale (flip/abandon) met aussi à jour l'état à partir de la
/// réponse HTTP directement (pas seulement en attendant l'event WS) : sur
/// SA PROPRE action, pas besoin d'attendre un aller-retour réseau
/// supplémentaire pour se sentir réactif.
class RemoteMemoryGameTransport extends MemoryGameTransport {
  final String sessionId;
  // `null` pour une partie hors-Box (défi à un ami de jeu via son code,
  // voir demande utilisateur) — le canal temps réel devient alors
  // [_friendChannelName] (dédié à CETTE session) plutôt que le canal de la
  // Box, voir le constructeur.
  final String? boxId;
  final String myUserId;
  final String partnerUserId;
  final _controller = StreamController<MemoryGameBoardState>.broadcast();
  late MemoryGameBoardState _state;
  // Retournements à MOI encore en vol vers le serveur. Tant qu'il y en a, on
  // n'applique aucune réponse/évènement serveur en retard : ils décrivent un
  // état DÉJÀ dépassé par notre prédiction locale, et l'appliquer refermait
  // la carte qu'on venait de retourner puis la rouvrait (voir demande
  // utilisateur : "elle se retourne, se referme immédiatement et se rouvre").
  int _pendingFlips = 0;
  bool _skippedEventWhilePending = false;
  // Filet de sécurité : un évènement temps réel manqué (coupure réseau, app en arrière-plan) laissait
  // ce téléphone figé sur un état ancien alors que l'autre avait déjà fini la partie (voir demande
  // utilisateur : "un téléphone revient en arrière"). On recale donc régulièrement sur le serveur.
  Timer? _resyncTimer;
  StreamSubscription<void>? _resyncSub;
  // Dernière version serveur appliquée (voir HasStateVersion) : tout état plus ancien est ignoré.
  int _version = 0;

  String get _friendChannelName => 'memory-game-session.$sessionId';

  RemoteMemoryGameTransport({
    required MemoryGameSession session,
    required this.boxId,
    required this.myUserId,
    required this.partnerUserId,
  }) : sessionId = session.id {
    _state = _stateFrom(session);
    _version = session.version;
    _stateReady = true;
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
  /// être appliqué : il faisait revenir l'écran en arrière. Une partie terminée passe toujours (le
  /// serveur vide alors certains champs, voir [_stateFrom]).
  bool _isStale(MemoryGameSession session) {
    if (session.version > 0 && _version > 0) return session.version < _version;
    return !(session.isFinished || session.abandoned) && session.movesCount < _state.movesCount;
  }

  /// Vérifie qu'un état serveur n'est pas plus ancien que celui affiché ; sinon le trace et le refuse.
  bool _acceptVersion(MemoryGameSession session) {
    if (_isStale(session)) {
      logStaleGameState('memory_game', incoming: session.version, current: _version);
      return false;
    }
    if (session.version > _version) _version = session.version;
    return true;
  }

  void _applyServerState(MemoryGameSession session) {
    if (!_acceptVersion(session)) return;
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  Future<void> _resyncIfBehind() async {
    if (_state.finished || _pendingFlips > 0) return;
    try {
      final session = await GameService.instance.fetchMemoryGameState(sessionId);
      if (_pendingFlips > 0 || _controller.isClosed || _state.finished) return;
      final behind = session.version > _version ||
          session.movesCount > _state.movesCount ||
          ((session.isFinished || session.abandoned) && !_state.finished);
      if (!behind) return;
      _applyServerState(session);
    } catch (_) {
      // best effort — on retente au prochain tour.
    }
  }

  bool _stateReady = false;

  MemoryGameBoardState _stateFrom(MemoryGameSession session, {List<int>? mismatch}) {
    // Le serveur VIDE le plateau, les paires et les coups une fois la partie
    // terminée/abandonnée (voir MemoryGameController::flip) : recevoir un tel
    // état (resynchronisation, évènement tardif) faisait retomber l'écran sur
    // "En attente de la partie…" au lieu du tableau final. On garde alors ce
    // qu'on avait déjà en mémoire.
    final cleared = _stateReady && (session.board == null || session.board!.isEmpty);
    return _buildState(session, mismatch: mismatch, keepPrevious: cleared);
  }

  MemoryGameBoardState _buildState(MemoryGameSession session, {List<int>? mismatch, bool keepPrevious = false}) =>
      MemoryGameBoardState(
        board: keepPrevious ? _state.board : (session.board ?? const []),
        matched: keepPrevious ? _state.matched : session.matched,
        flipped: session.flipped,
        mismatch: mismatch,
        currentTurnUserId: session.currentTurnUserId,
        movesCount: session.movesCount,
        movesByUser: keepPrevious ? _state.movesByUser : session.movesByUser,
        finished: session.isFinished || session.abandoned,
        abandoned: session.abandoned,
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

    if (_pendingFlips > 0) {
      _skippedEventWhilePending = true;
      return;
    }
    if (!_acceptVersion(session)) return;

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
    _pendingFlips++;
    // Prédiction locale immédiate avec le même moteur que les modes
    // Nearby/pass-and-play (voir MemoryGameEngine) — sur SON PROPRE clic on
    // n'attend JAMAIS l'aller-retour réseau (voir demande utilisateur : "ne
    // jamais patienter lorsque c'est moi qui clique", le bouton semblait
    // mort le temps de la requête, poussant à cliquer plusieurs fois).
    // Sans risque de divergence ici : ce chemin n'est atteint que si c'est
    // déjà mon tour (voir MemoryGameBoardScreen._onTapCard), donc aucun coup
    // adverse concurrent ne peut légitimement arriver entre-temps.
    try {
      final result = MemoryGameEngine.flip(
        board: _state.board,
        matched: _state.matched,
        flipped: _state.flipped,
        currentTurnUserId: _state.currentTurnUserId ?? myUserId,
        movesCount: _state.movesCount,
        movesByUser: _state.movesByUser,
        index: index,
        userId: myUserId,
        otherUserId: partnerUserId,
      );
      _state = _state.copyWith(
        matched: result.matched,
        flipped: result.flipped,
        mismatch: result.mismatch,
        clearMismatch: result.mismatch == null,
        currentTurnUserId: result.currentTurnUserId,
        movesCount: result.movesCount,
        movesByUser: result.movesByUser,
        finished: result.finished,
      );
      _controller.add(_state);
    } catch (_) {
      // Coup localement invalide (état déjà périmé) — laisse le serveur
      // trancher ci-dessous plutôt que d'empêcher l'appel.
    }

    var needsResync = false;
    try {
      final session = await GameService.instance.flipMemoryCard(sessionId, index);
      // Seule la réponse du DERNIER retournement en vol fait foi : les
      // précédentes sont déjà périmées par la prédiction locale suivante.
      if (_pendingFlips == 1) {
        _applyServerState(session);
      }
    } catch (_) {
      // Échec réseau/refus serveur : on resynchronise ci-dessous (une fois
      // tous les retournements en vol terminés).
      needsResync = true;
    } finally {
      _pendingFlips--;
    }

    // Partie terminée : le serveur vide le plateau juste après la réponse,
    // rien à resynchroniser (et surtout pas un état vidé).
    if (_pendingFlips == 0 && !_state.finished && (needsResync || _skippedEventWhilePending)) {
      _skippedEventWhilePending = false;
      try {
        final session = await GameService.instance.fetchMemoryGameState(sessionId);
        if (_pendingFlips == 0) {
          _applyServerState(session);
        }
      } catch (_) {
        // best effort — voir doc de classe RealtimeClient, jamais de crash
        // pour une indisponibilité réseau passagère.
      }
    }
  }

  @override
  Future<void> abandon() async {
    final session = await GameService.instance.abandonMemoryGame(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> pause() async {
    // Application immédiate côté local (voir demande utilisateur) — le
    // binôme le verra dès que le broadcast lui parvient, pas la peine
    // d'attendre la réponse serveur pour geler l'écran ici.
    _state = _state.copyWith(pausedByUserId: myUserId, pausedAt: DateTime.now());
    _controller.add(_state);

    final session = await GameService.instance.pauseMemoryGame(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> resume() async {
    // Réservé à qui a posé la pause — le backend renvoie 403 sinon (voir
    // MemoryGameController::resume) ; l'UI ne propose de toute façon jamais
    // ce bouton à l'autre (voir MemoryGameBoardState.pausedByMe), donc
    // n'appeler l'API que dans le cas déjà autorisé.
    // Réservé à qui a posé la pause — SAUF une pause posée automatiquement par un solde épuisé
    // (voir AuthorizesResume côté serveur : pausedByUserId reste alors NULL, n'importe quel
    // participant peut tenter de la lever, le serveur revérifie lui-même le solde du payeur).
    if (!_state.pausedByMe && _state.pausedByUserId != null) return;
    final session = await GameService.instance.resumeMemoryGame(sessionId);
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
