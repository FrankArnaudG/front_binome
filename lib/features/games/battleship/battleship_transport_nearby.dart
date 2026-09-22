import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nearby_connections/nearby_connections.dart';

import '../../../models/battleship_session.dart';
import 'battleship_engine.dart';
import 'battleship_transport.dart';
import '../../../core/server_clock.dart';

const kBattleshipHostRole = 'host';
const kBattleshipGuestRole = 'guest';

/// Mode "présentiel connecté" — l'HÔTE est autoritaire ET détient les
/// DEUX flottes complètes ; l'invité ne reçoit QUE sa propre vue filtrée
/// (voir _sendStateTo, jamais un message générique diffusé tel quel —
/// contrairement aux autres jeux Nearby, il n'y a qu'UN destinataire de
/// toute façon, donc "adapter le message au destinataire" est trivial
/// ici, pas besoin de canaux séparés).
class NearbyBattleshipTransport extends BattleshipTransport {
  final Nearby nearby;
  final String endpointId;
  final bool isHost;
  int _gridSize = BattleshipEngine.defaultGrid;
  final _controller = StreamController<BattleshipBoardState>.broadcast();

  // Uniquement renseigné côté hôte — l'invité ne connaît jamais l'état
  // complet, seulement ce que _stateFor(guest) lui a envoyé.
  List<BattleshipShip> _fleetHost = [];
  List<BattleshipShip> _fleetGuest = [];
  List<BattleshipShot> _shotsHost = [];
  List<BattleshipShot> _shotsGuest = [];
  bool _hostReady = false;
  bool _guestReady = false;
  String? _currentTurnRole;
  String? _winnerRole;
  int _movesCount = 0;
  bool _finished = false;
  DateTime? _startedAt;
  String? _pausedByRole;
  DateTime? _pausedAt;

  // Côté invité uniquement : dernière vue reçue de l'hôte.
  BattleshipBoardState? _guestState;

  NearbyBattleshipTransport.host({required this.nearby, required this.endpointId, required int gridSize})
      : isHost = true,
        _gridSize = gridSize {
    // Envoyé tout de suite (avant toute pose de flotte) — l'invité en a
    // besoin pour construire SON écran de placement, qui dépend de la
    // taille de grille choisie ici par l'hôte (voir doc du constructeur
    // .guest, même principe que NearbyDotSquaresTransport.host/_sendInit).
    _sendStateToGuest();
  }

  /// Aucun [gridSize] à fournir ici — appris du premier message `state`
  /// envoyé par l'hôte (voir _stateFor), même principe que
  /// NearbyDotSquaresTransport.guest pour `cols`.
  NearbyBattleshipTransport.guest({required this.nearby, required this.endpointId}) : isHost = false {
    _guestState = BattleshipBoardState(myUserId: kBattleshipGuestRole, opponentUserId: kBattleshipHostRole);
  }

  void _send(Map<String, dynamic> message) {
    nearby.sendBytesPayload(endpointId, Uint8List.fromList(utf8.encode(jsonEncode(message))));
  }

  BattleshipBoardState _stateFor(String role) {
    final isHostRole = role == kBattleshipHostRole;
    final myFleet = isHostRole ? _fleetHost : _fleetGuest;
    final myShots = isHostRole ? _shotsHost : _shotsGuest;
    final opponentFleet = isHostRole ? _fleetGuest : _fleetHost;

    return BattleshipBoardState(
      gridSize: _gridSize,
      myFleet: myFleet,
      myShots: myShots,
      opponentSunkShips: BattleshipEngine.sunkShipsOf(opponentFleet),
      myReady: isHostRole ? _hostReady : _guestReady,
      opponentReady: isHostRole ? _guestReady : _hostReady,
      isBattlePhase: _hostReady && _guestReady,
      currentTurnUserId: _currentTurnRole,
      winnerUserId: _winnerRole,
      movesCount: _movesCount,
      finished: _finished,
      startedAt: _startedAt,
      myUserId: role,
      opponentUserId: isHostRole ? kBattleshipGuestRole : kBattleshipHostRole,
      pausedByUserId: _pausedByRole,
      pausedAt: _pausedAt,
    );
  }

