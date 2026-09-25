import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nearby_connections/nearby_connections.dart';

import 'suit_battle_engine.dart';
import 'suit_battle_transport.dart';
import '../../../core/server_clock.dart';

/// Identifiants internes des deux rôles — voir kWarCardHostRole/
/// kWarCardGuestRole, même principe (Nearby Connections n'a pas de notion
/// de compte).
const kSuitBattleHostRole = 'host';
const kSuitBattleGuestRole = 'guest';

/// Mode "présentiel connecté" — l'HÔTE est autoritaire : lui seul applique
/// SuitBattleEngine, l'invité ne fait que proposer un coup et recevoir
/// l'état à jour. Copie structurelle conforme de NearbyWarCardTransport,
/// adaptée au pattern tour par tour + phase lead/response (voir
/// SuitBattleEngine).
class NearbySuitBattleTransport extends SuitBattleTransport {
  final Nearby nearby;
  final String endpointId;
  final bool isHost;
  final _controller = StreamController<SuitBattleBoardState>.broadcast();
  late SuitBattleBoardState _state;
  List<String> _deck = [];
  List<String> _spreadHost = [];
  List<String> _spreadGuest = [];
  List<String> _wonHost = [];
  List<String> _wonGuest = [];

  /// Côté hôte : prépare le paquet (encore empilé, pas distribué) et
  /// l'envoie tout de suite à l'invité.
  NearbySuitBattleTransport.host({
    required this.nearby,
    required this.endpointId,
  }) : isHost = true {
    _deck = SuitBattleEngine.shuffledDeck();
    _state = SuitBattleBoardState(
      deck: _deck,
      myUserId: kSuitBattleHostRole,
      creatorId: kSuitBattleHostRole,
      partnerId: kSuitBattleGuestRole,
    );
    _sendInit();
  }

  /// Côté invité : état par défaut tant que le message `init` de l'hôte
  /// n'est pas arrivé.
  NearbySuitBattleTransport.guest({
    required this.nearby,
    required this.endpointId,
  }) : isHost = false {
    _state = const SuitBattleBoardState(myUserId: kSuitBattleGuestRole, creatorId: kSuitBattleHostRole, partnerId: kSuitBattleGuestRole);
  }

  void _send(Map<String, dynamic> message) {
    nearby.sendBytesPayload(endpointId, Uint8List.fromList(utf8.encode(jsonEncode(message))));
  }

  void _sendInit() {
    _send({
      'type': 'init',
      'deck': _deck,
      'dealt': _state.dealt,
      'readyCreator': _state.readyCreator,
      'readyPartner': _state.readyPartner,
      'started': _state.started,
      'spreadHost': _spreadHost,
      'spreadGuest': _spreadGuest,
      'startedAt': _state.startedAt?.toIso8601String(),
    });
  }

  void _sendState() {
    _send({
      'type': 'state',
      'deck': _deck,
      'dealt': _state.dealt,
      'readyCreator': _state.readyCreator,
      'readyPartner': _state.readyPartner,
      'started': _state.started,
      'spreadHost': _spreadHost,
      'spreadGuest': _spreadGuest,
      'wonHost': _wonHost,
      'wonGuest': _wonGuest,
      'tableCard': _state.tableCard,
      'tableOwnerUserId': _state.tableOwnerUserId,
      'responseCard': _state.responseCard,
      'pendingRoundWinnerId': _state.pendingRoundWinnerId,
      'turnUserId': _state.turnUserId,
      'phase': _state.phase,
      'roundsCount': _state.roundsCount,
      'winnerUserId': _state.winnerUserId,
      'isTie': _state.isTie,
      'finished': _state.finished,
      'abandoned': _state.abandoned,
      'startedAt': _state.startedAt?.toIso8601String(),
      'pausedByUserId': _state.pausedByUserId,
      'pausedAt': _state.pausedAt?.toIso8601String(),
    });
  }

