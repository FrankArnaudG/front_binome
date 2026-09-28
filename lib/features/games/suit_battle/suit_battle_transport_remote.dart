import 'dart:async';

import '../../../core/game_sync_log.dart';
import '../../../core/realtime_client.dart';
import '../../../models/suit_battle_session.dart';
import '../game_service.dart';
import 'suit_battle_engine.dart';
import 'suit_battle_transport.dart';

/// Mode "à distance" — synchronisation via le backend (REST pour les
/// coups, WebSocket Reverb pour recevoir ceux du binôme). Le serveur fait
/// autorité (voir SuitBattleController) — copie structurelle conforme des
/// autres jeux à distance.
class RemoteSuitBattleTransport extends SuitBattleTransport {
  final String sessionId;
  // `null` pour une partie hors-Box (défi à un ami de jeu via son code,
  // voir demande utilisateur) — le canal temps réel devient alors
  // [_friendChannelName] (dédié à CETTE session) plutôt que le canal de la
  // Box, voir le constructeur.
  final String? boxId;
  final String myUserId;
  final String creatorId;
  final String partnerId;
  final _controller = StreamController<SuitBattleBoardState>.broadcast();
  late SuitBattleBoardState _state;

  // Filet de sécurité : un évènement temps réel manqué (coupure réseau, app en arrière-plan) laissait ce
  // téléphone figé sur un état ancien alors que l'autre avait avancé (voir demande utilisateur : "un
  // téléphone revient en arrière"). On recale donc régulièrement sur le serveur.
  Timer? _resyncTimer;
  StreamSubscription<void>? _resyncSub;
  // Dernière version serveur appliquée (voir HasStateVersion) : tout état plus ancien est ignoré.
  int _version = 0;

  String get _friendChannelName => 'suit-battle-session.$sessionId';

