import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nearby_connections/nearby_connections.dart';

import 'war_card_engine.dart';
import 'war_card_transport.dart';
import '../../../core/server_clock.dart';

/// Identifiants internes des deux rôles — voir kNumberHuntHostRole/
/// kNumberHuntGuestRole, même principe (Nearby Connections n'a pas de
/// notion de compte).
const kWarCardHostRole = 'host';
const kWarCardGuestRole = 'guest';

/// Mode "présentiel connecté" — l'HÔTE est autoritaire : lui seul applique
/// WarCardEngine, l'invité ne fait que proposer un tap "Retourner" et
/// recevoir l'état à jour. Copie structurelle conforme de
/// NearbyNumberHuntTransport, adaptée au pattern "les deux doivent taper"
/// (voir WarCardEngine.flip).
class NearbyWarCardTransport extends WarCardTransport {
  final Nearby nearby;
  final String endpointId;
  final bool isHost;
  final _controller = StreamController<WarCardBoardState>.broadcast();
  late WarCardBoardState _state;
  List<String> _deck = [];
  List<String> _pileHost = [];
  List<String> _pileGuest = [];
  List<String> _battlePot = [];

  /// Côté hôte : prépare le paquet (encore empilé, pas distribué) et
  /// l'envoie tout de suite à l'invité.
  NearbyWarCardTransport.host({
    required this.nearby,
    required this.endpointId,
    int deckSize = WarCardEngine.deckSize,
  }) : isHost = true {
    _deck = WarCardEngine.shuffledDeck(deckSize: deckSize);
    _state = WarCardBoardState(
      deck: _deck,
      myUserId: kWarCardHostRole,
      creatorId: kWarCardHostRole,
      partnerId: kWarCardGuestRole,
    );
    _sendInit();
  }

  /// Côté invité : état par défaut tant que le message `init` de l'hôte
  /// n'est pas arrivé.
  NearbyWarCardTransport.guest({
    required this.nearby,
    required this.endpointId,
  }) : isHost = false {
    _state = const WarCardBoardState(myUserId: kWarCardGuestRole, creatorId: kWarCardHostRole, partnerId: kWarCardGuestRole);
  }

  void _send(Map<String, dynamic> message) {
    nearby.sendBytesPayload(endpointId, Uint8List.fromList(utf8.encode(jsonEncode(message))));
  }