  /// À brancher sur `Nearby().acceptConnection(endpointId,
  /// onPayLoadRecieved: transport.onPayloadReceived)`.
  void onPayloadReceived(String fromEndpointId, Payload payload) {
    if (payload.type != PayloadType.BYTES || payload.bytes == null) return;

    final message = jsonDecode(utf8.decode(payload.bytes!)) as Map<String, dynamic>;
    switch (message['type']) {
      case 'init':
        // Reçu côté invité uniquement.
        _state = SuitBattleBoardState(
          deck: (message['deck'] as List).map((e) => e as String).toList(),
          dealt: message['dealt'] as bool? ?? false,
          readyCreator: message['readyCreator'] as bool? ?? false,
          readyPartner: message['readyPartner'] as bool? ?? false,
          started: message['started'] as bool? ?? false,
          spreadCreator: (message['spreadHost'] as List).map((e) => e as String).toList(),
          spreadPartner: (message['spreadGuest'] as List).map((e) => e as String).toList(),
          startedAt: message['startedAt'] != null ? DateTime.parse(message['startedAt'] as String) : null,
          myUserId: kSuitBattleGuestRole,
          creatorId: kSuitBattleHostRole,
          partnerId: kSuitBattleGuestRole,
        );
        _controller.add(_state);
      case 'state':
        // Reçu côté invité (l'hôte fait autorité).
        final pausedByUserId = message['pausedByUserId'] as String?;
        _state = _state.copyWith(
          deck: (message['deck'] as List).map((e) => e as String).toList(),
          dealt: message['dealt'] as bool? ?? _state.dealt,
          readyCreator: message['readyCreator'] as bool? ?? _state.readyCreator,
          readyPartner: message['readyPartner'] as bool? ?? _state.readyPartner,
          started: message['started'] as bool? ?? _state.started,
          spreadCreator: (message['spreadHost'] as List).map((e) => e as String).toList(),
          spreadPartner: (message['spreadGuest'] as List).map((e) => e as String).toList(),
          wonCreator: (message['wonHost'] as List).map((e) => e as String).toList(),
          wonPartner: (message['wonGuest'] as List).map((e) => e as String).toList(),
          tableCard: message['tableCard'] as String?,
          tableOwnerUserId: message['tableOwnerUserId'] as String?,
          responseCard: message['responseCard'] as String?,
          pendingRoundWinnerId: message['pendingRoundWinnerId'] as String?,
          turnUserId: message['turnUserId'] as String?,
          phase: message['phase'] as String?,
          roundsCount: message['roundsCount'] as int,
          winnerUserId: message['winnerUserId'] as String?,
          isTie: message['isTie'] as bool,
          finished: message['finished'] as bool,
          abandoned: message['abandoned'] as bool? ?? false,
          startedAt: message['startedAt'] != null ? DateTime.parse(message['startedAt'] as String) : _state.startedAt,
          pausedByUserId: pausedByUserId,
          pausedAt: message['pausedAt'] != null ? DateTime.parse(message['pausedAt'] as String) : null,
          clearTable: message['tableCard'] == null,
          clearReveal: message['responseCard'] == null,
          clearPause: pausedByUserId == null,
        );
        _controller.add(_state);
      case 'shuffle_request':
        if (isHost) _applyHostShuffle();
      case 'deal_auto_request':
        if (isHost) _applyHostDealAuto();
      case 'ready_request':
        if (isHost) _applyHostReadyUp(kSuitBattleGuestRole);
      case 'play_lead':
        if (isHost) _applyHostPlayLead(kSuitBattleGuestRole, message['card'] as String);
      case 'respond_card':
        if (isHost) _applyHostRespondCard(kSuitBattleGuestRole, message['card'] as String);
      case 'sweep_request':
        if (isHost) _applyHostSweepExchange();
      case 'capture_lead':
        if (isHost) _applyHostCaptureLead(kSuitBattleGuestRole);
      case 'pause_request':
        if (isHost) _applyHostPause(kSuitBattleGuestRole);
      case 'resume_request':
        if (isHost) _applyHostResume(kSuitBattleGuestRole);
      case 'abandon_request':
        if (isHost) _applyHostAbandon();
    }
  }

  void _applyHostShuffle() {
    if (_state.dealt) return;
    _deck = List.of(_deck)..shuffle();
    _state = _state.copyWith(deck: _deck);
    _controller.add(_state);
    _sendState();
  }

  void _applyHostDealAuto() {
    if (_state.dealt) return;
    final result = SuitBattleEngine.dealAutomatic(_deck);
    _spreadHost = result.spreadCreator;
    _spreadGuest = result.spreadPartner;
    _deck = [];
    _state = _state.copyWith(deck: _deck, spreadCreator: _spreadHost, spreadPartner: _spreadGuest, dealt: true);
    _controller.add(_state);
    _sendState();
  }

  /// "Commencer" — LES DEUX rôles doivent confirmer ; dès que les deux
  /// sont prêts, l'hôte (toujours "créateur" en présentiel connecté) prend
  /// la main en premier (voir SuitBattleEngine::readyUp côté PHP).
  void _applyHostReadyUp(String byRole) {
    if (!_state.dealt || _state.started) return;

    final outcome = SuitBattleEngine.readyUp(
      readyCreator: _state.readyCreator,
      readyPartner: _state.readyPartner,
      userId: byRole,
      creatorId: kSuitBattleHostRole,
    );

    _state = _state.copyWith(
      readyCreator: outcome.readyCreator,
      readyPartner: outcome.readyPartner,
      started: outcome.started,
      startedAt: outcome.started ? ServerClock.instance.now() : _state.startedAt,
      turnUserId: outcome.started ? kSuitBattleHostRole : _state.turnUserId,
      phase: outcome.started ? 'lead' : _state.phase,
    );
    _controller.add(_state);
    _sendState();
  }

