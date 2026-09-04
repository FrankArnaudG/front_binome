import 'dart:async';

import '../../../models/battleship_session.dart';
import 'battleship_engine.dart';
import 'battleship_transport.dart';

/// Mode "présentiel, un seul téléphone" (pass-and-play) — aucune
/// connexion, tout se joue en mémoire locale. CONTRAIREMENT aux autres
/// jeux pass-and-play (où l'état est intégralement partagé, la confiance
/// de couple suffit), ici les DEUX flottes doivent rester secrètes
/// l'une de l'autre MÊME EN LOCAL — voir [setActiveViewer], appelé par
/// l'écran "passe le téléphone" (BattleshipPassDeviceScreen) à chaque
/// changement de main : [currentState] recalcule alors la vue filtrée
/// pour la personne qui tient maintenant l'appareil, jamais un mélange
/// des deux.
class LocalBattleshipTransport extends BattleshipTransport {
  final String creatorUserId;
  final String partnerUserId;
  final _controller = StreamController<BattleshipBoardState>.broadcast();

  List<BattleshipShip> _fleetCreator = [];
  List<BattleshipShip> _fleetPartner = [];
  List<BattleshipShot> _shotsCreator = [];
  List<BattleshipShot> _shotsPartner = [];
  bool _creatorReady = false;
  bool _partnerReady = false;
  String? _currentTurnUserId;
  String? _winnerUserId;
  int _movesCount = 0;
  bool _finished = false;
  DateTime? _startedAt;
  String? _pausedByUserId;
  DateTime? _pausedAt;

  String _activeViewerId;

  LocalBattleshipTransport({required this.creatorUserId, required this.partnerUserId})
      : _activeViewerId = creatorUserId;

  /// Change QUI regarde l'écran maintenant — voir doc de classe. À
  /// appeler UNIQUEMENT depuis l'écran "passe le téléphone", jamais
  /// pendant que la personne précédente peut encore voir l'écran.
  void setActiveViewer(String userId) {
    _activeViewerId = userId;
    _controller.add(currentState);
  }

  bool get _viewerIsCreator => _activeViewerId == creatorUserId;

  @override
  Stream<BattleshipBoardState> get stateStream => _controller.stream;

  @override
  BattleshipBoardState get currentState {
    final myFleet = _viewerIsCreator ? _fleetCreator : _fleetPartner;
    final myShots = _viewerIsCreator ? _shotsCreator : _shotsPartner;
    final opponentFleet = _viewerIsCreator ? _fleetPartner : _fleetCreator;
    final myReady = _viewerIsCreator ? _creatorReady : _partnerReady;
    final opponentReady = _viewerIsCreator ? _partnerReady : _creatorReady;

    return BattleshipBoardState(
      myFleet: myFleet,
      myShots: myShots,
      opponentSunkShips: BattleshipEngine.sunkShipsOf(opponentFleet),
      myReady: myReady,
      opponentReady: opponentReady,
      isBattlePhase: _creatorReady && _partnerReady,
      currentTurnUserId: _currentTurnUserId,
      winnerUserId: _winnerUserId,
      movesCount: _movesCount,
      finished: _finished,
      startedAt: _startedAt,
      myUserId: _activeViewerId,
      opponentUserId: _viewerIsCreator ? partnerUserId : creatorUserId,
      pausedByUserId: _pausedByUserId,
      pausedAt: _pausedAt,
    );
  }

  @override
  Future<void> submitFleet(List<BattleshipShip> ships) async {
    BattleshipEngine.validateFleet(ships);

    if (_viewerIsCreator) {
      _fleetCreator = ships;
      _creatorReady = true;
    } else {
      _fleetPartner = ships;
      _partnerReady = true;
    }

    if (_creatorReady && _partnerReady) {
      _currentTurnUserId = creatorUserId;
      _startedAt = DateTime.now();
    }
    _controller.add(currentState);
  }

  @override
  Future<void> fire(int cell) async {
    if (_finished || _pausedByUserId != null) return;
    if (_currentTurnUserId != _activeViewerId) return;

    final defenderFleet = _viewerIsCreator ? _fleetPartner : _fleetCreator;
    final outcome = BattleshipEngine.fire(defenderFleet: defenderFleet, cell: cell);

    if (_viewerIsCreator) {
      _fleetPartner = outcome.defenderFleet;
      _shotsCreator = [..._shotsCreator, BattleshipShot(cell: cell, hit: outcome.hit)];
    } else {
      _fleetCreator = outcome.defenderFleet;
      _shotsPartner = [..._shotsPartner, BattleshipShot(cell: cell, hit: outcome.hit)];
    }
    _movesCount++;

    if (outcome.finished) {
      _winnerUserId = _activeViewerId;
      _finished = true;
    } else {
      _currentTurnUserId = _viewerIsCreator ? partnerUserId : creatorUserId;
    }
    _controller.add(currentState);
  }

  @override
  Future<void> abandon() async {
    _finished = true;
    _controller.add(currentState);
  }

  @override
  Future<void> pause() async {
    if (_pausedByUserId != null || _finished) return;
    _pausedByUserId = _activeViewerId;
    _pausedAt = DateTime.now();
    _controller.add(currentState);
  }

  @override
  Future<void> resume() async {
    if (_pausedByUserId != _activeViewerId) return;
    final paused = _pausedAt;
    if (paused != null && _startedAt != null) {
      _startedAt = _startedAt!.add(DateTime.now().difference(paused));
    }
    _pausedByUserId = null;
    _pausedAt = null;
    _controller.add(currentState);
  }

  @override
  void dispose() {
    _controller.close();
  }
}
