import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

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

  void _applyServerState(WarCardSession session, [String source = 'unknown']) {
    if (!_acceptVersion(session)) return;
    // Diagnostic (voir demande utilisateur : "ma carte se retourne sans que
    // je tape ma pile", mode à distance) — trace tout passage de MON
    // pendingFlip de false à true, avec la source (broadcast temps réel vs
    // resync périodique vs réponse directe d'un appel), pour distinguer un
    // vrai tap perdu/dupliqué d'un état serveur mal attribué.
    final myFlipBefore = myUserId == creatorId ? _state.pendingFlipCreator : _state.pendingFlipPartner;
    final myFlipAfter = myUserId == creatorId ? session.pendingFlipCreator : session.pendingFlipPartner;
    if (!myFlipBefore && myFlipAfter) {
      debugPrint(
        'RemoteWarCardTransport: mon pendingFlip passe à true via "$source" '
        '(session ${session.id}, version ${session.version}, rounds ${session.roundsCount})',
      );
    }
    // Diagnostic (voir demande utilisateur : "je peux sortir une carte et
    // elle change automatiquement") — la carte révélée à l'écran est lue EN
    // LIVE depuis pileCreator/pilePartner (voir _WarCardDuelArea), donc si
    // le dessus de MA pile change alors qu'AUCUNE manche n'a été résolue
    // entre-temps (même roundsCount), la carte affichée change sans raison
    // valable — signe d'un état incohérent appliqué par erreur.
    final myPileBefore = myUserId == creatorId ? _state.pileCreator : _state.pilePartner;
    final myPileAfter = myUserId == creatorId ? (session.pileCreator ?? const []) : (session.pilePartner ?? const []);
    final myTopCardBefore = myPileBefore.isNotEmpty ? myPileBefore.first : null;
    final myTopCardAfter = myPileAfter.isNotEmpty ? myPileAfter.first : null;
    if (myTopCardBefore != null &&
        myTopCardAfter != null &&
        myTopCardBefore != myTopCardAfter &&
        session.roundsCount == _state.roundsCount) {
      debugPrint(
        'RemoteWarCardTransport: ma carte du dessus change SANS résolution de manche via "$source" '
        '($myTopCardBefore → $myTopCardAfter, session ${session.id}, version ${session.version}, rounds ${session.roundsCount})',
      );
    }
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
      _applyServerState(session, 'resync_poll');
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
        pendingCollectorId: session.pendingCollectorId,
        pendingPot: session.battlePot,
      );

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.event != 'WarCardUpdated') return;
    final data = event.data;
    if (data == null) return;

    final session = WarCardSession.fromJson(data['session'] as Map<String, dynamic>);
    if (session.id != sessionId) return;
    if (!_acceptVersion(session)) return;

    _applyServerState(session, 'realtime_broadcast');
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
    // arrive presque aussitôt et écrase cette prédiction. Le vrai pot
    // courant (`_state.pendingPot`) est passé tel quel : lors d'une guerre
    // qui SE POURSUIT, il n'est PAS vide entre deux appels (seule une
    // résolution DÉCISIVE le vide, voir WarCardEngine._resolveRound) —
    // passer `const []` ici faisait perdre les cartes déjà accumulées
    // (voir retour utilisateur : "les deux cartes disparaissent avant de
    // réapparaître avec le texte guerre").
    try {
      final outcome = WarCardEngine.flip(
        pileCreator: _state.pileCreator,
        pilePartner: _state.pilePartner,
        pendingFlipCreator: _state.pendingFlipCreator,
        pendingFlipPartner: _state.pendingFlipPartner,
        battlePot: _state.pendingPot,
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
        // Comme LocalWarCardTransport/NearbyWarCardTransport : tant que
        // l'autre n'a pas encore tapé, `outcome.lastRoundResult` est vide
        // (manche non résolue) — l'écraser aurait fait disparaître les
        // cartes de guerre affichées le temps que la vraie réponse serveur
        // arrive (voir capture utilisateur : cartes qui disparaissent puis
        // réapparaissent après un tap pendant une guerre).
        lastRoundResult: outcome.resolved ? outcome.lastRoundResult : _state.lastRoundResult,
        roundsCount: outcome.roundsCount,
        winnerUserId: outcome.winnerUserId,
        isTie: outcome.isTie,
        finished: outcome.finished,
        // Comme NearbyWarCardTransport (`pendingPot: _battlePot`) : sans
        // ça, le pot affiché pendant une guerre restait figé sur sa valeur
        // d'AVANT ce tap (souvent vide) le temps que la vraie réponse
        // serveur arrive, ce qui faisait disparaître les cartes de guerre
        // juste après avoir tapé (voir retour utilisateur, même symptôme).
        pendingPot: outcome.resolved ? outcome.battlePot : _state.pendingPot,
        // Comme NearbyWarCardTransport : sans ça, `pendingCollectorId`
        // restait à sa valeur d'avant ce tap (donc `null`) le temps que la
        // vraie réponse serveur arrive, ce qui faisait passer
        // `duelIsWarStep` à vrai par erreur pour une manche pourtant
        // DÉCISIVE (pas une égalité) — d'où le terme "Guerre" qui
        // apparaissait puis disparaissait à chaque manche jouée (voir
        // retour utilisateur).
        pendingCollectorId: outcome.resolved ? outcome.pendingCollectorId : _state.pendingCollectorId,
        clearPendingCollector: outcome.resolved && outcome.pendingCollectorId == null,
      );
      _controller.add(_state);
    } catch (_) {
      // Coup localement invalide — le serveur tranchera.
    }

    try {
      final result = await GameService.instance.flipWarCard(sessionId);
      _applyServerState(result.session, 'my_own_flip_response');
    } catch (_) {
      try {
        final session = await GameService.instance.fetchWarCardState(sessionId);
        _applyServerState(session, 'my_own_flip_fallback_fetch');
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
  Future<void> collectPot() async {
    final session = await GameService.instance.collectPotWarCard(sessionId);
    _applyServerState(session, 'my_own_collect_response');
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