  void _sendInit() {
    _send({
      'type': 'init',
      // Listes complètes (pas juste le nombre) — voir demande
      // utilisateur : chacun doit pouvoir taper sur SA pile pour la voir
      // en éventail, y compris côté invité.
      'deck': _deck,
      'dealt': _state.dealt,
      'readyCreator': _state.readyCreator,
      'readyPartner': _state.readyPartner,
      'started': _state.started,
      'pileHost': _pileHost,
      'pileGuest': _pileGuest,
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
      'pileHost': _pileHost,
      'pileGuest': _pileGuest,
      'pendingFlipHost': _state.pendingFlipCreator,
      'pendingFlipGuest': _state.pendingFlipPartner,
      'lastRoundResult': _state.lastRoundResult,
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
        _state = WarCardBoardState(
          deck: (message['deck'] as List).map((e) => e as String).toList(),
          dealt: message['dealt'] as bool? ?? false,
          readyCreator: message['readyCreator'] as bool? ?? false,
          readyPartner: message['readyPartner'] as bool? ?? false,
          started: message['started'] as bool? ?? false,
          pileCreator: (message['pileHost'] as List).map((e) => e as String).toList(),
          pilePartner: (message['pileGuest'] as List).map((e) => e as String).toList(),
          startedAt: message['startedAt'] != null ? DateTime.parse(message['startedAt'] as String) : null,
          myUserId: kWarCardGuestRole,
          creatorId: kWarCardHostRole,
          partnerId: kWarCardGuestRole,
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
          pileCreator: (message['pileHost'] as List).map((e) => e as String).toList(),
          pilePartner: (message['pileGuest'] as List).map((e) => e as String).toList(),
          pendingFlipCreator: message['pendingFlipHost'] as bool,
          pendingFlipPartner: message['pendingFlipGuest'] as bool,
          lastRoundResult: (message['lastRoundResult'] as List)
              .whereType<Map>()
              .map((r) => r.map((k, v) => MapEntry(k as String, v as String)))
              .toList(),
          roundsCount: message['roundsCount'] as int,
          winnerUserId: message['winnerUserId'] as String?,
          isTie: message['isTie'] as bool,
          finished: message['finished'] as bool,
          abandoned: message['abandoned'] as bool? ?? false,
          startedAt: message['startedAt'] != null ? DateTime.parse(message['startedAt'] as String) : _state.startedAt,
          pausedByUserId: pausedByUserId,
          pausedAt: message['pausedAt'] != null ? DateTime.parse(message['pausedAt'] as String) : null,
          clearPause: pausedByUserId == null,
        );
        _controller.add(_state);
      case 'shuffle_request':
        if (isHost) _applyHostShuffle();
      case 'deal_auto_request':
        if (isHost) _applyHostDealAuto();
      case 'deal_manual_request':
        if (isHost) _applyHostDealManualStep();
      case 'ready_request':
        if (isHost) _applyHostReadyUp(kWarCardGuestRole);
      case 'shuffle_pile_request':
        if (isHost) _applyHostShufflePile(kWarCardGuestRole);
      case 'flip':
        // Reçu côté hôte uniquement — l'invité propose un tap, l'hôte
        // applique WarCardEngine et redistribue le nouvel état.
        if (isHost) _applyHostFlip(kWarCardGuestRole);
      case 'pause_request':
        if (isHost) _applyHostPause(kWarCardGuestRole);
      case 'resume_request':
        if (isHost) _applyHostResume(kWarCardGuestRole);
      case 'abandon_request':
        if (isHost) _applyHostAbandon();
    }
  }

  void _applyHostShuffle() {
    if (_state.dealt) return;
    _deck = WarCardEngine.shuffleDeck(_deck);
    _state = _state.copyWith(deck: _deck);
    _controller.add(_state);
    _sendState();
  }

  void _applyHostDealAuto() {
    if (_state.dealt) return;
    final result = WarCardEngine.dealAutomatic(_deck);
    _pileHost = result.pileCreator;
    _pileGuest = result.pilePartner;
    _deck = [];
    _state = _state.copyWith(deck: _deck, pileCreator: _pileHost, pilePartner: _pileGuest, dealt: true);
    _controller.add(_state);
    _sendState();
  }

  void _applyHostDealManualStep() {
    if (_state.dealt) return;
    final result = WarCardEngine.dealManualStep(deck: _deck, pileCreator: _pileHost, pilePartner: _pileGuest);
    _deck = result.deck;
    _pileHost = result.pileCreator;
    _pileGuest = result.pilePartner;
    _state = _state.copyWith(deck: _deck, pileCreator: _pileHost, pilePartner: _pileGuest, dealt: _deck.isEmpty);
    _controller.add(_state);
    _sendState();
  }

  /// "Commencer" (voir demande utilisateur) — LES DEUX rôles doivent
  /// confirmer, même principe que _applyHostFlip.
  void _applyHostReadyUp(String byRole) {
    if (!_state.dealt || _state.started) return;

    final outcome = WarCardEngine.readyUp(
      readyCreator: _state.readyCreator,
      readyPartner: _state.readyPartner,
      userId: byRole,
      creatorId: kWarCardHostRole,
    );

    _state = _state.copyWith(
      readyCreator: outcome.readyCreator,
      readyPartner: outcome.readyPartner,
      started: outcome.started,
      startedAt: outcome.started ? ServerClock.instance.now() : _state.startedAt,
    );
    _controller.add(_state);
    _sendState();
  }

  /// "Battre" SA PROPRE pile en cours de partie (voir demande
  /// utilisateur) — refusé si [byRole] a déjà joué sa carte pour la
  /// manche en cours.
  void _applyHostShufflePile(String byRole) {
    if (_state.finished || _state.isPaused) return;
    final isHostRole = byRole == kWarCardHostRole;
    final alreadyTapped = isHostRole ? _state.pendingFlipCreator : _state.pendingFlipPartner;
    if (alreadyTapped) return;

    if (isHostRole) {
      _pileHost = WarCardEngine.shufflePile(_pileHost);
      _state = _state.copyWith(pileCreator: _pileHost);
    } else {
      _pileGuest = WarCardEngine.shufflePile(_pileGuest);
      _state = _state.copyWith(pilePartner: _pileGuest);
    }
    _controller.add(_state);
    _sendState();
  }

  void _applyHostFlip(String byRole) {
    if (_state.finished || _state.isPaused) return;

    final outcome = WarCardEngine.flip(
      pileCreator: _pileHost,
      pilePartner: _pileGuest,
      pendingFlipCreator: _state.pendingFlipCreator,
      pendingFlipPartner: _state.pendingFlipPartner,
      battlePot: _battlePot,
      roundsCount: _state.roundsCount,
      userId: byRole,
      creatorId: kWarCardHostRole,
      partnerId: kWarCardGuestRole,
    );

    _pileHost = outcome.pileCreator;
    _pileGuest = outcome.pilePartner;
    _battlePot = outcome.battlePot;

    _state = _state.copyWith(
      pileCreator: _pileHost,
      pilePartner: _pileGuest,
      pendingFlipCreator: outcome.pendingFlipCreator,
      pendingFlipPartner: outcome.pendingFlipPartner,
      lastRoundResult: outcome.resolved ? outcome.lastRoundResult : _state.lastRoundResult,
      roundsCount: outcome.roundsCount,
      winnerUserId: outcome.winnerUserId,
      isTie: outcome.isTie,
      finished: outcome.finished,
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
  Stream<WarCardBoardState> get stateStream => _controller.stream;

  @override
  WarCardBoardState get currentState => _state;

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
  Future<void> dealManualStep() async {
    if (isHost) {
      _applyHostDealManualStep();
    } else {
      _send({'type': 'deal_manual_request'});
    }
  }

  @override
  Future<void> readyUp() async {
    if (isHost) {
      _applyHostReadyUp(kWarCardHostRole);
    } else {
      _send({'type': 'ready_request'});
    }
  }

  @override
  Future<void> shufflePile(String userId) async {
    if (isHost) {
      _applyHostShufflePile(kWarCardHostRole);
    } else {
      _send({'type': 'shuffle_pile_request'});
    }
  }

  @override
  Future<void> flip(String userId) async {
    if (isHost) {
      _applyHostFlip(kWarCardHostRole);
    } else {
      _send({'type': 'flip'});
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
      _applyHostPause(kWarCardHostRole);
    } else {
      _send({'type': 'pause_request'});
    }
  }

  @override
  Future<void> resume() async {
    if (!_state.pausedByMe) return;
    if (isHost) {
      _applyHostResume(kWarCardHostRole);
    } else {
      _send({'type': 'resume_request'});
    }
  }

  @override
  void dispose() {
    _controller.close();
  }
}
