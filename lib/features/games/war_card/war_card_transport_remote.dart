import 'dart:async';

import '../../../core/game_sync_log.dart';
import '../../../core/realtime_client.dart';
import '../../../models/war_card_session.dart';
import '../game_service.dart';
import 'war_card_engine.dart';
import 'war_card_transport.dart';

/// Mode "à distance" — synchronisation via le backend (REST pour les
/// taps, WebSocket Reverb pour recevoir ceux du binôme). Le serveur ne
/// résout la manche que quand LES DEUX ont tapé (voir
/// WarCardController::flip, verrouillage de ligne) — copie structurelle
/// conforme des autres jeux à distance.
class RemoteWarCardTransport extends WarCardTransport {
  final String sessionId;
  // `null` pour une partie hors-Box (défi à un ami de jeu via son code,
  // voir demande utilisateur) — le canal temps réel devient alors
  // [_friendChannelName] (dédié à CETTE session) plutôt que le canal de la
  // Box, voir le constructeur.
  final String? boxId;
  final String myUserId;
  final String creatorId;
  final String partnerId;
  final _controller = StreamController<WarCardBoardState>.broadcast();
  late WarCardBoardState _state;

  // Filet de sécurité : un évènement temps réel manqué (coupure réseau, app en arrière-plan) laissait ce
  // téléphone figé sur un état ancien alors que l'autre avait avancé (voir demande utilisateur : "un
  // téléphone revient en arrière"). On recale donc régulièrement sur le serveur.
  Timer? _resyncTimer;
  StreamSubscription<void>? _resyncSub;
  // Dernière version serveur appliquée (voir HasStateVersion) : tout état plus ancien est ignoré.
  int _version = 0;

  String get _friendChannelName => 'war-card-session.$sessionId';

  RemoteWarCardTransport({
    required WarCardSession session,
    required this.boxId,
    required this.myUserId,
    required this.creatorId,
    required this.partnerId,
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
  bool _isStale(WarCardSession session) {
    if (session.version > 0 && _version > 0) return session.version < _version;
    return !(session.isFinished || session.abandoned) && session.roundsCount < _state.roundsCount;
  }

  /// Vérifie qu'un état serveur n'est pas plus ancien que celui affiché ; sinon le trace et le refuse.
  bool _acceptVersion(WarCardSession session) {
    if (_isStale(session)) {
      logStaleGameState('war_card', incoming: session.version, current: _version);
      return false;
    }
    if (session.version > _version) _version = session.version;
    return true;
  }

  void _applyServerState(WarCardSession session) {
    if (!_acceptVersion(session)) return;
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  Future<void> _resyncIfBehind() async {
    if (_state.finished) return;
    try {
      final session = await GameService.instance.fetchWarCardState(sessionId);
      if (_controller.isClosed || _state.finished) return;
      final behind = session.version > _version || session.roundsCount > _state.roundsCount || ((session.isFinished || session.abandoned) && !_state.finished);
      if (!behind) return;
      _applyServerState(session);
    } catch (_) {
      // best effort — on retente au prochain tour.
    }
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
        abandoned: session.abandoned,
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
    if (!_acceptVersion(session)) return;

    _applyServerState(session);
  }

  @override
  Stream<WarCardBoardState> get stateStream => _controller.stream;

  @override
  WarCardBoardState get currentState => _state;

  @override
  Future<void> shuffleDeck() async {
    final session = await GameService.instance.shuffleWarCard(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> dealAutomatic() async {
    final session = await GameService.instance.dealAutoWarCard(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> dealManualStep() async {
    final session = await GameService.instance.dealManualWarCard(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> readyUp() async {
    final session = await GameService.instance.readyUpWarCard(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> flip(String userId) async {
    // Prédiction locale immédiate (voir RemoteMemoryGameTransport.flip) —
    // le cas fréquent (je suis le/la premier·ère à taper) est déterministe
    // (ne fait que marquer mon propre "pendingFlip"). Si les deux ont déjà
    // tapé, la manche se résout avec un mélange aléatoire qui peut différer
    // du résultat serveur — sans conséquence visible, la réponse HTTP
    // arrive presque aussitôt et écrase cette prédiction. `battlePot` est
    // toujours vide entre deux appels (voir WarCardEngine._resolveRound,
    // qui le vide systématiquement avant de retourner), donc sûr de passer
    // `const []` ici même si l'état affiché ne le porte pas.
    try {
      final outcome = WarCardEngine.flip(
        pileCreator: _state.pileCreator,
        pilePartner: _state.pilePartner,
        pendingFlipCreator: _state.pendingFlipCreator,
        pendingFlipPartner: _state.pendingFlipPartner,
        battlePot: const [],
        roundsCount: _state.roundsCount,
        userId: myUserId,
        creatorId: creatorId,
        partnerId: partnerId,
      );
      _state = _state.copyWith(
        pileCreator: outcome.pileCreator,
        pilePartner: outcome.pilePartner,
        pendingFlipCreator: outcome.pendingFlipCreator,
        pendingFlipPartner: outcome.pendingFlipPartner,
        lastRoundResult: outcome.lastRoundResult,
        roundsCount: outcome.roundsCount,
        winnerUserId: outcome.winnerUserId,
        isTie: outcome.isTie,
        finished: outcome.finished,
      );
      _controller.add(_state);
    } catch (_) {
      // Coup localement invalide — le serveur tranchera.
    }

    try {
      final result = await GameService.instance.flipWarCard(sessionId);
      _applyServerState(result.session);
    } catch (_) {
      try {
        final session = await GameService.instance.fetchWarCardState(sessionId);
        _applyServerState(session);
      } catch (_) {
        // best effort — voir doc de classe RealtimeClient.
      }
    }
  }

  @override
  Future<void> shufflePile(String userId) async {
    final session = await GameService.instance.shufflePileWarCard(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> abandon() async {
    final session = await GameService.instance.abandonWarCard(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> pause() async {
    // Application immédiate côté local (voir demande utilisateur) — le
    // binôme le verra dès que le broadcast lui parvient, pas la peine
    // d'attendre la réponse serveur pour geler l'écran ici.
    _state = _state.copyWith(pausedByUserId: myUserId, pausedAt: DateTime.now());
    _controller.add(_state);

    final session = await GameService.instance.pauseWarCard(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> resume() async {
    // Réservé à qui a posé la pause — SAUF une pause posée automatiquement par un solde épuisé
    // (voir AuthorizesResume côté serveur : pausedByUserId reste alors NULL, n'importe quel
    // participant peut tenter de la lever, le serveur revérifie lui-même le solde du payeur).
    if (!_state.pausedByMe && _state.pausedByUserId != null) return;
    final session = await GameService.instance.resumeWarCard(sessionId);
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