  void _applyHostPlayLead(String byRole, String card) {
    if (_state.finished || _state.isPaused) return;
    if (_state.turnUserId != byRole || _state.phase != 'lead') return;

    try {
      final isHostRole = byRole == kSuitBattleHostRole;
      final outcome = SuitBattleEngine.playLead(
        spread: isHostRole ? _spreadHost : _spreadGuest,
        userId: byRole,
        card: card,
        otherUserId: isHostRole ? kSuitBattleGuestRole : kSuitBattleHostRole,
      );
      if (isHostRole) {
        _spreadHost = outcome.spread;
      } else {
        _spreadGuest = outcome.spread;
      }
      _state = _state.copyWith(
        spreadCreator: _spreadHost,
        spreadPartner: _spreadGuest,
        tableCard: outcome.tableCard,
        tableOwnerUserId: outcome.tableOwnerUserId,
        turnUserId: outcome.turnUserId,
        phase: 'response',
        winnerUserId: outcome.winnerUserId,
        finished: outcome.finished,
      );
      _controller.add(_state);
      _sendState();
    } catch (_) {
      // Coup invalide — ignoré, l'invité reste sur son état courant.
    }
  }

  void _applyHostRespondCard(String byRole, String card) {
    if (_state.finished || _state.isPaused) return;
    if (_state.turnUserId != byRole || _state.phase != 'response') return;
    final tableCard = _state.tableCard;
    final leaderId = _state.tableOwnerUserId;
    if (tableCard == null || leaderId == null) return;

    try {
      final isHostRole = byRole == kSuitBattleHostRole;
      final outcome = SuitBattleEngine.respondCard(
        spread: isHostRole ? _spreadHost : _spreadGuest,
        userId: byRole,
        card: card,
        tableCard: tableCard,
        leaderId: leaderId,
        leaderWonPile: leaderId == kSuitBattleHostRole ? _wonHost : _wonGuest,
        responderWonPile: byRole == kSuitBattleHostRole ? _wonHost : _wonGuest,
        roundsCount: _state.roundsCount,
      );
      if (isHostRole) {
        _spreadHost = outcome.spread;
      } else {
        _spreadGuest = outcome.spread;
      }
      if (outcome.finished) {
        // Fin de partie sur cette carte : fusion immédiate, pas de pause
        // "reveal" (voir doc de classe SuitBattleRespondOutcome).
        final mergedWonPile = outcome.mergedWonPile!;
        if (outcome.winnerId == kSuitBattleHostRole) {
          _wonHost = mergedWonPile;
        } else {
          _wonGuest = mergedWonPile;
        }
        _state = _state.copyWith(
          spreadCreator: _spreadHost,
          spreadPartner: _spreadGuest,
          wonCreator: _wonHost,
          wonPartner: _wonGuest,
          turnUserId: outcome.winnerId,
          phase: 'lead',
          roundsCount: outcome.roundsCount,
          winnerUserId: outcome.winnerUserId,
          finished: true,
          clearTable: true,
        );
      } else {
        // Voir demande utilisateur : "les deux cartes sorties se disposent
        // côte à côte... un bouton Balayer" — la carte du répondant reste
        // visible à côté de `tableCard` jusqu'au balayage explicite (voir
        // _applyHostSweepExchange).
        _state = _state.copyWith(
          spreadCreator: _spreadHost,
          spreadPartner: _spreadGuest,
          responseCard: outcome.card,
          pendingRoundWinnerId: outcome.winnerId,
          phase: 'reveal',
          roundsCount: outcome.roundsCount,
        );
      }
      _controller.add(_state);
      _sendState();
    } catch (_) {
      // Coup invalide — ignoré.
    }
  }

  /// "Balayer" — voir demande utilisateur. N'importe lequel des deux rôles
  /// peut le déclencher : l'issue de l'échange est déjà tranchée, balayer
  /// ne fait que la valider visuellement pour continuer.
  void _applyHostSweepExchange() {
    if (_state.finished || _state.isPaused || _state.phase != 'reveal') return;
    final tableCard = _state.tableCard;
    final responseCard = _state.responseCard;
    final winnerId = _state.pendingRoundWinnerId;
    if (tableCard == null || responseCard == null || winnerId == null) return;

    final mergedWonPile = SuitBattleEngine.sweepExchange(
      tableCard: tableCard,
      responseCard: responseCard,
      currentWinnerWonPile: winnerId == kSuitBattleHostRole ? _wonHost : _wonGuest,
    );
    if (winnerId == kSuitBattleHostRole) {
      _wonHost = mergedWonPile;
    } else {
      _wonGuest = mergedWonPile;
    }
    _state = _state.copyWith(
      wonCreator: _wonHost,
      wonPartner: _wonGuest,
      turnUserId: winnerId,
      phase: 'lead',
      clearTable: true,
    );
    _controller.add(_state);
    _sendState();
  }