  void _sendStateToGuest() {
    final state = _stateFor(kBattleshipGuestRole);
    _send({
      'type': 'state',
      'gridSize': state.gridSize,
      'myFleet': state.myFleet.map((s) => {'cells': s.cells, 'hits': s.hits}).toList(),
      'myShots': state.myShots.map((s) => {'cell': s.cell, 'hit': s.hit}).toList(),
      'opponentSunkShips': state.opponentSunkShips,
      'myReady': state.myReady,
      'opponentReady': state.opponentReady,
      'isBattlePhase': state.isBattlePhase,
      'currentTurnUserId': state.currentTurnUserId,
      'winnerUserId': state.winnerUserId,
      'movesCount': state.movesCount,
      'finished': state.finished,
      'startedAt': state.startedAt?.toIso8601String(),
      'pausedByUserId': state.pausedByUserId,
      'pausedAt': state.pausedAt?.toIso8601String(),
    });
  }

  void onPayloadReceived(String fromEndpointId, Payload payload) {
    if (payload.type != PayloadType.BYTES || payload.bytes == null) return;
    final message = jsonDecode(utf8.decode(payload.bytes!)) as Map<String, dynamic>;

    switch (message['type']) {
      case 'state':
        // Reçu côté invité uniquement — l'hôte fait autorité, cette vue
        // est déjà filtrée pour NOUS (voir _sendStateToGuest).
        final pausedByUserId = message['pausedByUserId'] as String?;
        // Appris du premier message `state` reçu — voir doc du constructeur
        // .guest, l'invité n'a aucune autre façon de connaître ce choix
        // fait par l'hôte (pas de serveur en Nearby).
        _gridSize = message['gridSize'] as int? ?? BattleshipEngine.defaultGrid;
        _guestState = BattleshipBoardState(
          gridSize: _gridSize,
          myFleet: (message['myFleet'] as List)
              .map((e) => BattleshipShip.fromJson(e as Map<String, dynamic>))
              .toList(),
          myShots: (message['myShots'] as List).map((e) => BattleshipShot.fromJson(e as Map<String, dynamic>)).toList(),
          opponentSunkShips:
              (message['opponentSunkShips'] as List).map((s) => (s as List).map((e) => e as int).toList()).toList(),
          myReady: message['myReady'] as bool,
          opponentReady: message['opponentReady'] as bool,
          isBattlePhase: message['isBattlePhase'] as bool,
          currentTurnUserId: message['currentTurnUserId'] as String?,
          winnerUserId: message['winnerUserId'] as String?,
          movesCount: message['movesCount'] as int,
          finished: message['finished'] as bool,
          startedAt: message['startedAt'] != null ? DateTime.parse(message['startedAt'] as String) : null,
          myUserId: kBattleshipGuestRole,
          opponentUserId: kBattleshipHostRole,
          pausedByUserId: pausedByUserId,
          pausedAt: message['pausedAt'] != null ? DateTime.parse(message['pausedAt'] as String) : null,
        );
        _controller.add(_guestState!);
      case 'submit_fleet':
        if (isHost) {
          _applyFleet(
            kBattleshipGuestRole,
            (message['ships'] as List).map((e) => BattleshipShip.fromJson(e as Map<String, dynamic>)).toList(),
          );
        }
      case 'fire':
        if (isHost) _applyFire(kBattleshipGuestRole, message['cell'] as int);
      case 'pause_request':
        if (isHost) _applyPause(kBattleshipGuestRole);
      case 'resume_request':
        if (isHost) _applyResume(kBattleshipGuestRole);
    }
  }