  RemoteSuitBattleTransport({
    required SuitBattleSession session,
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
  bool _isStale(SuitBattleSession session) {
    if (session.version > 0 && _version > 0) return session.version < _version;
    return !(session.isFinished || session.abandoned) && session.roundsCount < _state.roundsCount;
  }

  /// Vérifie qu'un état serveur n'est pas plus ancien que celui affiché ; sinon le trace et le refuse.
  bool _acceptVersion(SuitBattleSession session) {
    if (_isStale(session)) {
      logStaleGameState('suit_battle', incoming: session.version, current: _version);
      return false;
    }
    if (session.version > _version) _version = session.version;
    return true;
  }

  void _applyServerState(SuitBattleSession session) {
    if (!_acceptVersion(session)) return;
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  Future<void> _resyncIfBehind() async {
    if (_state.finished) return;
    try {
      final session = await GameService.instance.fetchSuitBattleState(sessionId);
      if (_controller.isClosed || _state.finished) return;
      final behind = session.version > _version || session.roundsCount > _state.roundsCount || ((session.isFinished || session.abandoned) && !_state.finished);
      if (!behind) return;
      _applyServerState(session);
    } catch (_) {
      // best effort — on retente au prochain tour.
    }
  }

  SuitBattleBoardState _stateFrom(SuitBattleSession session) => SuitBattleBoardState(
        deck: session.deck,
        dealt: session.dealt,
        readyCreator: session.readyCreator,
        readyPartner: session.readyPartner,
        started: session.started,
        spreadCreator: session.spreadCreator ?? const [],
        spreadPartner: session.spreadPartner ?? const [],
        wonCreator: session.wonCreator,
        wonPartner: session.wonPartner,
        tableCard: session.tableCard,
        tableOwnerUserId: session.tableOwnerUserId,
        responseCard: session.responseCard,
        pendingRoundWinnerId: session.pendingRoundWinnerId,
        turnUserId: session.turnUserId,
        phase: session.phase,
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
    if (event.event != 'SuitBattleUpdated') return;
    final data = event.data;
    if (data == null) return;

    final session = SuitBattleSession.fromJson(data['session'] as Map<String, dynamic>);
    if (session.id != sessionId) return;
    if (!_acceptVersion(session)) return;

    _applyServerState(session);
  }

  @override
  Stream<SuitBattleBoardState> get stateStream => _controller.stream;

  @override
  SuitBattleBoardState get currentState => _state;

  @override
  Future<void> shuffleDeck() async {
    final session = await GameService.instance.shuffleSuitBattle(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> dealAutomatic() async {
    final session = await GameService.instance.dealAutoSuitBattle(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> readyUp() async {
    final session = await GameService.instance.readyUpSuitBattle(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> playLead(String userId, String card) async {
    // Prédiction locale immédiate (voir RemoteWarCardTransport.flip) — le
    // coup ne dépend d'aucun aléa, la prédiction est donc TOUJOURS
    // identique au résultat serveur (contrairement au mélange de
    // WarCardEngine) ; la réponse HTTP écrase quand même cet état dès
    // qu'elle arrive, par sécurité si le serveur avait un état plus
    // récent que le nôtre.
    try {
      final otherUserId = myUserId == creatorId ? partnerId : creatorId;
      final outcome = SuitBattleEngine.playLead(
        spread: _state.mySpread,
        userId: userId,
        card: card,
        otherUserId: otherUserId,
      );
      _state = _state.copyWith(
        spreadCreator: _state.iAmCreator ? outcome.spread : _state.spreadCreator,
        spreadPartner: _state.iAmCreator ? _state.spreadPartner : outcome.spread,
        tableCard: outcome.tableCard,
        tableOwnerUserId: outcome.tableOwnerUserId,
        turnUserId: outcome.turnUserId,
        phase: 'response',
        winnerUserId: outcome.winnerUserId,
        finished: outcome.finished,
      );
      _controller.add(_state);
    } catch (_) {
      // Coup localement invalide — le serveur tranchera.
    }

    await _syncWith(() => GameService.instance.playLeadSuitBattle(sessionId, card));
  }

  @override
  Future<void> respondCard(String userId, String card) async {
    try {
      final tableCard = _state.tableCard;
      final leaderId = _state.tableOwnerUserId;
      if (tableCard != null && leaderId != null) {
        final outcome = SuitBattleEngine.respondCard(
          spread: _state.mySpread,
          userId: userId,
          card: card,
          tableCard: tableCard,
          leaderId: leaderId,
          leaderWonPile: leaderId == creatorId ? _state.wonCreator : _state.wonPartner,
          responderWonPile: userId == creatorId ? _state.wonCreator : _state.wonPartner,
          roundsCount: _state.roundsCount,
        );
        if (outcome.finished) {
          // Fin de partie sur cette carte : fusion immédiate, pas de pause
          // "reveal" (voir doc de classe SuitBattleRespondOutcome).
          final winnerIsCreator = outcome.winnerId == creatorId;
          _state = _state.copyWith(
            spreadCreator: _state.iAmCreator ? outcome.spread : _state.spreadCreator,
            spreadPartner: _state.iAmCreator ? _state.spreadPartner : outcome.spread,
            wonCreator: winnerIsCreator ? outcome.mergedWonPile : _state.wonCreator,
            wonPartner: winnerIsCreator ? _state.wonPartner : outcome.mergedWonPile,
            turnUserId: outcome.winnerId,
            phase: 'lead',
            roundsCount: outcome.roundsCount,
            winnerUserId: outcome.winnerUserId,
            finished: true,
            clearTable: true,
          );
        } else {
          // Voir demande utilisateur : "les deux cartes sorties se
          // disposent côte à côte... un bouton Balayer" — la carte du
          // répondant reste visible à côté de `tableCard` jusqu'au
          // balayage explicite (voir sweepExchange).
          _state = _state.copyWith(
            spreadCreator: _state.iAmCreator ? outcome.spread : _state.spreadCreator,
            spreadPartner: _state.iAmCreator ? _state.spreadPartner : outcome.spread,
            responseCard: outcome.card,
            pendingRoundWinnerId: outcome.winnerId,
            phase: 'reveal',
            roundsCount: outcome.roundsCount,
          );
        }
        _controller.add(_state);
      }
    } catch (_) {
      // Coup localement invalide — le serveur tranchera.
    }

    await _syncWith(() => GameService.instance.respondSuitBattle(sessionId, card));
  }

  @override
  Future<void> sweepExchange() async {
    try {
      final tableCard = _state.tableCard;
      final responseCard = _state.responseCard;
      final winnerId = _state.pendingRoundWinnerId;
      if (tableCard != null && responseCard != null && winnerId != null) {
        final winnerIsCreator = winnerId == creatorId;
        final mergedWonPile = SuitBattleEngine.sweepExchange(
          tableCard: tableCard,
          responseCard: responseCard,
          currentWinnerWonPile: winnerIsCreator ? _state.wonCreator : _state.wonPartner,
        );
        _state = _state.copyWith(
          wonCreator: winnerIsCreator ? mergedWonPile : _state.wonCreator,
          wonPartner: winnerIsCreator ? _state.wonPartner : mergedWonPile,
          turnUserId: winnerId,
          phase: 'lead',
          clearTable: true,
        );
        _controller.add(_state);
      }
    } catch (_) {
      // Coup localement invalide — le serveur tranchera.
    }

    await _syncWith(() => GameService.instance.sweepSuitBattle(sessionId));
  }

  @override
  Future<void> captureLead(String userId) async {
    try {
      final tableCard = _state.tableCard;
      final leaderId = _state.tableOwnerUserId;
      if (tableCard != null && leaderId != null) {
        final outcome = SuitBattleEngine.captureLead(
          tableCard: tableCard,
          leaderId: leaderId,
          responderSpread: userId == creatorId ? _state.spreadCreator : _state.spreadPartner,
          roundsCount: _state.roundsCount,
        );
        final responderIsCreator = userId == creatorId;
        _state = _state.copyWith(
          spreadCreator: responderIsCreator ? outcome.spread : _state.spreadCreator,
          spreadPartner: responderIsCreator ? _state.spreadPartner : outcome.spread,
          turnUserId: outcome.leaderId,
          phase: 'lead',
          roundsCount: outcome.roundsCount,
          clearTable: true,
        );
        _controller.add(_state);
      }
    } catch (_) {
      // Coup localement invalide — le serveur tranchera.
    }

    await _syncWith(() => GameService.instance.captureLeadSuitBattle(sessionId));
  }

  Future<void> _syncWith(Future<SuitBattleSession> Function() call) async {
    try {
      final session = await call();
      _applyServerState(session);
    } catch (_) {
      try {
        final session = await GameService.instance.fetchSuitBattleState(sessionId);
        _applyServerState(session);
      } catch (_) {
        // best effort — voir doc de classe RealtimeClient.
      }
    }
  }

  @override
  Future<void> abandon() async {
    final session = await GameService.instance.abandonSuitBattle(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> pause() async {
    // Application immédiate côté local (voir demande utilisateur) — le
    // binôme le verra dès que le broadcast lui parvient, pas la peine
    // d'attendre la réponse serveur pour geler l'écran ici.
    _state = _state.copyWith(pausedByUserId: myUserId, pausedAt: DateTime.now());
    _controller.add(_state);

    final session = await GameService.instance.pauseSuitBattle(sessionId);
    _applyServerState(session);
  }

  @override
  Future<void> resume() async {
    // Réservé à qui a posé la pause — SAUF une pause posée automatiquement par un solde épuisé
    // (voir AuthorizesResume côté serveur : pausedByUserId reste alors NULL, n'importe quel
    // participant peut tenter de la lever, le serveur revérifie lui-même le solde du payeur).
    if (!_state.pausedByMe && _state.pausedByUserId != null) return;
    final session = await GameService.instance.resumeSuitBattle(sessionId);
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