  void _applyHostCaptureLead(String byRole) {
    if (_state.finished || _state.isPaused) return;
    if (_state.turnUserId != byRole || _state.phase != 'response') return;
    final tableCard = _state.tableCard;
    final leaderId = _state.tableOwnerUserId;
    if (tableCard == null || leaderId == null) return;

    final outcome = SuitBattleEngine.captureLead(
      tableCard: tableCard,
      leaderId: leaderId,
      responderWonPile: byRole == kSuitBattleHostRole ? _wonHost : _wonGuest,
      roundsCount: _state.roundsCount,
    );
    if (byRole == kSuitBattleHostRole) {
      _wonHost = outcome.wonPile;
    } else {
      _wonGuest = outcome.wonPile;
    }
    _state = _state.copyWith(
      wonCreator: _wonHost,
      wonPartner: _wonGuest,
      turnUserId: outcome.leaderId,
      phase: 'lead',
      roundsCount: outcome.roundsCount,
      clearTable: true,
    );
    _controller.add(_state);
    _sendState();
  }

  void _applyHostPause(String byRole) {
    if (_state.isPaused || _state.finished) return;
    _state = _state.copyWith(pausedByUserId: byRole, pausedAt: ServerClock.instance.now());
    _controller.add(_state);
    _sendState();
  }

  void _applyHostResume(String byRole) {
    if (!_state.isPaused || _state.pausedByUserId != byRole) return;
    final paused = _state.pausedAt;
    if (paused != null && _state.startedAt != null) {
      _state = _state.copyWith(startedAt: _state.startedAt!.add(ServerClock.instance.now().difference(paused)));
    }
    _state = _state.copyWith(clearPause: true);
    _controller.add(_state);
    _sendState();
  }

  @override
  Stream<SuitBattleBoardState> get stateStream => _controller.stream;

  @override
  SuitBattleBoardState get currentState => _state;

  @override
  Future<void> shuffleDeck() async {
    if (isHost) {
      _applyHostShuffle();
    } else {
      _send({'type': 'shuffle_request'});
    }
  }

  @override
  Future<void> dealAutomatic() async {
    if (isHost) {
      _applyHostDealAuto();
    } else {
      _send({'type': 'deal_auto_request'});
    }
  }

  @override
  Future<void> readyUp() async {
    if (isHost) {
      _applyHostReadyUp(kSuitBattleHostRole);
    } else {
      _send({'type': 'ready_request'});
    }
  }

  @override
  Future<void> playLead(String userId, String card) async {
    if (isHost) {
      _applyHostPlayLead(kSuitBattleHostRole, card);
    } else {
      _send({'type': 'play_lead', 'card': card});
    }
  }

  @override
  Future<void> respondCard(String userId, String card) async {
    if (isHost) {
      _applyHostRespondCard(kSuitBattleHostRole, card);
    } else {
      _send({'type': 'respond_card', 'card': card});
    }
  }

  @override
  Future<void> sweepExchange() async {
    if (isHost) {
      _applyHostSweepExchange();
    } else {
      _send({'type': 'sweep_request'});
    }
  }

  @override
  Future<void> captureLead(String userId) async {
    if (isHost) {
      _applyHostCaptureLead(kSuitBattleHostRole);
    } else {
      _send({'type': 'capture_lead'});
    }
  }

  @override
  Future<void> abandon() async {
    if (isHost) {
      _applyHostAbandon();
    } else {
      // Prévient l'hôte pour qu'il redistribue l'état "abandonné" à son
      // tour (voir demande utilisateur : "mon binôme ne reçoit rien") —
      // même principe que pause_request : seul l'hôte fait autorité et
      // diffuse, l'invité ne peut pas clore la partie unilatéralement pour
      // l'autre. Reflété localement tout de suite pour fermer SON écran
      // sans attendre l'aller-retour Bluetooth (voir _confirmAbandon).
      _send({'type': 'abandon_request'});
      _state = _state.copyWith(finished: true, abandoned: true);
      _controller.add(_state);
    }
  }

  void _applyHostAbandon() {
    if (_state.finished) return;
    _state = _state.copyWith(finished: true, abandoned: true);
    _controller.add(_state);
    _sendState();
  }

  @override
  Future<void> pause() async {
    if (isHost) {
      _applyHostPause(kSuitBattleHostRole);
    } else {
      _send({'type': 'pause_request'});
    }
  }

  @override
  Future<void> resume() async {
    if (!_state.pausedByMe) return;
    if (isHost) {
      _applyHostResume(kSuitBattleHostRole);
    } else {
      _send({'type': 'resume_request'});
    }
  }

  @override
  void dispose() {
    _controller.close();
  }
}
