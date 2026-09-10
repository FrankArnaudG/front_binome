import 'dart:async';

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

  String get _friendChannelName => 'suit-battle-session.$sessionId';

  RemoteSuitBattleTransport({
    required SuitBattleSession session,
    required this.boxId,
    required this.myUserId,
    required this.creatorId,
    required this.partnerId,
  }) : sessionId = session.id {
    _state = _stateFrom(session);
    final box = boxId;
    if (box != null) {
      RealtimeClient.instance.subscribeToBox(box, onEvent: _onRealtimeEvent);
    } else {
      RealtimeClient.instance.subscribePrivate(_friendChannelName, onEvent: _onRealtimeEvent);
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

    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Stream<SuitBattleBoardState> get stateStream => _controller.stream;

  @override
  SuitBattleBoardState get currentState => _state;

  @override
  Future<void> shuffleDeck() async {
    final session = await GameService.instance.shuffleSuitBattle(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> dealAutomatic() async {
    final session = await GameService.instance.dealAutoSuitBattle(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> readyUp() async {
    final session = await GameService.instance.readyUpSuitBattle(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
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
        final winnerIsCreator = outcome.winnerId == creatorId;
        _state = _state.copyWith(
          spreadCreator: _state.iAmCreator ? outcome.spread : _state.spreadCreator,
          spreadPartner: _state.iAmCreator ? _state.spreadPartner : outcome.spread,
          wonCreator: winnerIsCreator ? outcome.wonPile : _state.wonCreator,
          wonPartner: winnerIsCreator ? _state.wonPartner : outcome.wonPile,
          turnUserId: outcome.winnerId,
          phase: 'lead',
          roundsCount: outcome.roundsCount,
          winnerUserId: outcome.winnerUserId,
          finished: outcome.finished,
          clearTable: true,
        );
        _controller.add(_state);
      }
    } catch (_) {
      // Coup localement invalide — le serveur tranchera.
    }

    await _syncWith(() => GameService.instance.respondSuitBattle(sessionId, card));
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
          responderWonPile: userId == creatorId ? _state.wonCreator : _state.wonPartner,
          roundsCount: _state.roundsCount,
        );
        final responderIsCreator = userId == creatorId;
        _state = _state.copyWith(
          wonCreator: responderIsCreator ? outcome.wonPile : _state.wonCreator,
          wonPartner: responderIsCreator ? _state.wonPartner : outcome.wonPile,
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
      _state = _stateFrom(session);
      _controller.add(_state);
    } catch (_) {
      try {
        final session = await GameService.instance.fetchSuitBattleState(sessionId);
        _state = _stateFrom(session);
        _controller.add(_state);
      } catch (_) {
        // best effort — voir doc de classe RealtimeClient.
      }
    }
  }

  @override
  Future<void> abandon() async {
    final session = await GameService.instance.abandonSuitBattle(sessionId);
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

    final session = await GameService.instance.pauseSuitBattle(sessionId);
    _state = _stateFrom(session);
    _controller.add(_state);
  }

  @override
  Future<void> resume() async {
    if (!_state.pausedByMe) return;
    final session = await GameService.instance.resumeSuitBattle(sessionId);
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
