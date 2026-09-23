import 'dart:async';

import 'war_card_engine.dart';
import 'war_card_transport.dart';

/// Mode "présentiel, un seul téléphone" (pass-and-play) — aucune
/// connexion, tout se joue en mémoire locale. Contrairement à Chasse aux
/// Chiffres (où l'app ne peut pas savoir qui a tapé), ici chaque joueur a
/// SON PROPRE bouton "Retourner" affiché à l'écran (voir
/// WarCardBoardScreen) — pas d'ambiguïté à lever, [flip] reçoit
/// directement l'identité de qui vient de taper.
class LocalWarCardTransport extends WarCardTransport {
  final String creatorUserId;
  final String partnerUserId;

  final _controller = StreamController<WarCardBoardState>.broadcast();
  late WarCardBoardState _state;
  List<String> _deck = [];
  List<String> _pileCreator = [];
  List<String> _pilePartner = [];
  List<String> _battlePot = [];

  LocalWarCardTransport({required this.creatorUserId, required this.partnerUserId, int deckSize = WarCardEngine.deckSize}) {
    _deck = WarCardEngine.shuffledDeck(deckSize: deckSize);
    _state = WarCardBoardState(
      deck: _deck,
      myUserId: creatorUserId,
      creatorId: creatorUserId,
      partnerId: partnerUserId,
    );
  }

  @override
  Stream<WarCardBoardState> get stateStream => _controller.stream;

  @override
  WarCardBoardState get currentState => _state;

  @override
  Future<void> shuffleDeck() async {
    if (_state.dealt) return;
    _deck = WarCardEngine.shuffleDeck(_deck);
    _state = _state.copyWith(deck: _deck);
    _controller.add(_state);
  }

  @override
  Future<void> dealAutomatic() async {
    if (_state.dealt) return;
    final result = WarCardEngine.dealAutomatic(_deck);
    _pileCreator = result.pileCreator;
    _pilePartner = result.pilePartner;
    _deck = [];
    _state = _state.copyWith(deck: _deck, pileCreator: _pileCreator, pilePartner: _pilePartner, dealt: true);
    _controller.add(_state);
  }

  @override
  Future<void> dealManualStep() async {
    if (_state.dealt) return;
    final result = WarCardEngine.dealManualStep(deck: _deck, pileCreator: _pileCreator, pilePartner: _pilePartner);
    _deck = result.deck;
    _pileCreator = result.pileCreator;
    _pilePartner = result.pilePartner;
    _state = _state.copyWith(deck: _deck, pileCreator: _pileCreator, pilePartner: _pilePartner, dealt: _deck.isEmpty);
    _controller.add(_state);
  }

  // Pass-and-play : les deux rôles sont sur le même appareil (voir doc de
  // classe) — UN seul appel de "Commencer" suffit pour marquer les DEUX
  // prêts d'un coup, contrairement aux modes à distance/présentiel connecté.
  @override
  Future<void> readyUp() async {
    if (!_state.dealt || _state.started) return;
    _state = _state.copyWith(readyCreator: true, readyPartner: true, started: true, startedAt: DateTime.now());
    _controller.add(_state);
  }

  @override
  Future<void> flip(String userId) async {
    if (_state.finished || _state.isPaused) return;

    final outcome = WarCardEngine.flip(
      pileCreator: _pileCreator,
      pilePartner: _pilePartner,
      pendingFlipCreator: _state.pendingFlipCreator,
      pendingFlipPartner: _state.pendingFlipPartner,
      battlePot: _battlePot,
      roundsCount: _state.roundsCount,
      userId: userId,
      creatorId: creatorUserId,
      partnerId: partnerUserId,
    );

    _pileCreator = outcome.pileCreator;
    _pilePartner = outcome.pilePartner;
    _battlePot = outcome.battlePot;

    // Pass-and-play garde le ramassage AUTOMATIQUE (voir demande
    // utilisateur : le bouton "ramasser" ne s'applique qu'à distance/
    // Bluetooth, les deux joueurs étant déjà réunis devant le même écran
    // ici — pas besoin de "s'informer") — ramassé tout de suite, sans
    // jamais exposer `pendingCollectorId` à l'écran.
    if (outcome.pendingCollectorId != null) {
      final result = WarCardEngine.collectPot(
        pileCreator: _pileCreator,
        pilePartner: _pilePartner,
        pot: _battlePot,
        collectorIsCreator: outcome.pendingCollectorId == creatorUserId,
      );
      _pileCreator = result.pileCreator;
      _pilePartner = result.pilePartner;
      _battlePot = [];
    }

    _state = _state.copyWith(
      pileCreator: _pileCreator,
      pilePartner: _pilePartner,
      pendingFlipCreator: outcome.pendingFlipCreator,
      pendingFlipPartner: outcome.pendingFlipPartner,
      lastRoundResult: outcome.resolved ? outcome.lastRoundResult : _state.lastRoundResult,
      roundsCount: outcome.roundsCount,
      winnerUserId: outcome.winnerUserId,
      isTie: outcome.isTie,
      finished: outcome.finished,
    );
    _controller.add(_state);
  }

  @override
  Future<void> shufflePile(String userId) async {
    if (_state.finished || _state.isPaused) return;
    final isCreator = userId == creatorUserId;
    final alreadyTapped = isCreator ? _state.pendingFlipCreator : _state.pendingFlipPartner;
    if (alreadyTapped) return;

    if (isCreator) {
      _pileCreator = WarCardEngine.shufflePile(_pileCreator);
      _state = _state.copyWith(pileCreator: _pileCreator);
    } else {
      _pilePartner = WarCardEngine.shufflePile(_pilePartner);
      _state = _state.copyWith(pilePartner: _pilePartner);
    }
    _controller.add(_state);
  }

  // Jamais appelée en pass-and-play — voir flip() ci-dessus, qui ramasse
  // toujours immédiatement (pendingCollectorId n'est jamais exposé ici).
  @override
  Future<void> collectPot() async {}

  @override
  Future<void> abandon() async {
    _state = _state.copyWith(finished: true);
    _controller.add(_state);
  }

  // myUserId reste fixe pour toute la partie (voir LocalNumberHuntTransport,
  // même correctif) — garantit que `pausedByMe` reste vrai sur cet
  // appareil partagé.
  @override
  Future<void> pause() async {
    if (_state.isPaused || _state.finished) return;
    _state = _state.copyWith(pausedByUserId: _state.myUserId, pausedAt: DateTime.now());
    _controller.add(_state);
  }

  @override
  Future<void> resume() async {
    if (!_state.isPaused) return;
    final paused = _state.pausedAt;
    if (paused != null && _state.startedAt != null) {
      _state = _state.copyWith(startedAt: _state.startedAt!.add(DateTime.now().difference(paused)));
    }
    _state = _state.copyWith(clearPause: true);
    _controller.add(_state);
  }

  @override
  void dispose() {
    _controller.close();
  }
}