  void _applyFleet(String role, List<BattleshipShip> ships) {
    try {
      BattleshipEngine.validateFleet(ships, _gridSize);
    } on ArgumentError {
      return;
    }

    if (role == kBattleshipHostRole) {
      _fleetHost = ships;
      _hostReady = true;
    } else {
      _fleetGuest = ships;
      _guestReady = true;
    }

    if (_hostReady && _guestReady) {
      _currentTurnRole = kBattleshipHostRole;
      _startedAt = ServerClock.instance.now();
    }
    _controller.add(_stateFor(kBattleshipHostRole));
    _sendStateToGuest();
  }

  void _applyFire(String role, int cell) {
    if (_finished || _pausedByRole != null || _currentTurnRole != role) return;

    final defenderFleet = role == kBattleshipHostRole ? _fleetGuest : _fleetHost;
    final BattleshipFireOutcome outcome;
    try {
      outcome = BattleshipEngine.fire(defenderFleet: defenderFleet, cell: cell, gridSize: _gridSize);
    } on ArgumentError {
      return;
    }

    if (role == kBattleshipHostRole) {
      _fleetGuest = outcome.defenderFleet;
      _shotsHost = [..._shotsHost, BattleshipShot(cell: cell, hit: outcome.hit)];
    } else {
      _fleetHost = outcome.defenderFleet;
      _shotsGuest = [..._shotsGuest, BattleshipShot(cell: cell, hit: outcome.hit)];
    }
    _movesCount++;

    if (outcome.finished) {
      _winnerRole = role;
      _finished = true;
    } else {
      _currentTurnRole = role == kBattleshipHostRole ? kBattleshipGuestRole : kBattleshipHostRole;
    }
    _controller.add(_stateFor(kBattleshipHostRole));
    _sendStateToGuest();
  }

  void _applyPause(String role) {
    if (_pausedByRole != null || _finished) return;
    _pausedByRole = role;
    _pausedAt = ServerClock.instance.now();
    _controller.add(_stateFor(kBattleshipHostRole));
    _sendStateToGuest();
  }

  void _applyResume(String role) {
    if (_pausedByRole != role) return;
    final paused = _pausedAt;
    if (paused != null && _startedAt != null) {
      _startedAt = _startedAt!.add(ServerClock.instance.now().difference(paused));
    }
    _pausedByRole = null;
    _pausedAt = null;
    _controller.add(_stateFor(kBattleshipHostRole));
    _sendStateToGuest();
  }

  @override
  Stream<BattleshipBoardState> get stateStream => _controller.stream;

  @override
  BattleshipBoardState get currentState => isHost ? _stateFor(kBattleshipHostRole) : _guestState!;

  @override
  Future<void> submitFleet(List<BattleshipShip> ships) async {
    if (isHost) {
      _applyFleet(kBattleshipHostRole, ships);
    } else {
      BattleshipEngine.validateFleet(ships, _gridSize); // feedback immédiat côté invité avant l'aller-retour réseau
      _send({'type': 'submit_fleet', 'ships': ships.map((s) => {'cells': s.cells}).toList()});
    }
  }

  @override
  Future<void> fire(int cell) async {
    if (isHost) {
      _applyFire(kBattleshipHostRole, cell);
    } else {
      _send({'type': 'fire', 'cell': cell});
    }
  }

  @override
  Future<void> abandon() async {
    _finished = true;
    if (isHost) {
      _controller.add(_stateFor(kBattleshipHostRole));
      _sendStateToGuest();
    } else {
      _guestState = _guestState?.copyWith(finished: true);
      _controller.add(_guestState!);
    }
  }

  @override
  Future<void> pause() async {
    if (isHost) {
      _applyPause(kBattleshipHostRole);
    } else {
      _send({'type': 'pause_request'});
    }
  }

  @override
  Future<void> resume() async {
    if (!currentState.pausedByMe) return;
    if (isHost) {
      _applyResume(kBattleshipHostRole);
    } else {
      _send({'type': 'resume_request'});
    }
  }

  @override
  void dispose() {
    _controller.close();
  }
}
