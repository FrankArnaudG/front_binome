import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:google_fonts/google_fonts.dart';
import 'package:showcaseview/showcaseview.dart';

import '../../../core/app_router.dart' show AppRouter;
import '../../../core/server_clock.dart';
import '../../../l10n/locale_scope.dart';
import '../../../models/app_user.dart';
import '../../../models/game.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../../../theme/themed_background.dart';
import '../game_guide_storage.dart';
import '../game_service.dart';
import '../nearby/nearby_comms.dart';
import '../widgets/always_on_top_layer.dart';
import '../widgets/coin_billing_ring.dart';
import '../widgets/game_comment_overlay.dart';
import '../widgets/game_guide_voice_demo.dart';
import '../widgets/game_resume_action.dart';
import '../widgets/game_wallet_depleted_notice.dart';
import '../widgets/game_wallet_guard.dart';
import '../widgets/nearby_voice_overlay.dart';
import '../widgets/playing_card_face.dart';
import '../widgets/voice_call_overlay.dart';
import '../widgets/war_card_match_scoreboard.dart';
import '../../shop/wallet_balance_notifier.dart';
import 'war_card_engine.dart';
import 'war_card_transport.dart';
import 'war_card_transport_local.dart';
import 'war_card_transport_remote.dart';

/// Étapes du guide pas-à-pas du plateau (voir doc de _BoardGuideStep dans
/// memory_game_board_screen.dart pour le principe général : simulation
/// 100% locale, mise en pause automatique, rejouable via "?"). Plus
/// simple qu'au Jeu de Mémoire : la Bataille n'a pas de "paire" à
/// démontrer, juste un bouton à taper — pas d'étape réactive nécessaire.
enum _WarCardGuideStep { status, flip, flipResult, coins, pause, chat, micJoin, micReady, cameraReady }

const _kRedColor = Color(0xFFE5484D);
const _kBlueColor = Color(0xFF2F6FED);

/// Plateau de "Bataille" — UNIQUE écran de jeu partagé par les 3 modes
/// (voir WarCardTransport), copie structurelle conforme des autres jeux
/// (pause/reprise, chrono), SAUF le pattern de tap : en pass-and-play
/// (voir [LocalWarCardTransport]) DEUX boutons "Retourner" distincts sont
/// affichés (un par joueur) ; en distant/présentiel connecté, un seul
/// bouton pour "moi".
class WarCardBoardScreen extends StatefulWidget {
  final Game game;
  final AppUser user;
  final WarCardTransport transport;
  final Map<String, String> playerNames;
  final Map<String, String?> playerAvatars;
  final Future<void> Function(BuildContext context)? onRematch;
  // Celui qui a lancé la partie (voir demande utilisateur) : seul lui voit "Rejouer" et le
  // décompte de Tokens (c'est son temps qui est facturé). L'autre joueur ne voit que "Quitter".
  final bool isLauncher;
  // "Quitter" depuis la feuille de score : par défaut referme le jeu ; l'invité·e d'une partie à
  // distance y ouvre le choix de la difficulté (voir game_invite_navigation.dart).
  final Future<void> Function(BuildContext context)? onQuit;
  final NearbyComms? nearbyComms;
  final String? nearbyMyName;
  final String? nearbyPartnerName;

  const WarCardBoardScreen({
    super.key,
    required this.game,
    required this.user,
    required this.transport,
    required this.playerNames,
    required this.playerAvatars,
    this.onRematch,
    this.isLauncher = true,
    this.onQuit,
    this.nearbyComms,
    this.nearbyMyName,
    this.nearbyPartnerName,
  });

  @override
  State<WarCardBoardScreen> createState() => _WarCardBoardScreenState();
}

class _WarCardBoardScreenState extends State<WarCardBoardScreen> {
  bool _resuming = false;
  late StreamSubscription<WarCardBoardState> _subscription;
  late WarCardBoardState _state;
  Timer? _clockTimer;
  bool _scoreboardShown = false;
  // Réglage admin (minutes_per_coin/grace_period_seconds) pour l'anneau de
  // progression coté token (voir CoinBillingRing/demande utilisateur) —
  // chargé une seule fois, uniquement utile en mode à distance.
  Map<String, int>? _economyRate;

  // Séquence "duel" (voir demande utilisateur) : chaque carte monte
  // IMMÉDIATEMENT au centre dès qu'elle est retournée (voir _tapFlip) et
  // y attend l'autre ; une fois les deux réunies, elles y restent 2s
  // avant de repartir ensemble vers la pile du VAINQUEUR — voir
  // _runDuelAnimation. Valeur réelle posée dans initState() (voir
  // _state.roundsCount) — un `0` figé ici rejouait l'animation de la
  // DERNIÈRE manche déjà résolue dès que cet écran était recréé en cours
  // de partie (reconnexion réseau, retour en arrière puis retour dans la
  // partie...), donnant l'impression qu'une carte se retournait seule
  // sans qu'on ait tapé (voir demande utilisateur : "ma carte se
  // retourne sans que je tape ma pile").
  int _lastAnimatedRoundsCount = 0;
  // Limite "battre sa pile" (voir demande utilisateur : "on peut battre
  // uniquement deux fois avant de sortir une carte, après avoir sorti je
  // peux encore battre deux fois max, ainsi de suite") — remis à zéro pour
  // LES DEUX rôles dès qu'une manche se résout (voir _onState), jamais
  // seulement pour celui qui vient de jouer : chacun a son propre "crédit"
  // de 2, mais la remise à zéro est un même événement pour les deux (la
  // fin de la manche).
  final Map<String, int> _shuffleCounts = {};
  static const _maxShufflesPerTurn = 2;
  int _shuffleCountFor(String userId) => _shuffleCounts[userId] ?? 0;
  // Vrai tant que les cartes de la dernière manche doivent rester
  // affichées (guerre en cours OU manche décisive en attente de
  // ramassage) — voir demande utilisateur. Le CONTENU affiché (cartes,
  // "c'est une guerre ou pas") n'est PLUS figé dans des champs séparés :
  // il se recalcule à chaque rendu depuis `_state.lastRoundResult`/
  // `_state.pendingCollectorId` (voir _WarCardDuelArea.build), qui sont
  // TOUJOURS à jour (mis à jour à chaque état reçu, sans condition) —
  // contrairement à d'anciens champs figés au moment du déclenchement de
  // l'animation, qui pouvaient rester bloqués sur une manche précédente
  // si ce déclenchement était sauté (voir demande utilisateur : "Guerre"
  // resté affiché derrière des cartes qui n'étaient plus à égalité).
  bool _duelActive = false;

  // Animation de ramassage (voir demande utilisateur : "en cliquant sur
  // ramasser on voit les cartes se réunir et qui descendent dans les
  // cartes du gagnant") — instantané pris dans _onState juste avant que le
  // pot ne soit vidé par le serveur, purement pour l'animation de SORTIE
  // (jamais relu comme source de vérité, toujours refermé par
  // _closeCollectAnimation après un délai fixe — ne peut donc jamais rester
  // bloqué comme les anciens champs figés).
  bool _collecting = false;
  List<String> _collectingCards = const [];
  String? _collectingWinnerId;

  // Historique fiable des cartes de guerre par côté (voir demande
  // utilisateur : "les premières cartes ont disparu et sa carte est
  // apparue directement" une fois la manche devenue décisive) — construit
  // manche après manche depuis `state.lastRoundResult` (TOUJOURS
  // correctement attribué créateur/partenaire, jamais mélangé), plutôt que
  // depuis `state.pendingPot` : ce dernier est mélangé par le serveur dès
  // qu'une manche décisive survient (juste avant le ramassage), ce qui
  // rendait impossible de savoir de façon fiable quelle carte appartenait
  // à qui à partir de ce moment-là. Remis à zéro uniquement au ramassage
  // effectif (voir `justCollected` dans _onState) — jamais entre deux
  // manches d'une MÊME guerre.
  List<String> _warStackCreator = const [];
  List<String> _warStackPartner = const [];

  bool get _isLocalPassAndPlay => widget.transport is LocalWarCardTransport;

  // Guide pas-à-pas (voir doc de classe de _WarCardGuideStep et demande
  // utilisateur : "prends le même soin pour les autres jeux") — mêmes
  // principes qu'au Jeu de Mémoire : étapes purement informatives,
  // avancées au tap (voir _onGuideStepTapped), rejouable via le "?" de
  // l'AppBar, jamais bloquée par le binôme.
  final _statusGuideKey = GlobalKey();
  final _flipGuideKey = GlobalKey();
  final _coinsGuideKey = GlobalKey();
  final _pauseGuideKey = GlobalKey();
  final _chatGuideKey = GlobalKey();
  final _micGuideKey = GlobalKey();
  final _cameraGuideKey = GlobalKey();
  static const _boardGuideKey = 'war_card_board';
  _WarCardGuideStep? _guideStep;
  bool _guideMicConnecting = false;
  // Démo "retourner sa carte" du guide (voir demande utilisateur :
  // "guider le user vers quelque action pour qu'il comprenne le
  // mécanisme") — révèle la carte du DESSUS de ma vraie pile (simple
  // lecture, aucune triche : c'est déjà la carte que je jouerais), sans
  // jamais appeler widget.transport.flip() ni dépendre du binôme.
  bool _guideFlipped = false;

  @override
  void initState() {
    super.initState();
    _state = widget.transport.currentState;
    _lastAnimatedRoundsCount = _state.roundsCount;
    _subscription = widget.transport.stateStream.listen(_onState);
    ShowcaseView.get().addOnCompleteCallback(_onGuideStepTapped);
    ShowcaseView.get().addOnDismissCallback(_onGuideDismissed);
    _maybeStartGuide();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // Masque la barre de nav système ET celle de l'app le temps de la
    // partie — voir le correctif appliqué à NumberHuntBoardScreen.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppRouter.showGlobalNavBar.value = false;
    });
    if (_commentsBoxId != null) _loadEconomyRate();
  }

  /// Le guide "Comment jouer" n'existe que dans le mode "Présentiel, un seul téléphone" (voir demande
  /// utilisateur) : pas de lancement automatique ni de bouton "?" en partie à distance ou en présentiel
  /// connecté. Les guides qui y mènent renvoient vers ce mode (voir game_guide_notes.dart).
  bool get _guideAvailable => widget.transport is LocalWarCardTransport;

  Future<void> _maybeStartGuide() async {
    if (!_guideAvailable) return;
    final seen = await GameGuideStorage.instance.hasSeen(widget.user.id, _boardGuideKey);
    if (seen || !mounted) return;
    GameGuideStorage.instance.markSeen(widget.user.id, _boardGuideKey);
    _startGuide();
  }

  /// Point d'entrée unique du guide (auto ou via "?") — met la partie en
  /// pause d'abord (voir memory_game_board_screen.dart._startGuide pour
  /// le raisonnement complet : ne pas facturer pendant la démo, le
  /// binôme ne voit que la pause habituelle).
  void _startGuide() {
    if (!_state.isPaused && !_state.finished) {
      widget.transport.pause();
    }
    _startGuideStep(_WarCardGuideStep.status);
  }

  void _startGuideStep(_WarCardGuideStep step) {
    if (!mounted) return;
    setState(() {
      _guideStep = step;
      if (step == _WarCardGuideStep.micReady) _guideMicConnecting = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _guideKeyFor(step);
      if (!ShowcaseView.get().isTargetRendered(key)) {
        setState(() => _guideStep = null);
        return;
      }
      ShowcaseView.get().startShowCase([key]);
    });
  }

  GlobalKey _guideKeyFor(_WarCardGuideStep step) {
    switch (step) {
      case _WarCardGuideStep.status:
        return _statusGuideKey;
      case _WarCardGuideStep.flip:
      case _WarCardGuideStep.flipResult:
        return _flipGuideKey;
      case _WarCardGuideStep.coins:
        return _coinsGuideKey;
      case _WarCardGuideStep.pause:
        return _pauseGuideKey;
      case _WarCardGuideStep.chat:
        return _chatGuideKey;
      case _WarCardGuideStep.micJoin:
      case _WarCardGuideStep.micReady:
        return _micGuideKey;
      case _WarCardGuideStep.cameraReady:
        return _cameraGuideKey;
    }
  }

  void _onGuideStepTapped(int? index, GlobalKey key) {
    switch (_guideStep) {
      case _WarCardGuideStep.status:
        _startGuideStep(_WarCardGuideStep.flip);
        break;
      case _WarCardGuideStep.flip:
        // N'avance PAS ici (gestes de cible désactivés, voir
        // disableDefaultTargetGestures) — seul un vrai tap sur la pile
        // fait avancer (voir _onGuideFlipTap).
        break;
      case _WarCardGuideStep.flipResult:
        setState(() => _guideFlipped = false);
        _startGuideStep(_WarCardGuideStep.coins);
        break;
      case _WarCardGuideStep.coins:
        _startGuideStep(_WarCardGuideStep.pause);
        break;
      case _WarCardGuideStep.pause:
        _startGuideStep(_WarCardGuideStep.chat);
        break;
      case _WarCardGuideStep.chat:
        _startGuideStep(_WarCardGuideStep.micJoin);
        break;
      case _WarCardGuideStep.micJoin:
        _startGuideStep(_WarCardGuideStep.micReady);
        break;
      case _WarCardGuideStep.micReady:
        _startGuideStep(_WarCardGuideStep.cameraReady);
        break;
      case _WarCardGuideStep.cameraReady:
        setState(() {
          _guideStep = null;
          _guideMicConnecting = false;
        });
        break;
      case null:
        break;
    }
  }

  void _onGuideDismissed(GlobalKey? key) {
    if (!mounted) return;
    setState(() {
      _guideStep = null;
      _guideMicConnecting = false;
      _guideFlipped = false;
    });
  }

  /// Tap RÉEL sur MA pile pendant l'étape flip (voir _WarCardPileBase.
  /// guideKey) — révèle la carte du dessus SANS toucher au transport,
  /// puis explique ce qu'il se passe ensuite.
  void _onGuideFlipTap() {
    setState(() => _guideFlipped = true);
    _startGuideStep(_WarCardGuideStep.flipResult);
  }

  Widget _buildGuideVoiceDemo() {
    final phase = switch (_guideStep) {
      _WarCardGuideStep.micJoin => GameGuideVoicePhase.micJoin,
      _WarCardGuideStep.micReady => GameGuideVoicePhase.micReady,
      _WarCardGuideStep.cameraReady => GameGuideVoicePhase.cameraReady,
      _ => null,
    };
    if (phase == null) return const SizedBox.shrink();
    return GameGuideVoiceDemo(
      micKey: _micGuideKey,
      cameraKey: _cameraGuideKey,
      phase: phase,
      connecting: _guideMicConnecting,
      onMicTapToConnect: () => setState(() => _guideMicConnecting = true),
    );
  }

  Future<void> _loadEconomyRate() async {
    try {
      final rate = await GameService.instance.fetchGameEconomyRate();
      if (mounted) setState(() => _economyRate = rate);
    } catch (_) {
      // Best-effort — l'anneau reste simplement invisible sans ce détail.
    }
  }

  /// Temps facturable écoulé, en secondes — voir ServerClock, calibré sur
  /// l'en-tête HTTP Date du serveur, jamais l'horloge brute de l'appareil
  /// (voir demande utilisateur). Base commune à [_coinProgress] et
  /// [_coinsConsumed] pour qu'ils restent parfaitement synchronisés.
  double? _elapsedBillableSeconds() {
    final rate = _economyRate;
    final started = _state.startedAt;
    if (rate == null || started == null) return null;
    final graceSeconds = rate['grace_period_seconds'] ?? 0;
    final now = _state.pausedAt ?? ServerClock.instance.now();
    final elapsed = now.difference(started).inSeconds - graceSeconds;
    return elapsed < 0 ? 0 : elapsed.toDouble();
  }

  /// Fraction (0..1) de progression vers le prochain token déduit —
  /// purement indicatif (voir doc de CoinBillingRing), calculé à partir du
  /// même réglage que le serveur (minutes_per_coin/grace_period_seconds)
  /// mais jamais la source de vérité de la facturation elle-même.
  double _coinProgress() {
    final elapsed = _elapsedBillableSeconds();
    final cycleSeconds = (_economyRate?['minutes_per_coin'] ?? 8) * 60;
    if (elapsed == null || cycleSeconds <= 0) return 0;
    return (elapsed % cycleSeconds) / cycleSeconds;
  }

  /// Nombre de tokens consommés depuis le début de CETTE partie — fluide
  /// comme l'anneau (même calcul), voir demande utilisateur.
  double? _coinsConsumed() {
    final elapsed = _elapsedBillableSeconds();
    final cycleSeconds = (_economyRate?['minutes_per_coin'] ?? 8) * 60;
    if (elapsed == null || cycleSeconds <= 0) return 0;
    return elapsed / cycleSeconds;
  }

  void _onState(WarCardBoardState state) {
    if (!mounted) return;

    // Nouvelle manche résolue (roundsCount vient d'augmenter) : remet à
    // zéro le crédit "battre sa pile" des DEUX rôles (voir demande
    // utilisateur) — indépendant de la séquence d'animation ci-dessous,
    // pour rester correct même si `lastRoundResult` arrivait vide.
    if (state.roundsCount > _state.roundsCount) {
      _shuffleCounts.clear();
    }

    // Une NOUVELLE manche (UNE SEULE comparaison, voir WarCardEngine.
    // resolveRound) vient de se résoudre — voir demande utilisateur : lance
    // la séquence "duel" plutôt que de juste afficher le résultat
    // instantanément. Ne fait QUE déclencher la temporisation : le
    // contenu affiché (cartes, guerre ou pas) se recalcule à chaque
    // rendu depuis `_state` (voir _WarCardDuelArea.build), jamais figé
    // ici — un déclenchement manqué ne peut donc plus bloquer l'affichage
    // sur une manche périmée (voir demande utilisateur : "Guerre" resté
    // affiché derrière des cartes qui n'étaient plus à égalité).
    final isNewRound = state.roundsCount > _lastAnimatedRoundsCount && state.lastRoundResult.isNotEmpty;
    if (isNewRound) _lastAnimatedRoundsCount = state.roundsCount;

    // Complète l'historique fiable des cartes de guerre par côté (voir
    // _warStackCreator/_warStackPartner ci-dessus) — chaque manche résolue
    // (égalité OU décisive) ajoute sa paire, lue depuis `lastRoundResult`
    // qui reste correct même une fois le pot mélangé côté serveur.
    List<String>? newWarStackCreator;
    List<String>? newWarStackPartner;
    if (isNewRound) {
      final round = state.lastRoundResult.last;
      final roundCreatorCard = round['creator'];
      final roundPartnerCard = round['partner'];
      newWarStackCreator = roundCreatorCard == null ? _warStackCreator : [..._warStackCreator, roundCreatorCard];
      newWarStackPartner = roundPartnerCard == null ? _warStackPartner : [..._warStackPartner, roundPartnerCard];
    }

    // Une manche non-décisive (égalité) est la SEULE où les deux cartes
    // qui viennent d'être jouées sont à égalité (voir demande utilisateur :
    // "les deux cartes restent toujours en place... jusqu'à ce que l'un
    // gagne à ramasser", pas de cartes cachées) — dérivé des cartes
    // elles-mêmes (voir WarCardEngine.isTieRound), PAS de
    // `pendingCollectorId` : ce dernier n'est jamais exposé par
    // LocalWarCardTransport (pass-and-play, ramassage toujours
    // automatique), ce qui aurait fait passer CHAQUE manche décisive pour
    // une guerre en pass-and-play (voir demande utilisateur : appliquer la
    // même règle validée à distance aux deux autres modes).
    bool isOngoingWar = false;
    if (isNewRound) {
      final round = state.lastRoundResult.last;
      final roundCreatorCard = round['creator'];
      final roundPartnerCard = round['partner'];
      isOngoingWar = !state.finished &&
          roundCreatorCard != null &&
          roundPartnerCard != null &&
          WarCardEngine.isTieRound(roundCreatorCard, roundPartnerCard);
    }

    // Le pot vient d'être ramassé via le bouton dédié (à distance/
    // présentiel connecté, voir demande utilisateur) — déclenche
    // l'animation de ramassage ("on voit les cartes se réunir et qui
    // descendent dans les cartes du gagnant") ; c'est ELLE, via
    // _closeCollectAnimation, qui referme la séquence "duel" restée en
    // attente (voir la fin de _runDuelAnimation, qui s'arrête sans se
    // refermer tant que `pendingCollectorId` reste non-null) — capture le
    // pot et le vainqueur AVANT l'écrasement de `_state` ci-dessous, sinon
    // il n'y aurait plus rien à animer.
    final justCollected = _duelActive && _state.pendingCollectorId != null && state.pendingCollectorId == null;
    final collectedPot = justCollected ? List<String>.of(_state.pendingPot) : null;
    final collectedWinnerId = justCollected ? _state.pendingCollectorId : null;

    // Manche DÉCISIVE ramassée AUTOMATIQUEMENT (voir LocalWarCardTransport,
    // pass-and-play : pas de bouton "Ramasser", le pot est déjà vide dans
    // `state` dès cette mise à jour) — voir demande utilisateur : "s'assurer
    // que lors du retour, les cartes on le voit revenir pour le gagnant"
    // même dans ce mode, où il n'y a pourtant aucun tap explicite à
    // intercepter. Détecté par élimination : une nouvelle manche, pas une
    // guerre, la partie continue, et pourtant aucun ramassage en attente
    // n'a jamais été exposé — signature propre au ramassage automatique.
    final isDecisiveAutoCollected =
        isNewRound && !isOngoingWar && !state.finished && state.pendingCollectorId == null;
    final autoCollectedCards =
        isDecisiveAutoCollected ? [...?newWarStackCreator, ...?newWarStackPartner] : null;
    final autoCollectedWinnerId = isDecisiveAutoCollected ? state.winnerUserId : null;

    setState(() {
      _state = state;
      if (newWarStackCreator != null) _warStackCreator = newWarStackCreator;
      if (newWarStackPartner != null) _warStackPartner = newWarStackPartner;
      if (justCollected) {
        _collecting = true;
        _collectingCards = collectedPot!;
        _collectingWinnerId = collectedWinnerId;
      } else if (isDecisiveAutoCollected) {
        // Contrairement au ramassage explicite (bouton "Ramasser", où le
        // délai de lecture vient naturellement du temps que met la personne
        // à taper), ici RIEN ne fait attendre — voir demande utilisateur :
        // "si les deux cartes sont en haut, patienter 2 à 3 secondes avant
        // de la ramener vers le lot gagnant pour permettre de lire". Les
        // deux cartes restent donc d'abord affichées normalement (voir
        // _autoCollectAfterPause, qui déclenche `_collecting` seulement
        // après cette pause).
        _duelActive = true;
      }
    });

    if (justCollected) unawaited(_closeCollectAnimation());
    if (isDecisiveAutoCollected) unawaited(_autoCollectAfterPause(autoCollectedCards!, autoCollectedWinnerId));

    // Le ramassage automatique (ci-dessus) gère déjà entièrement
    // l'ouverture/fermeture de `_duelActive` pour cette manche — appeler
    // _runDuelAnimation en plus ferait doublon (elle attend elle-même 1500ms
    // avant de vérifier `pendingCollectorId`, toujours `null` en
    // pass-and-play, et refermerait une deuxième fois pour rien).
    if (isNewRound && !isDecisiveAutoCollected) {
      unawaited(_runDuelAnimation(isOngoingWar: isOngoingWar));
    }

    if (state.finished && !_scoreboardShown && !_duelActive) {
      _scoreboardShown = true;
      // Voir demande utilisateur : "ça doit être instantané" — rafraîchit
      // le solde dès que la partie est vraiment terminée plutôt que
      // d'attendre le retour au tableau de bord.
      if (_commentsBoxId != null) unawaited(WalletBalanceNotifier.instance.refresh());
      // Le tableau de score s'affiche maintenant systématiquement, y
      // compris après un abandon (voir demande utilisateur : "faire pareil
      // si on abandonne, on a le score en bas pour tous les jeux, il faut
      // proposer de quitter et pour rejouer c'est pour celui qui a lancé
      // le jeu") — _showScoreboard gère déjà "Quitter" pour tous, et
      // "Rejouer" réservé à widget.isLauncher (voir showWarCardMatchScoreboard).
      WidgetsBinding.instance.addPostFrameCallback((_) => _showScoreboard());
    }
  }

  /// Pass-and-play uniquement (voir LocalWarCardTransport, ramassage
  /// toujours automatique) — les deux cartes de la manche décisive restent
  /// d'abord affichées normalement (déjà fait par le `setState` de
  /// `_onState` juste avant l'appel), le temps de les LIRE (voir demande
  /// utilisateur : "patienter 2 à 3 secondes avant de la ramener vers le
  /// lot gagnant pour permettre de lire"), puis seulement ENSUITE déclenche
  /// la même animation de ramassage que le bouton "Ramasser" (voir
  /// `_closeCollectAnimation`, qui referme tout à la fin).
  Future<void> _autoCollectAfterPause(List<String> cards, String? winnerId) async {
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;
    setState(() {
      _collecting = true;
      _collectingCards = cards;
      _collectingWinnerId = winnerId;
    });
    await _closeCollectAnimation();
  }

  /// Laisse le temps de voir les cartes du pot se réunir et descendre dans
  /// la pile du côté vainqueur (voir demande utilisateur, animation gérée
  /// par _WarCardDuelArea via `collecting`/`collectingCards`) avant de
  /// refermer le duel — durée alignée sur celle de cette animation. Borné
  /// dans le temps (contrairement à un état figé indéfiniment) : cette
  /// méthode se termine toujours, quoi qu'il arrive côté serveur.
  Future<void> _closeCollectAnimation() async {
    await Future.delayed(const Duration(milliseconds: 520));
    if (!mounted) return;
    setState(() {
      _collecting = false;
      _duelActive = false;
      // Le pot vient d'être réellement ramassé — l'historique de CETTE
      // guerre n'a plus lieu d'être (voir _warStackCreator/_warStackPartner
      // ci-dessus, remis à zéro uniquement ici, jamais entre deux manches
      // d'une même guerre).
      _warStackCreator = const [];
      _warStackPartner = const [];
    });
    if (_state.finished && !_scoreboardShown) {
      _scoreboardShown = true;
      if (_commentsBoxId != null) unawaited(WalletBalanceNotifier.instance.refresh());
      // Voir demande utilisateur : scoreboard systématique, même après un
      // abandon (voir même correctif plus haut dans _onState).
      WidgetsBinding.instance.addPostFrameCallback((_) => _showScoreboard());
    }
  }

  /// Voir demande utilisateur : chaque carte monte IMMÉDIATEMENT au
  /// centre ("VS") dès qu'elle est retournée (voir _tapFlip), et y
  /// attend que l'autre la rejoigne — cette méthode gère la suite d'UNE
  /// SEULE comparaison (voir WarCardEngine.resolveRound, plus de cascade
  /// automatique) : soit une "guerre" (égalité, voir [isOngoingWar]) où
  /// les deux cartes restent posées jusqu'à ce que les DEUX rejouent —
  /// cette méthode est alors rappelée pour la comparaison suivante, sans
  /// minuterie ici — soit une manche décisive, qui affiche le bouton
  /// "Ramasser" juste en dessous après une courte pause. Dans les DEUX
  /// cas, les cartes restent dans la même "boîte" du haut (voir demande
  /// utilisateur) — plus de convergence animée vers la pile du vainqueur.
  /// Ne gère QUE la temporisation/l'ouverture-fermeture de `_duelActive` :
  /// le contenu affiché se recalcule à chaque rendu depuis `_state` (voir
  /// _WarCardDuelArea.build), jamais figé en paramètre ici.
  Future<void> _runDuelAnimation({required bool isOngoingWar}) async {
    if (!mounted) return;
    setState(() => _duelActive = true);

    if (isOngoingWar) {
      // "GUERRE ⚔️" — voir demande utilisateur : "les deux cartes
      // restent toujours en place, on attend que les gens sortent
      // d'autre carte". Pas de minuterie : ces cartes restent affichées
      // (voir _WarCardDuelArea) jusqu'à ce que les DEUX aient retapé —
      // _tapFlip/_shufflePile restent utilisables pendant ce temps (voir
      // _duelBlocksInput) — et rappellent alors cette méthode pour la
      // comparaison suivante dès que le serveur répond.
      return;
    }

    // Courte pause pour laisser le temps de voir les deux cartes avant
    // que le bouton "Ramasser" n'apparaisse juste en dessous (voir
    // demande utilisateur).
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    if (_state.pendingCollectorId != null) {
      // Cartes toujours affichées, pas encore ramassées (voir demande
      // utilisateur : bouton dédié plutôt qu'un ramassage automatique) —
      // on s'arrête ICI, `_duelActive` reste vrai le temps que le bouton
      // "Ramasser" soit tapé. `_onState` referme cette étape dès que le
      // pot est effectivement ramassé (voir `justCollected`).
      return;
    }

    setState(() {
      _duelActive = false;
      // Atteint ici pour TOUTE manche décisive dont `_duelActive` n'a pas
      // déjà été refermé par _closeCollectAnimation — notamment en
      // pass-and-play (voir LocalWarCardTransport, ramassage toujours
      // automatique, `pendingCollectorId` jamais exposé, donc
      // `_closeCollectAnimation` n'y est jamais déclenché) — l'historique de
      // cette guerre n'a plus lieu d'être (voir _warStackCreator/
      // _warStackPartner).
      _warStackCreator = const [];
      _warStackPartner = const [];
    });

    if (_state.finished && !_scoreboardShown) {
      _scoreboardShown = true;
      if (_commentsBoxId != null) unawaited(WalletBalanceNotifier.instance.refresh());
      // Voir demande utilisateur : scoreboard systématique, même après un
      // abandon (voir même correctif plus haut dans _onState).
      WidgetsBinding.instance.addPostFrameCallback((_) => _showScoreboard());
    }
  }

  /// Même dialogue pour le bouton drapeau ET la flèche retour (voir
  /// PopScope dans build()) — voir MemoryGameBoardScreen._confirmAbandon
  /// pour la justification complète.
  Future<bool> _confirmAbandon() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(LocaleScope.t(ctx, 'memory_board_abandon_title')),
        content: Text(LocaleScope.t(ctx, 'memory_board_abandon_content')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(LocaleScope.t(ctx, 'common_cancel'))),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(LocaleScope.t(ctx, 'memory_board_abandon_confirm'), style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _showScoreboard() async {
    if (!mounted) return;
    final rematch = await showWarCardMatchScoreboard(
      context,
      state: _state,
      playerNames: widget.playerNames,
      playerAvatars: widget.playerAvatars,
      colorFor: _colorFor,
      allowRematch: widget.isLauncher && widget.onRematch != null,
    );
    if (rematch == true && widget.isLauncher && widget.onRematch != null && mounted) {
      // Voir demande utilisateur : le chrono et l'appel continuent sans
      // coupure entre deux manches — pas de closeGameSession ici.
      await widget.onRematch!(context);
    } else if (mounted) {
      // "Quitter", ou tap à côté de la feuille (voir demande utilisateur) : referme le jeu
      // (retour au choix de la difficulté pour l'invité·e, voir onQuit).
      // Voir demande utilisateur : "on peut quitter sans forcément cliquer
      // sur le bouton quitter" — ce branchement couvre déjà les deux cas.
      // Ferme VRAIMENT la session (arrête micro/caméra/chrono/facturation
      // pour les DEUX, voir GameSessionLifecycleController).
      final transport = widget.transport;
      if (transport is RemoteWarCardTransport) {
        unawaited(GameService.instance.closeGameSession('war_card', transport.sessionId));
      }
      if (widget.onQuit != null) {
        await widget.onQuit!(context);
      } else {
        Navigator.of(context).pop();
      }
    }
  }

  /// Voir demande utilisateur : repousse la coupure automatique
  /// d'inactivité tant que NOTRE PROPRE micro se rouvre après la fin de la
  /// manche (voir VoiceCallOverlay.onMicActiveChanged).
  void _onMicActiveChanged(bool active) {
    if (!active || !_state.finished) return;
    final transport = widget.transport;
    if (transport is RemoteWarCardTransport) {
      unawaited(GameService.instance.pingGameSessionMic('war_card', transport.sessionId));
    }
  }

  String _elapsed() {
    final started = _state.startedAt;
    if (started == null) return '0:00';
    // Voir demande utilisateur : le chrono continue après la fin de la
    // manche, jusqu'à la fermeture VRAIE de la session.
    final now = _state.pausedAt ?? ServerClock.instance.now();
    // Le chrono attend la même période de grâce que l'anneau de token
    // (voir CoinBillingRing/demande utilisateur) — reste à 0:00 tant que
    // la grâce n'est pas écoulée, nul en dehors du mode à distance.
    final graceSeconds = _economyRate?['grace_period_seconds'] ?? 0;
    final seconds = (now.difference(started).inSeconds - graceSeconds).clamp(0, 1 << 31);
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  /// Rouge pour la première des deux id (par ordre lexicographique) et
  /// bleu pour l'autre — déterministe des deux côtés, même principe que
  /// les autres jeux.
  Color _colorFor(String userId) {
    final ids = widget.playerNames.keys.toList()..sort();
    return userId == ids.first ? _kRedColor : _kBlueColor;
  }

  bool _pendingFlipFor(String userId) => userId == _state.creatorId ? _state.pendingFlipCreator : _state.pendingFlipPartner;

  List<String> _pileFor(String userId) => userId == _state.creatorId ? _state.pileCreator : _state.pilePartner;

  /// "cliquer sur la carte et elle se retourne" (voir demande
  /// utilisateur) — [userId] : creatorId ou partnerId, jamais "moi" (voir
  /// doc de classe). La révélation "en attente de l'autre" affichée tant
  /// que la manche n'est pas résolue n'est PAS une valeur figée au moment
  /// du tap : elle se lit en LIVE depuis `_state.pileCreator/pilePartner`
  /// (voir _WarCardDuelArea) — aucune copie qui pourrait diverger de la
  /// vérité côté moteur si l'état se met à jour entre-temps.
  Future<void> _tapFlip(String userId) async {
    if (_state.finished || _state.isPaused || _duelBlocksInput) return;
    if (_pendingFlipFor(userId)) return;
    if (_pileFor(userId).isEmpty) return;

    await widget.transport.flip(userId);
  }

  // Vrai tant que la dernière manche affichée est une "guerre" en cours
  // (égalité, voir demande utilisateur) — recalculé depuis `_state`,
  // jamais figé (voir doc de classe de _runDuelAnimation). Dérivé des deux
  // cartes réellement jouées (voir WarCardEngine.isTieRound), PAS de
  // `_state.pendingCollectorId` : ce dernier n'est jamais exposé par
  // LocalWarCardTransport (pass-and-play, ramassage toujours automatique),
  // ce qui aurait fait passer CHAQUE manche décisive pour une guerre en
  // pass-and-play — voir demande utilisateur : appliquer la même règle
  // validée à distance aux deux autres modes.
  bool get _isOngoingWarNow {
    if (!_duelActive || _state.finished) return false;
    if (_state.lastRoundResult.isEmpty) return false;
    final round = _state.lastRoundResult.last;
    final creatorCard = round['creator'];
    final partnerCard = round['partner'];
    if (creatorCard == null || partnerCard == null) return false;
    return WarCardEngine.isTieRound(creatorCard, partnerCard);
  }

  // Bloque les taps SEULEMENT pendant l'attente de ramassage d'une
  // manche DÉCISIVE (l'état va bientôt changer) — pas pendant une
  // "guerre" (égalité) : là, les deux cartes restent affichées mais
  // chacun doit pouvoir retaper pour jouer sa carte suivante (voir
  // demande utilisateur : "on attend que les gens sortent d'autre
  // carte"). Toujours bloqué pendant `_collecting` : à ce moment,
  // `_state.pendingCollectorId` est déjà revenu à `null` côté serveur
  // (pot ramassé), ce qui ferait sinon passer `_isOngoingWarNow` à vrai
  // par erreur pendant que l'animation de ramassage joue encore.
  bool get _duelBlocksInput => _collecting || (_duelActive && !_isOngoingWarNow);

  /// "Battre" SA PROPRE pile en cours de partie (voir demande
  /// utilisateur : "je peux regarder mes propres cartes, est-ce possible
  /// de les battre également") — interdit tant que MA carte est déjà
  /// engagée dans un duel (`_pendingFlipFor`) : sinon je pourrais changer
  /// la carte que je viens de jouer après l'avoir vue "révélée" à l'écran,
  /// alors que la résolution lit le dessus de la pile au moment où les
  /// DEUX ont tapé, pas au moment du tap lui-même (voir WarCardEngine.flip).
  Future<void> _shufflePile(String userId) async {
    if (_state.finished || _state.isPaused || _duelBlocksInput) return;
    if (_pendingFlipFor(userId)) return;
    if (_pileFor(userId).length < 2) return;
    if (_shuffleCountFor(userId) >= _maxShufflesPerTurn) return;

    setState(() => _shuffleCounts[userId] = _shuffleCountFor(userId) + 1);
    await widget.transport.shufflePile(userId);
  }

  /// "Ramasser" le pot d'une manche gagnée (voir demande utilisateur :
  /// "un bouton pour m'informer de ramasser... une manière d'impliquer
  /// chacun proprement", à distance/Bluetooth uniquement — jamais en
  /// pass-and-play, voir `WarCardBoardState.pendingCollectorId`, toujours
  /// `null` côté LocalWarCardTransport). L'écran ne se referme qu'une fois
  /// le nouvel état reçu (voir `justCollected` dans _onState) — pas de
  /// mise à jour optimiste locale ici, un geste trop rare/délibéré pour
  /// justifier la complexité.
  Future<void> _collectPot() async {
    if (!_state.iMustCollect || _collecting) return;
    await widget.transport.collectPot();
  }

  /// Affiche SA propre pile en éventail (voir demande utilisateur) — sans
  /// incidence sur l'équité de la partie : la Bataille n'a aucune
  /// décision à prendre, connaître l'ordre de ses propres cartes à
  /// l'avance ne change rien à l'issue.
  void _showFan(BuildContext context, List<String> pile, Color color) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _WarCardFanSheet(pile: pile, color: color),
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    ShowcaseView.get().removeOnCompleteCallback(_onGuideStepTapped);
    ShowcaseView.get().removeOnDismissCallback(_onGuideDismissed);
    _clockTimer?.cancel();
    widget.transport.dispose();
    widget.nearbyComms?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Différé au frame suivant (voir memory_game_board_screen.dart).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppRouter.showGlobalNavBar.value = true;
    });
    super.dispose();
  }

  Future<void> _shuffle() => widget.transport.shuffleDeck();

  Future<void> _dealAutomatic() => widget.transport.dealAutomatic();

  Future<void> _dealManualStep() => widget.transport.dealManualStep();

  Future<void> _readyUp() => widget.transport.readyUp();

  /// Bouton "Terminer la partie" du popup de solde épuisé (voir
  /// GameWalletGuard) — même geste qu'un abandon volontaire, sans re-passer
  /// par la confirmation (déjà confirmé en fermant ce popup-là).
  String? get _commentsBoxId {
    final transport = widget.transport;
    return transport is RemoteWarCardTransport ? transport.boxId : null;
  }

  String get _sessionId {
    final transport = widget.transport;
    return transport is RemoteWarCardTransport ? transport.sessionId : '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final commentsBoxId = _commentsBoxId;

    if (!_state.dealt) {
      return _WarCardPreDealScreen(
        game: widget.game,
        theme: theme,
        state: _state,
        playerNames: widget.playerNames,
        colorFor: _colorFor,
        onShuffle: _shuffle,
        onDealAutomatic: _dealAutomatic,
        onDealManualStep: _dealManualStep,
      );
    }

    if (!_state.started) {
      return _WarCardReadyScreen(
        game: widget.game,
        theme: theme,
        state: _state,
        playerNames: widget.playerNames,
        colorFor: _colorFor,
        onReadyUp: _readyUp,
      );
    }

    return PopScope(
      canPop: _state.finished,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Ne referme plus l'écran soi-même (voir demande utilisateur :
        // scoreboard systématique après un abandon, même geste que le
        // bouton drapeau ci-dessous) — _onState détecte `state.finished`
        // et affiche le tableau de score (avec "Rejouer" pour le lanceur,
        // "Quitter" pour tous), qui referme l'écran lui-même.
        if (await _confirmAbandon()) {
          await widget.transport.abandon();
        }
      },
      child: Stack(
      children: [
        // Isole tout le plateau du clavier (voir GameCommentOverlay) : SANS
        // ce retrait explicite de l'inset, `resizeToAvoidBottomInset: false`
        // seul ne suffit pas toujours à empêcher la grille de remonter sur
        // certains appareils/versions Android (voir demande utilisateur :
        // "les images ne doivent jamais remonter") — ici, RIEN sous ce
        // point ne peut plus voir le clavier, quoi qu'il arrive.
        MediaQuery.removeViewInsets(
          context: context,
          removeBottom: true,
          child: Scaffold(
      backgroundColor: theme.background,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(
          widget.game.nameFor(LocaleScope.of(context).current.code),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
        actions: [
          if (!_state.finished)
            Showcase(
              key: _pauseGuideKey,
              title: _state.isPaused ? 'Reprends la partie' : 'Mets en pause',
              description: _state.isPaused
                  ? "Ce bouton reprend la partie quand tu es prêt·e — tant qu'elle est en pause, le chrono et les Tokens ne bougent pas."
                  : "Tu peux mettre la partie en pause à tout moment si tu dois t'absenter.",
              targetShapeBorder: const CircleBorder(),
              child: _state.isPaused
                  ? IconButton(
                      icon: _resuming
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_circle_outline),
                      tooltip: (_state.pausedByMe || _state.pausedByUserId == null)
                          ? LocaleScope.t(context, 'memory_board_resume_tooltip')
                          : LocaleScope.t(context, 'memory_board_paused_by_partner_tooltip', {
                              'name': widget.playerNames[_state.pausedByUserId] ??
                                  LocaleScope.t(context, 'memory_board_partner_fallback'),
                            }),
                      onPressed: (!_resuming && (_state.pausedByMe || _state.pausedByUserId == null))
                          ? () => handleResumeTap(context, widget.transport.resume, (busy) => setState(() => _resuming = busy))
                          : null,
                    )
                  : IconButton(
                      icon: const Icon(Icons.pause_circle_outline),
                      tooltip: LocaleScope.t(context, 'memory_board_pause_tooltip'),
                      onPressed: () => widget.transport.pause(),
                    ),
            ),
          if (!_state.finished)
            IconButton(
              icon: const Icon(Icons.flag_outlined),
              tooltip: LocaleScope.t(context, 'memory_board_abandon_tooltip'),
              onPressed: () async {
                if (await _confirmAbandon()) {
                  await widget.transport.abandon();
                }
              },
            ),
          if (_state.finished && widget.isLauncher && widget.onRematch != null)
            IconButton(
              icon: const Icon(Icons.replay_rounded),
              tooltip: LocaleScope.t(context, 'memory_score_rematch'),
              onPressed: () => widget.onRematch!(context),
            ),
          if (!_state.finished && _guideAvailable)
            IconButton(icon: const Icon(Icons.help_outline_rounded), tooltip: 'Revoir le guide', onPressed: _startGuide),
        ],
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Showcase(
                          key: _statusGuideKey,
                          title: 'Manches jouées',
                          description: 'Ce texte compte le nombre de manches déjà jouées dans cette partie.',
                          targetBorderRadius: BorderRadius.circular(8),
                          child: Text(
                            _state.finished
                                ? LocaleScope.t(context, 'game_board_finished_label')
                                : LocaleScope.t(context, 'war_card_rounds_played', {'count': '${_state.roundsCount}'}),
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 16, color: theme.primary),
                          ),
                        ),
                        Showcase(
                          key: _coinsGuideKey,
                          title: 'Temps et Tokens',
                          description: commentsBoxId != null && widget.isLauncher
                              ? 'Le chrono et le nombre de Tokens déjà consommés par cette partie à distance.'
                              : 'Le temps écoulé depuis le début de la partie.',
                          targetBorderRadius: BorderRadius.circular(8),
                          child: Row(
                            children: [
                              Icon(Icons.timer_outlined, size: 16, color: theme.textOnBackgroundMuted),
                              const SizedBox(width: 4),
                              Text(_elapsed(), style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted)),
                              if (commentsBoxId != null && widget.isLauncher) ...[
                                const SizedBox(width: 8),
                                CoinBillingRing(theme: theme, progress: _coinProgress()),
                                if (_coinsConsumed() != null) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    '-${_coinsConsumed()!.toStringAsFixed(2)}',
                                    style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: theme.primary),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _WarCardDuelArea(
                      theme: theme,
                      state: _state,
                      leftId: _isLocalPassAndPlay ? _state.creatorId : widget.user.id,
                      rightId: _isLocalPassAndPlay ? _state.partnerId : _partnerId(),
                      isLocalMode: _isLocalPassAndPlay,
                      playerNames: widget.playerNames,
                      colorFor: _colorFor,
                      duelActive: _duelActive,
                      onTapFlip: _tapFlip,
                      onTapPeek: (userId) => _showFan(context, _pileFor(userId), _colorFor(userId)),
                      onTapShuffle: _shufflePile,
                      shuffleCountFor: _shuffleCountFor,
                      onTapCollect: _collectPot,
                      flipGuideKey: _flipGuideKey,
                      guideFlipped: _guideFlipped,
                      onGuideFlipTap: _guideStep == _WarCardGuideStep.flip ? _onGuideFlipTap : null,
                      collecting: _collecting,
                      collectingCards: _collectingCards,
                      collectingWinnerId: _collectingWinnerId,
                      warStackCreator: _warStackCreator,
                      warStackPartner: _warStackPartner,
                    ),
                  ),
                ],
              ),
              if (_state.isPaused && _guideStep == null)
                Positioned.fill(
                  child: Container(
                    color: theme.background,
                    alignment: Alignment.center,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.pause_circle_filled_rounded, size: 48, color: theme.primary),
                          const SizedBox(height: 12),
                          Text(
                            LocaleScope.t(context, 'memory_board_paused_title'),
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: theme.textOnBackground),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _state.pausedByUserId == null
                                ? LocaleScope.t(context, 'memory_board_paused_subtitle_depleted')
                                : (_state.pausedByMe
                                    ? LocaleScope.t(context, 'memory_board_paused_subtitle_me')
                                    : LocaleScope.t(context, 'memory_board_paused_subtitle_partner', {
                                        'name': widget.playerNames[_state.pausedByUserId] ??
                                            LocaleScope.t(context, 'memory_board_partner_fallback'),
                                      })),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                          ),
                          if (_state.pausedByMe || _state.pausedByUserId == null) ...[
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: _resuming
                                  ? null
                                  : () => handleResumeTap(context, widget.transport.resume, (busy) => setState(() => _resuming = busy)),
                              icon: _resuming
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.play_arrow_rounded),
                              label: Text(LocaleScope.t(context, 'memory_board_resume_button')),
                              style: ElevatedButton.styleFrom(backgroundColor: theme.primary, foregroundColor: Colors.white),
                            ),
                            if (_state.pausedByUserId == null) GameWalletDepletedNotice(theme: theme),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
        ),
        if (commentsBoxId != null)
          GameCommentOverlay(boxId: commentsBoxId, enabled: true, guideKey: _chatGuideKey)
        else if (widget.nearbyComms != null)
          GameCommentOverlay(
            nearbyComms: widget.nearbyComms,
            enabled: true,
            myName: widget.nearbyMyName ?? '',
            partnerName: widget.nearbyPartnerName ?? '',
            guideKey: _chatGuideKey,
          ),
        // Voir demande utilisateur : micro/caméra restent actifs après la
        // fin de la manche jusqu'à ce qu'on quitte vraiment (voir
        // _showScoreboard) — la feuille de score, affichée PAR-DESSUS, ne
        // doit ni les cacher ni empêcher d'y toucher (voir AlwaysOnTopLayer).
        AlwaysOnTopLayer(
          child: commentsBoxId != null
              ? VoiceCallOverlay(
                  boxId: commentsBoxId,
                  myUserId: widget.user.id,
                  partnerUserId: _partnerId(),
                  enabled: true,
                  paused: _state.isPaused,
                  forceEnded: _state.isPaused,
                  onMicActiveChanged: _onMicActiveChanged,
                )
              : widget.nearbyComms != null
                  ? NearbyVoiceOverlay(comms: widget.nearbyComms, enabled: true, paused: _state.isPaused)
                  : const SizedBox.shrink(),
        ),
        _buildGuideVoiceDemo(),
        GameWalletGuard(
          boxId: commentsBoxId,
          sessionType: 'war_card',
          sessionId: _sessionId,
        ),
      ],
      ),
    );
  }

  String _partnerId() => widget.playerNames.keys.firstWhere((id) => id != widget.user.id, orElse: () => widget.user.id);
}

/// Phase "avant partie" (voir demande utilisateur) : les 52 cartes sont
/// visibles empilées ENSEMBLE, "Battre" les remélange réellement (pas
/// juste une animation) autant de fois qu'on veut, tant que le partage
/// n'a pas commencé. Le partage manuel n'a PAS de bouton dédié : on tape
/// DIRECTEMENT sur le paquet (voir demande utilisateur), en bas de
/// l'écran — chaque tap envoie une carte du dessus vers la pile de
/// gauche et une carte du dessous vers la pile de droite, visibles en
/// haut à côté du nom de chacun. "Partage automatique" reste un bouton
/// séparé pour distribuer instantanément le reste du paquet.
class _WarCardPreDealScreen extends StatefulWidget {
  final Game game;
  final ThemePalette theme;
  final WarCardBoardState state;
  final Map<String, String> playerNames;
  final Color Function(String userId) colorFor;
  final Future<void> Function() onShuffle;
  final Future<void> Function() onDealAutomatic;
  final Future<void> Function() onDealManualStep;

  const _WarCardPreDealScreen({
    required this.game,
    required this.theme,
    required this.state,
    required this.playerNames,
    required this.colorFor,
    required this.onShuffle,
    required this.onDealAutomatic,
    required this.onDealManualStep,
  });

  @override
  State<_WarCardPreDealScreen> createState() => _WarCardPreDealScreenState();
}

class _WarCardPreDealScreenState extends State<_WarCardPreDealScreen> with TickerProviderStateMixin {
  bool _busy = false;
  late final AnimationController _shuffleController;
  // Voir demande utilisateur : "on doit voir les cartes se déplacer du
  // paquet vers leur destination... deux cartes [l'une après l'autre]" —
  // l'affichage reste figé sur l'état PRÉCÉDENT pendant que ce contrôleur
  // anime le trajet, et ne bascule sur le nouvel état qu'une fois le vol
  // terminé (voir didUpdateWidget/_animateDeal).
  late final AnimationController _flightController;
  late WarCardBoardState _displayState;

  final _overlayKey = GlobalKey();
  final _deckKey = GlobalKey();
  final _creatorSlotKey = GlobalKey();
  final _partnerSlotKey = GlobalKey();
  // Deux points de départ DISTINCTS (voir demande utilisateur : "on a
  // l'impression que les deux cartes partent toutes du dessus" — le
  // départ doit visuellement correspondre à la vraie règle, une carte du
  // DESSUS et une du DESSOUS du paquet, voir WarCardEngine.dealManualStep).
  Offset? _flightFromTop;
  Offset? _flightFromBottom;
  Offset? _flightTo;
  bool _flightToCreator = true;

  @override
  void initState() {
    super.initState();
    _displayState = widget.state;
    _shuffleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _flightController = AnimationController(vsync: this, duration: const Duration(milliseconds: 640));
  }

  @override
  void didUpdateWidget(covariant _WarCardPreDealScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // UN seul tap de partage manuel ajoute EXACTEMENT deux cartes, mais
    // toujours du MÊME côté (voir demande utilisateur : "les deux cartes
    // qui sortent doivent aller pour une [seule] personne") — un partage
    // automatique (ou un battage, qui ne change aucune longueur de pile)
    // n'a pas vocation à être animé carte par carte.
    final creatorGrew = widget.state.pileCreator.length - _displayState.pileCreator.length;
    final partnerGrew = widget.state.pilePartner.length - _displayState.pilePartner.length;
    final isManualStep = (creatorGrew == 2 && partnerGrew == 0) || (partnerGrew == 2 && creatorGrew == 0);
    if (_flightController.isAnimating) return;
    if (isManualStep) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _animateDeal(toCreator: creatorGrew == 2));
    } else {
      _displayState = widget.state;
    }
  }

  @override
  void dispose() {
    _shuffleController.dispose();
    _flightController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {bool animateShuffle = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    if (animateShuffle) unawaited(_shuffleController.forward(from: 0));
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Offset? _centerOf(GlobalKey key, RenderBox ancestor) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;

    return box.localToGlobal(Offset.zero, ancestor: ancestor) + Offset(box.size.width / 2, box.size.height / 2);
  }

  /// Les positions RÉELLES de la carte du DESSUS (deck[0], la face visible
  /// en bas à gauche du tas — voir _WarCardFullStack) et de la carte du
  /// DESSOUS (le dos le plus enfoui, en haut à droite) — voir demande
  /// utilisateur : le vol doit visiblement partir de deux cartes
  /// DIFFÉRENTES du tas, pas d'un même point arbitraire.
  ({Offset top, Offset bottom})? _deckEdges(GlobalKey key, RenderBox ancestor) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;

    final topLeft = box.localToGlobal(Offset.zero, ancestor: ancestor);
    // Carte du dessus : Positioned(left: 0, bottom: 0) dans _WarCardFullStack.
    final top = topLeft + const Offset(_kCardWidth / 2, 0) + Offset(0, box.size.height - _kCardHeight / 2);
    // Carte du dessous : Positioned(right: 0, top: 0), la toute première
    // dessinée (donc la plus enfouie sous les autres dos).
    final bottom = topLeft + Offset(box.size.width - _kCardWidth / 2, _kCardHeight / 2);

    return (top: top, bottom: bottom);
  }

  /// Anime le trajet des deux cartes du paquet vers LA MÊME pile, L'UNE
  /// APRÈS L'AUTRE (voir demande utilisateur), avant de basculer
  /// l'affichage sur le nouvel état (compte à jour de la pile).
  Future<void> _animateDeal({required bool toCreator}) async {
    final ancestor = _overlayKey.currentContext?.findRenderObject() as RenderBox?;
    final deckEdges = ancestor == null ? null : _deckEdges(_deckKey, ancestor);
    final destCenter = ancestor == null ? null : _centerOf(toCreator ? _creatorSlotKey : _partnerSlotKey, ancestor);

    if (ancestor == null || deckEdges == null || destCenter == null) {
      // Mise en page pas encore prête (première frame) — pas d'animation
      // possible, on répercute directement le nouvel état.
      if (mounted) setState(() => _displayState = widget.state);
      return;
    }

    setState(() {
      _flightFromTop = deckEdges.top;
      _flightFromBottom = deckEdges.bottom;
      _flightTo = destCenter;
      _flightToCreator = toCreator;
    });

    await _flightController.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _displayState = widget.state;
      _flightFromTop = null;
      _flightFromBottom = null;
      _flightTo = null;
    });
    _flightController.reset();
  }

  /// "déplier les cartes et on peut voir" (voir demande utilisateur) —
  /// réutilise la même feuille "éventail" que pour voir sa propre pile en
  /// cours de partie, avec un texte adapté (le paquet n'appartient encore
  /// à personne).
  void _peekDeck(BuildContext context, List<String> deck, Color color) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _WarCardFanSheet(
        pile: deck,
        color: color,
        title: LocaleScope.t(context, 'war_card_predeal_peek_title', {'count': '${deck.length}'}),
        subtitle: LocaleScope.t(context, 'war_card_predeal_peek_subtitle'),
      ),
    );
  }

  /// Voir demande utilisateur : plutôt que de cacher Battre/Partage
  /// automatique/l'œil une fois le partage manuel entamé, ils restent
  /// visibles mais grisés — un tap dessus affiche cette info quelques
  /// secondes au lieu de rien faire silencieusement.
  void _showLockedInfo(BuildContext context) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(LocaleScope.t(context, 'war_card_predeal_locked_hint')),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<Widget> _buildFlyingCards() {
    final fromTop = _flightFromTop;
    final fromBottom = _flightFromBottom;
    final to = _flightTo;
    if (fromTop == null || fromBottom == null || to == null) return const [];

    final color = widget.colorFor(_flightToCreator ? _displayState.creatorId : _displayState.partnerId);
    // Les DEUX cartes vont à LA MÊME pile (voir demande utilisateur), l'une
    // après l'autre — un léger décalage entre les deux points d'arrivée
    // pour qu'on distingue bien qu'il s'agit de deux cartes, pas une seule.
    const jitter = Offset(7, -5);

    return [
      // La carte du DESSUS du paquet — part du HAUT du tas.
      AnimatedBuilder(
        animation: _flightController,
        builder: (context, _) {
          // Sature à 1.0 dès la moitié du trajet total : la première
          // carte arrive et RESTE visible sur la pile pendant que la
          // seconde s'envole — les deux ne disparaissent qu'ensemble, en
          // même temps que l'affichage bascule sur le nouvel état.
          final phase = Curves.easeInOut.transform((_flightController.value.clamp(0.0, 0.5)) / 0.5);
          final pos = Offset.lerp(fromTop, to - jitter, phase)!;

          return Positioned(
            left: pos.dx - _kCardWidth / 2,
            top: pos.dy - _kCardHeight / 2,
            child: _CardBack(color: color),
          );
        },
      ),
      // La carte du DESSOUS du paquet — part du BAS du tas.
      AnimatedBuilder(
        animation: _flightController,
        builder: (context, _) {
          if (_flightController.value <= 0.5) return const SizedBox.shrink();
          final phase = Curves.easeInOut.transform((_flightController.value - 0.5) / 0.5);
          final pos = Offset.lerp(fromBottom, to + jitter, phase)!;

          return Positioned(
            left: pos.dx - _kCardWidth / 2,
            top: pos.dy - _kCardHeight / 2,
            child: _CardBack(color: color),
          );
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final state = _displayState;
    final deck = state.deck;
    final started = state.pileCreator.isNotEmpty || state.pilePartner.isNotEmpty;
    final canTapDeck = !_busy && !_flightController.isAnimating && deck.isNotEmpty;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(
          widget.game.nameFor(LocaleScope.of(context).current.code),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: Stack(
            key: _overlayKey,
            fit: StackFit.expand,
            children: [
              // Petit écran (voir demande utilisateur) : le contenu défile
              // au lieu de déborder — `minHeight` garde le rendu "plein
              // écran + Expanded centré" habituel sur un écran normal,
              // tout en autorisant le scroll si ça ne rentre pas.
              LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: _buildBody(theme, state, deck, started, canTapDeck),
                    ),
                  ),
                ),
              ),
              ..._buildFlyingCards(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemePalette theme, WarCardBoardState state, List<String> deck, bool started, bool canTapDeck) {
    return Column(
            children: [
              // Les deux piles en construction, à côté du nom de chacun —
              // voir demande utilisateur : "une carte du bas et une du
              // haut se positionnent en haut à droite ou à gauche à côté
              // du nom".
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // `card: null` en permanence ici (voir demande
                    // utilisateur : "les cartes ne doivent pas se
                    // retourner pour être visibles" pendant le partage) —
                    // seul le compte progresse, jamais l'identité de la
                    // carte reçue tant qu'on est sur cet écran.
                    KeyedSubtree(
                      key: _creatorSlotKey,
                      child: _CardSlot(
                        card: null,
                        color: widget.colorFor(state.creatorId),
                        label: widget.playerNames[state.creatorId] ?? '',
                        pileCount: state.pileCreator.length,
                      ),
                    ),
                    KeyedSubtree(
                      key: _partnerSlotKey,
                      child: _CardSlot(
                        card: null,
                        color: widget.colorFor(state.partnerId),
                        label: widget.playerNames[state.partnerId] ?? '',
                        pileCount: state.pilePartner.length,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          LocaleScope.t(context, 'war_card_predeal_title'),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: theme.textOnBackground),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          started
                              ? LocaleScope.t(context, 'war_card_predeal_manual_progress', {'count': '${deck.length}'})
                              : LocaleScope.t(context, 'war_card_predeal_subtitle'),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Le paquet, EN BAS de l'écran (voir demande utilisateur) —
              // c'est lui qu'on tape directement pour distribuer, pas de
              // bouton "Distribuer" séparé.
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Column(
                  children: [
                    // Battre / partage automatique n'ont plus de sens une
                    // fois le partage MANUEL déjà entamé — plutôt que de
                    // les cacher, ils restent visibles mais GRISÉS, et un
                    // tap dessus affiche une info explicative quelques
                    // secondes (voir demande utilisateur) — idem pour
                    // l'œil (voir plus bas).
                    _LockableAction(
                      locked: started,
                      onLockedTap: () => _showLockedInfo(context),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: (started || _busy) ? null : () => _run(widget.onShuffle, animateShuffle: true),
                          icon: const Icon(Icons.shuffle_rounded),
                          label: Text(LocaleScope.t(context, 'war_card_predeal_shuffle')),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _LockableAction(
                      locked: started,
                      onLockedTap: () => _showLockedInfo(context),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: (started || _busy) ? null : () => _run(widget.onDealAutomatic),
                          icon: const Icon(Icons.flash_on_rounded),
                          label: Text(LocaleScope.t(context, 'war_card_predeal_deal_auto')),
                          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    AnimatedBuilder(
                      animation: _shuffleController,
                      builder: (context, child) {
                        // Petite secousse latérale pendant l'animation de
                        // battage — juste assez pour se lire comme un vrai
                        // battage de cartes, pas une distraction permanente.
                        final shake = math.sin(_shuffleController.value * math.pi * 6) * 6 * (1 - _shuffleController.value);
                        return Transform.translate(offset: Offset(shake, 0), child: child);
                      },
                      child: KeyedSubtree(
                        key: _deckKey,
                        child: GestureDetector(
                          onTap: canTapDeck ? () => _run(widget.onDealManualStep) : null,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              _WarCardFullStack(count: deck.length, color: theme.primary),
                              if (deck.isNotEmpty)
                                Positioned(
                                  top: -8,
                                  right: -8,
                                  child: Opacity(
                                    opacity: started ? 0.4 : 1,
                                    child: _WarCardPeekButton(
                                      color: theme.primary,
                                      onTap: started ? () => _showLockedInfo(context) : () => _peekDeck(context, deck, theme.primary),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      LocaleScope.t(context, 'war_card_predeal_count', {'count': '${deck.length}'}),
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w800, color: theme.primary),
                    ),
                    if (deck.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        LocaleScope.t(context, 'war_card_predeal_tap_hint'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
  }
}

/// Phase "prêt ?" (voir demande utilisateur) : une fois le paquet
/// entièrement distribué, les deux piles se recentrent à l'écran (plus de
/// boutons Battre/Partage auto/œil), et un bouton "Commencer" apparaît.
/// En pass-and-play UN tap suffit (les deux rôles sont sur le même
/// appareil, voir [LocalWarCardTransport.readyUp]) ; à distance/présentiel
/// connecté, LES DEUX doivent taper — copie du principe déjà utilisé pour
/// "Retourner" (voir WarCardEngine.flip), simple attente sans refus
/// explicite tant que l'autre n'a pas confirmé (voir demande utilisateur).
class _WarCardReadyScreen extends StatefulWidget {
  final Game game;
  final ThemePalette theme;
  final WarCardBoardState state;
  final Map<String, String> playerNames;
  final Color Function(String userId) colorFor;
  final Future<void> Function() onReadyUp;

  const _WarCardReadyScreen({
    required this.game,
    required this.theme,
    required this.state,
    required this.playerNames,
    required this.colorFor,
    required this.onReadyUp,
  });

  @override
  State<_WarCardReadyScreen> createState() => _WarCardReadyScreenState();
}

class _WarCardReadyScreenState extends State<_WarCardReadyScreen> with SingleTickerProviderStateMixin {
  bool _busy = false;
  late final AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))..forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _tapReady() async {
    if (_busy || widget.state.iAmReady) return;
    setState(() => _busy = true);
    try {
      await widget.onReadyUp();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final state = widget.state;
    final partnerName = widget.playerNames[state.iAmCreator ? state.partnerId : state.creatorId] ??
        LocaleScope.t(context, 'memory_score_player_fallback');

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(
          widget.game.nameFor(LocaleScope.of(context).current.code),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: CurvedAnimation(parent: _entranceController, curve: Curves.easeOutBack),
                  child: FadeTransition(
                    opacity: _entranceController,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _CardSlot(
                          card: null,
                          color: widget.colorFor(state.creatorId),
                          label: widget.playerNames[state.creatorId] ?? '',
                          pileCount: state.pileCreator.length,
                        ),
                        const SizedBox(width: 24),
                        _CardSlot(
                          card: null,
                          color: widget.colorFor(state.partnerId),
                          label: widget.playerNames[state.partnerId] ?? '',
                          pileCount: state.pilePartner.length,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  LocaleScope.t(context, 'war_card_ready_title'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: theme.textOnBackground),
                ),
                const SizedBox(height: 6),
                Text(
                  state.iAmReady
                      ? LocaleScope.t(context, 'war_card_ready_waiting', {'name': partnerName})
                      : (state.partnerIsReady
                          ? LocaleScope.t(context, 'war_card_ready_partner_wants', {'name': partnerName})
                          : LocaleScope.t(context, 'war_card_ready_subtitle')),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: (_busy || state.iAmReady) ? null : _tapReady,
                    icon: state.iAmReady
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.play_circle_fill_rounded),
                    label: Text(LocaleScope.t(context, 'war_card_ready_start_button')),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Enrobe un bouton pour le griser et intercepter le tap quand [locked]
/// — voir demande utilisateur : "au lieu de les cacher ils peuvent
/// rester et grisé, si j'essaie de cliquer un petit info apparaît". Le
/// bouton enrobé doit lui-même désactiver son `onPressed` (mettre `null`)
/// quand [locked] est vrai, sinon son propre gestionnaire de tap capte le
/// geste avant que celui-ci ne remonte jusqu'ici.
class _LockableAction extends StatelessWidget {
  final bool locked;
  final VoidCallback onLockedTap;
  final Widget child;

  const _LockableAction({required this.locked, required this.onLockedTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: locked ? 0.4 : 1,
      child: GestureDetector(
        onTap: locked ? onLockedTap : null,
        child: child,
      ),
    );
  }
}

/// Icône à l'angle du paquet — voir demande utilisateur : "ajoute une
/// icône à l'angle des cartes... si on clique ça déplie les cartes et on
/// peut voir".
class _WarCardPeekButton extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _WarCardPeekButton({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(Icons.visibility_rounded, size: 18, color: color),
        ),
      ),
    );
  }
}

/// Bouton "battre sa pile" (voir demande utilisateur : "je peux regarder
/// mes propres cartes, est-ce possible de les battre également") — même
/// habillage que _WarCardPeekButton, à l'angle opposé (haut-gauche).
class _WarCardShuffleButton extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _WarCardShuffleButton({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(Icons.shuffle_rounded, size: 18, color: color),
        ),
      ),
    );
  }
}

const _kLeftBottomAlign = Alignment(-0.55, -0.1);
const _kRightBottomAlign = Alignment(0.55, -0.1);
const _kLeftStageAlign = Alignment(-0.32, -0.75);
const _kRightStageAlign = Alignment(0.32, -0.75);

/// Zone de jeu principale de "Bataille" — voir demande utilisateur : plus
/// de boutons "Retourner" séparés, on tape DIRECTEMENT sur sa carte (en
/// bas de l'écran, une par côté) pour la jouer ; un œil à l'angle de
/// chaque carte permet de voir sa pile en éventail.
class _WarCardDuelArea extends StatelessWidget {
  final ThemePalette theme;
  final WarCardBoardState state;
  final String leftId;
  final String rightId;
  final bool isLocalMode;
  final Map<String, String> playerNames;
  final Color Function(String userId) colorFor;
  // Vrai tant que les cartes de la dernière manche doivent rester
  // affichées (voir _WarCardBoardScreenState._duelActive) — le contenu
  // (cartes, guerre ou pas, compteurs) se recalcule TOUJOURS ci-dessous
  // depuis [state], jamais figé en paramètre séparé (voir demande
  // utilisateur : "Guerre" resté affiché derrière des cartes qui
  // n'étaient plus à égalité — un ancien champ figé pouvait rester bloqué
  // sur une manche périmée si son déclenchement était manqué).
  final bool duelActive;
  final Future<void> Function(String userId) onTapFlip;
  final void Function(String userId) onTapPeek;
  // "Battre" sa propre pile en cours de partie (voir demande utilisateur) —
  // async comme onTapFlip : _WarCardBoardScreenState._shufflePile applique
  // ses propres garde-fous (carte déjà engagée, pile trop petite, etc.).
  final Future<void> Function(String userId) onTapShuffle;
  // Limite "battre sa pile" (voir demande utilisateur : max 2 par manche,
  // remis à zéro à chaque nouvelle manche résolue — voir
  // _WarCardBoardScreenState._shuffleCounts).
  final int Function(String userId) shuffleCountFor;
  // "Ramasser" le pot d'une manche gagnée (voir demande utilisateur : un
  // bouton dédié plutôt qu'un ramassage automatique, à distance/Bluetooth
  // uniquement) — sans argument : `_WarCardBoardScreenState._collectPot`
  // relit `state.pendingCollectorId` lui-même.
  final VoidCallback onTapCollect;
  // Guide pas-à-pas (voir demande utilisateur : "guider le user vers
  // quelque action pour qu'il comprenne le mécanisme") — bulle sur MA
  // pile uniquement (gauche), jamais celle du binôme. [guideFlipped]
  // révèle localement la carte du dessus (voir _WarCardBoardScreenState.
  // _onGuideFlipTap) ; [onGuideFlipTap] non-null UNIQUEMENT pendant
  // l'étape "flip" du guide, pour intercepter le tap réel sur ma pile
  // même si `canPlay` est faux (partie en pause pendant tout le guide).
  final GlobalKey? flipGuideKey;
  final bool guideFlipped;
  final VoidCallback? onGuideFlipTap;
  // Animation de ramassage (voir demande utilisateur : "on voit les cartes
  // se réunir et qui descendent dans les cartes du gagnant") — pilotée par
  // _WarCardBoardScreenState (voir _onState/justCollected), qui capture un
  // instantané de [state.pendingPot] juste avant qu'il ne soit vidé par le
  // serveur, borné dans le temps (voir _closeCollectAnimation), jamais un
  // état qui pourrait rester bloqué indéfiniment.
  final bool collecting;
  final List<String> collectingCards;
  final String? collectingWinnerId;
  // Historique fiable des cartes de guerre par côté (voir
  // _WarCardBoardScreenState._warStackCreator/_warStackPartner) — construit
  // depuis `lastRoundResult`, jamais depuis `state.pendingPot` (mélangé par
  // le serveur dès qu'une manche décisive survient), pour que l'empilement
  // affiché reste complet et correctement attribué jusqu'au ramassage.
  final List<String> warStackCreator;
  final List<String> warStackPartner;

  const _WarCardDuelArea({
    required this.theme,
    required this.state,
    required this.leftId,
    required this.rightId,
    required this.isLocalMode,
    required this.playerNames,
    required this.colorFor,
    required this.duelActive,
    required this.onTapFlip,
    required this.onTapPeek,
    required this.onTapShuffle,
    required this.shuffleCountFor,
    required this.onTapCollect,
    this.flipGuideKey,
    this.guideFlipped = false,
    this.onGuideFlipTap,
    this.collecting = false,
    this.collectingCards = const [],
    this.collectingWinnerId,
    this.warStackCreator = const [],
    this.warStackPartner = const [],
  });

  @override
  Widget build(BuildContext context) {
    final leftColor = colorFor(leftId);
    final rightColor = colorFor(rightId);
    final leftIsCreator = leftId == state.creatorId;
    final leftPile = leftIsCreator ? state.pileCreator : state.pilePartner;
    final rightPile = leftIsCreator ? state.pilePartner : state.pileCreator;
    final leftTapped = leftIsCreator ? state.pendingFlipCreator : state.pendingFlipPartner;
    final rightTapped = leftIsCreator ? state.pendingFlipPartner : state.pendingFlipCreator;
    // À distance/présentiel connecté, seul MON côté (gauche) est
    // interactif — la pile de droite (partenaire) n'appartient qu'à SON
    // appareil. En pass-and-play, les deux côtés sont sur le même
    // appareil, donc tous les deux interactifs (voir doc de classe).
    final canActLeft = !state.finished && !state.isPaused;
    final canActRight = canActLeft && isLocalMode;

    // La dernière manche jouée (une seule comparaison, voir
    // WarCardEngine.resolveRound) — relue directement depuis [state] à
    // CHAQUE rendu, jamais figée dans un champ séparé (voir demande
    // utilisateur : "Guerre" resté affiché derrière des cartes qui
    // n'étaient plus à égalité — un champ figé pouvait rester bloqué sur
    // une manche périmée si son déclenchement était manqué).
    // Vrai tant que la manche affichée est une "guerre" (égalité) — voir
    // demande utilisateur : "GUERRE ⚔️... les deux cartes restent en
    // place" — plutôt qu'une manche décisive en attente de ramassage.
    // Dérivé des DEUX cartes réellement jouées (voir WarCardEngine.
    // isTieRound), PAS de `pendingCollectorId` : ce dernier n'est JAMAIS
    // exposé par LocalWarCardTransport (pass-and-play), qui ramasse
    // toujours automatiquement — s'y fier aurait fait passer CHAQUE manche
    // décisive pour une guerre en pass-and-play (voir demande
    // utilisateur : appliquer la même règle validée à distance aux deux
    // autres modes).
    final lastRound = state.lastRoundResult.isNotEmpty ? state.lastRoundResult.last : null;
    final lastRoundCreatorCard = lastRound?['creator'];
    final lastRoundPartnerCard = lastRound?['partner'];
    final lastRoundWasTie = lastRoundCreatorCard != null &&
        lastRoundPartnerCard != null &&
        WarCardEngine.isTieRound(lastRoundCreatorCard, lastRoundPartnerCard);
    final duelIsWarStep = duelActive && !state.finished && lastRoundWasTie;

    // "En attente de l'autre" — lu EN LIVE depuis la pile actuelle, jamais
    // une copie figée au moment du tap (voir _tapFlip) : la carte engagée
    // ne bouge pas tant que la manche n'est pas résolue (voir
    // WarCardEngine.flip), donc la relire à chaque rendu ne peut jamais
    // diverger de ce que le moteur va effectivement comparer.
    // Cartes de guerre SUPERPOSÉES par côté — voir demande utilisateur :
    // "pas de remplacement... on voit qu'il a sorti 2 cartes, pareil pour
    // le binôme ou l'adversaire" — puis, une fois la guerre devenue
    // décisive, "les premières cartes ont disparu, il ne restait que la
    // dernière". Source = [warStackCreator]/[warStackPartner] (voir
    // _WarCardBoardScreenState), JAMAIS `state.pendingPot` : ce dernier est
    // mélangé par le serveur dès la résolution décisive (juste avant le
    // ramassage), donc plus fiable pour reconstituer qui a joué quoi à ce
    // moment précis — l'historique reconstruit ici reste donc complet et
    // correctement attribué jusqu'au ramassage effectif. On y ajoute EN
    // LIVE la carte que ce côté vient de tapoter pendant une guerre encore
    // en cours (avant même que l'autre ait répondu) — le dessus d'une pile
    // est déterministe (voir WarCardEngine._resolveRound, jamais de pioche
    // aléatoire), donc jamais en contradiction avec ce que le moteur
    // comparera réellement une fois les deux tapées.
    List<String> sideCards({required bool isCreatorSide, required bool tapped, required List<String> pile}) {
      final accumulated = isCreatorSide ? warStackCreator : warStackPartner;
      if (duelActive) {
        return [
          ...accumulated,
          if (duelIsWarStep && tapped && pile.isNotEmpty) pile.first,
        ];
      }
      return tapped && pile.isNotEmpty ? [pile.first] : const <String>[];
    }

    final leftCards = guideFlipped
        ? (leftPile.isNotEmpty ? [leftPile.first] : const <String>[])
        : sideCards(isCreatorSide: leftIsCreator, tapped: leftTapped, pile: leftPile);
    final rightCards = sideCards(isCreatorSide: !leftIsCreator, tapped: rightTapped, pile: rightPile);

    // Voir demande utilisateur : le compteur descend à n-1 DÈS le tap
    // (avant résolution) — une fois la manche résolue (voir duelActive),
    // `state.pileCreator/pilePartner` reflète déjà la carte jouée
    // (retirée dès WarCardEngine.resolveRound, pot fusionné seulement au
    // ramassage), donc plus besoin de compteur figé séparé ici.
    final leftCount = duelActive ? leftPile.length : (leftTapped ? leftPile.length - 1 : leftPile.length);
    final rightCount = duelActive ? rightPile.length : (rightTapped ? rightPile.length - 1 : rightPile.length);

    // Dès qu'une carte est révélée (retournement optimiste OU manche
    // résolue), elle monte IMMÉDIATEMENT au centre et y reste — voir
    // demande utilisateur : "les cartes doivent rester toujours en
    // place... dans la boîte en haut", que ce soit une guerre (égalité)
    // ou une manche décisive en attente de ramassage. Plus de convergence
    // animée vers la pile du vainqueur (retiré suite à demande
    // utilisateur).
    Alignment alignFor({required bool isLeft, required bool revealed}) {
      if (!revealed) return isLeft ? _kLeftBottomAlign : _kRightBottomAlign;
      return isLeft ? _kLeftStageAlign : _kRightStageAlign;
    }

    return Stack(
      children: [
        // "GUERRE ⚔️" — uniquement pendant une manche non-décisive (voir
        // demande utilisateur), pas pendant la convergence finale.
        // Au-dessus de la boîte des cartes sorties (au-dessus de
        // _kLeftStageAlign/_kRightStageAlign, Y=-0.75) — voir demande
        // utilisateur : chevauchait auparavant les étiquettes des piles
        // en dessous.
        if (duelActive && duelIsWarStep)
          Positioned.fill(
            key: const ValueKey('war_card_guerre_label'),
            child: Align(
              alignment: const Alignment(0, -0.92),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    LocaleScope.t(context, 'war_card_battle_label'),
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 18, color: _kRedColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    LocaleScope.t(context, 'war_card_war_hint'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                  ),
                ],
              ),
            ),
          ),
        // Badge du nombre de cartes dans la boîte — TOUJOURS affiché,
        // jamais retiré de l'arbre (voir demande utilisateur : "même si
        // c'est 0 il ne doit pas disparaître") — compte les cartes
        // RÉELLEMENT visibles à cet instant ([leftCards]+[rightCards], voir
        // sideCards ci-dessus), donc passe à 1 dès que la toute première
        // carte sort (avant même la résolution de la manche), pas
        // seulement une fois le pot constitué — cohérent sur les 3 modes
        // (à distance, présentiel connecté, pass-and-play), puisque
        // [leftCards]/[rightCards] sont déjà calculés de façon fiable pour
        // chacun (voir demande utilisateur : "pour tous les options...
        // même règle").
        Positioned.fill(
          key: const ValueKey('war_card_pot_badge'),
          child: Align(
            alignment: const Alignment(0.95, -0.95),
            // Repasse à 0 dès le tap sur "Ramasser" (voir demande
            // utilisateur), sans attendre la confirmation serveur.
            child: _WarCardPotBadge(count: collecting ? 0 : leftCards.length + rightCards.length),
          ),
        ),
        // Le VS reste centré ENTRE les deux piles (voir demande
        // utilisateur) — remonté avec elles pour réduire le grand vide
        // laissé en haut de l'écran.
        Positioned.fill(
          key: const ValueKey('war_card_vs'),
          child: Align(
            alignment: const Alignment(0, -0.1),
            child: Text('VS', style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 16, color: theme.textOnBackgroundMuted)),
          ),
        ),
        // Positioned.fill sur CHAQUE enfant de ce Stack (voir demande
        // utilisateur : "quand le btn Ramasser apparaît ça fait bouger
        // légèrement les cartes de la box") — sans ça, un simple `Align`
        // compte dans le calcul de la taille du Stack ; l'apparition d'un
        // nouvel enfant (le bouton "Ramasser", absent de l'arbre jusque-là)
        // pouvait agrandir cette taille calculée et décaler en pixels tous
        // les pourcentages d'alignement des AUTRES enfants, dont les
        // cartes. `Positioned.fill` sort chaque enfant du calcul de taille
        // du Stack (fixée par son parent, déjà contraint) sans changer son
        // positionnement visuel.
        //
        // CHAQUE enfant a aussi sa propre `key` explicite (voir demande
        // utilisateur : "on ne voit pas le mouvement de la carte qui
        // quitte pour aller rejoindre la box... précédé de la disparition
        // et de l'apparition de la première carte") — sans clé, Flutter
        // associe l'ancien et le nouvel enfant par leur POSITION dans
        // cette liste. Or le badge et le label "Guerre" ci-dessus
        // apparaissent/disparaissent selon l'état (`duelActive`,
        // `duelIsWarStep`) — leur apparition décale d'un cran tous les
        // enfants suivants dans la liste, ce qui faisait perdre à Flutter
        // la correspondance avec les enfants déjà montés (dont les cartes
        // et leur `AnimatedAlign`) : il les détruisait et recréait tous,
        // d'où le clignotement de la carte déjà affichée et l'absence
        // d'animation pour la carte qui vient d'arriver (son état
        // d'animation "précédent" n'existait plus). Une clé stable par
        // enfant permet à Flutter de les reconnaître individuellement,
        // peu importe leur position.
        Positioned.fill(
          key: const ValueKey('war_card_left_pile_base'),
          child: Align(
            alignment: _kLeftBottomAlign,
            child: _WarCardPileBase(
              label: playerNames[leftId] ?? '',
              color: leftColor,
              count: leftCount,
              canPlay: canActLeft && !leftTapped && leftPile.isNotEmpty,
              canPeek: true,
              // 2 max par manche (voir demande utilisateur et
              // _WarCardBoardScreenState._maxShufflesPerTurn, seule source
              // de vérité pour l'application réelle de la limite).
              canShuffle: canActLeft && !leftTapped && leftPile.length > 1 && shuffleCountFor(leftId) < 2,
              onTapFlip: () => onTapFlip(leftId),
              onTapPeek: () => onTapPeek(leftId),
              onTapShuffle: () => onTapShuffle(leftId),
              guideKey: flipGuideKey,
              guideTitle: guideFlipped ? 'Elle attend ton binôme' : 'Tape pour retourner',
              guideDescription: guideFlipped
                  ? "Ta carte est révélée et attend au centre. Dès que ton binôme tape la sienne aussi, elles s'affrontent : la plus forte gagne les deux. Égalité ? C'est la bataille : trois cartes cachées de chaque côté, puis on retourne à nouveau."
                  : "Tape ta pile pour retourner ta carte. Dès que ton binôme aura fait pareil, vos deux cartes s'affrontent au centre — la plus forte gagne les deux.",
              onGuideTap: onGuideFlipTap,
            ),
          ),
        ),
        Positioned.fill(
          key: const ValueKey('war_card_right_pile_base'),
          child: Align(
            alignment: _kRightBottomAlign,
            child: _WarCardPileBase(
              label: playerNames[rightId] ?? '',
              color: rightColor,
              count: rightCount,
              canPlay: canActRight && !rightTapped && rightPile.isNotEmpty,
              canPeek: isLocalMode,
              canShuffle: canActRight && !rightTapped && rightPile.length > 1 && shuffleCountFor(rightId) < 2,
              onTapFlip: () => onTapFlip(rightId),
              onTapPeek: () => onTapPeek(rightId),
              onTapShuffle: () => onTapShuffle(rightId),
            ),
          ),
        ),
        // Toujours montés (jamais insérés/retirés de l'arbre) pour que
        // l'alignement puisse s'ANIMER en douceur dès la révélation —
        // voir demande utilisateur : "elle monte immédiatement". Masqués
        // pendant l'animation de ramassage (voir bloc `collecting`
        // ci-dessous, qui prend le relais avec son propre instantané des
        // cartes).
        if (!collecting) ...[
          Positioned.fill(
            key: const ValueKey('war_card_left_cards'),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeInOut,
              alignment: alignFor(isLeft: true, revealed: leftCards.isNotEmpty),
              child: leftCards.isEmpty ? const SizedBox.shrink() : _WarCardStack(cards: leftCards, color: leftColor),
            ),
          ),
          Positioned.fill(
            key: const ValueKey('war_card_right_cards'),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeInOut,
              alignment: alignFor(isLeft: false, revealed: rightCards.isNotEmpty),
              child: rightCards.isEmpty ? const SizedBox.shrink() : _WarCardStack(cards: rightCards, color: rightColor),
            ),
          ),
        ],
        // "Ramasser" tapé (voir demande utilisateur : "on voit les cartes
        // se réunir et qui descendent dans les cartes du gagnant") — les
        // cartes du pot (instantané pris juste avant que le serveur ne le
        // vide, voir _WarCardBoardScreenState._onState) convergent vers la
        // pile du côté vainqueur puis s'estompent. Durée alignée sur
        // _closeCollectAnimation, qui referme le duel une fois terminé.
        if (collecting)
          Positioned.fill(
            key: const ValueKey('war_card_collecting'),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeInCubic,
              builder: (context, t, child) {
                final target = collectingWinnerId == leftId ? _kLeftBottomAlign : _kRightBottomAlign;
                const start = Alignment(0, -0.75);
                final align = Alignment.lerp(start, target, t)!;
                return Align(
                  alignment: align,
                  child: Opacity(
                    opacity: 1 - t * 0.9,
                    child: Transform.scale(scale: 1 - t * 0.35, child: child),
                  ),
                );
              },
              child: _WarCardStack(
                cards: collectingCards,
                color: collectingWinnerId == leftId ? leftColor : rightColor,
              ),
            ),
          ),
        // "touche ta carte pour la jouer" (voir demande utilisateur) —
        // remontée avec les piles, pas collée au bord de l'écran. Masqué
        // pendant l'attente de ramassage (voir bloc suivant) : les DEUX
        // ont déjà tapé pour CETTE manche, ce serait trompeur.
        if (!collecting && !(duelActive && state.pendingCollectorId != null) && canActLeft && (!leftTapped || (isLocalMode && !rightTapped)))
          Positioned.fill(
            key: const ValueKey('war_card_tap_hint'),
            child: Align(
              alignment: const Alignment(0, 0.3),
              child: Text(
                LocaleScope.t(context, 'war_card_tap_hint'),
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
              ),
            ),
          ),
        // "Ramasser mes cartes" (voir demande utilisateur : "un bouton
        // pour m'informer de ramasser... impliquer chacun proprement") —
        // affiché dès qu'une manche DÉCISIVE (pas une guerre) est jouée,
        // après la courte pause de _runDuelAnimation qui reste
        // délibérément figée tant que le ramassage n'a pas eu lieu. Le
        // binôme voit qui doit ramasser, pas de bouton actif pour lui.
        if (!collecting && duelActive && !duelIsWarStep && state.pendingCollectorId != null)
          Positioned.fill(
            key: const ValueKey('war_card_collect_button'),
            child: Align(
              // Position fixe, la même des deux côtés, juste en dessous des
              // cartes qui restent dans leur "boîte" du haut (voir demande
              // utilisateur : plus de convergence, cartes toujours au même
              // niveau).
              alignment: const Alignment(0, -0.35),
              child: state.iMustCollect
                  ? FilledButton.icon(
                      onPressed: onTapCollect,
                      icon: const Icon(Icons.back_hand_rounded, size: 18),
                      label: Text(LocaleScope.t(context, 'war_card_collect_button')),
                    )
                  : Text(
                      LocaleScope.t(context, 'war_card_collect_waiting', {
                        'partner': playerNames[state.pendingCollectorId] ?? '',
                      }),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                    ),
            ),
          ),
      ],
    );
  }
}

/// Une pile, EN BAS de l'écran (voir demande utilisateur) — dos de
/// cartes empilés, tapable pour jouer, avec un œil à l'angle haut-droit
/// (voir sa pile en éventail).
class _WarCardPileBase extends StatefulWidget {
  final String label;
  final Color color;
  final int count;
  final bool canPlay;
  final bool canPeek;
  final bool canShuffle;
  final VoidCallback onTapFlip;
  final VoidCallback onTapPeek;
  final VoidCallback onTapShuffle;
  final GlobalKey? guideKey;
  final String? guideTitle;
  final String? guideDescription;
  // Non-null UNIQUEMENT pendant l'étape "flip" du guide (voir
  // _WarCardBoardScreenState._onGuideFlipTap) — intercepte le tap réel
  // sur cette pile même quand `canPlay` est faux (partie en pause
  // pendant tout le guide, voir demande utilisateur : chacun doit
  // pouvoir tester le guide sans dépendre du binôme).
  final VoidCallback? onGuideTap;

  const _WarCardPileBase({
    required this.label,
    required this.color,
    required this.count,
    required this.canPlay,
    required this.canPeek,
    required this.canShuffle,
    required this.onTapFlip,
    required this.onTapPeek,
    required this.onTapShuffle,
    this.guideKey,
    this.guideTitle,
    this.guideDescription,
    this.onGuideTap,
  });

  @override
  State<_WarCardPileBase> createState() => _WarCardPileBaseState();
}

class _WarCardPileBaseState extends State<_WarCardPileBase> with SingleTickerProviderStateMixin {
  // Animation "éventail qui s'ouvre puis se ferme" au tap sur "battre"
  // (voir demande utilisateur) — purement visuelle, indépendante du vrai
  // mélange déclenché en parallèle par widget.onTapShuffle (voir
  // _WarCardFullStack.fanAmount).
  late final AnimationController _shuffleController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void dispose() {
    _shuffleController.dispose();
    super.dispose();
  }

  void _onTapShuffle() {
    widget.onTapShuffle();
    unawaited(_shuffleController.forward(from: 0));
  }

  @override
  Widget build(BuildContext context) {
    final pile = GestureDetector(
      onTap: widget.onGuideTap ?? (widget.canPlay ? widget.onTapFlip : null),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: _shuffleController,
            builder: (context, _) => _WarCardFullStack(
              count: widget.count,
              color: widget.color,
              // sin(π·t) : 0 au repos comme à la fin, pic à 1 au milieu de
              // l'animation — l'éventail s'ouvre puis se referme tout seul.
              fanAmount: math.sin(math.pi * _shuffleController.value),
            ),
          ),
          if (widget.canPeek)
            Positioned(
              top: -8,
              right: -8,
              child: _WarCardPeekButton(color: widget.color, onTap: widget.onTapPeek),
            ),
          // Masqué (pas juste désactivé) quand la carte du dessus est déjà
          // engagée dans un duel — voir _shufflePile : la battre à ce
          // moment-là changerait la carte jouée après coup.
          if (widget.canShuffle)
            Positioned(
              top: -8,
              left: -8,
              child: _WarCardShuffleButton(color: widget.color, onTap: _onTapShuffle),
            ),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.label, style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: widget.color)),
        const SizedBox(height: 8),
        if (widget.guideKey == null)
          pile
        else
          Showcase(
            key: widget.guideKey!,
            title: widget.guideTitle ?? 'Tape pour retourner',
            description: widget.guideDescription ??
                "Tape ta pile pour retourner ta carte. Dès que ton binôme aura fait pareil, vos deux cartes s'affrontent au centre — la plus forte gagne les deux.",
            targetBorderRadius: BorderRadius.circular(12),
            disableDefaultTargetGestures: widget.onGuideTap != null,
            child: pile,
          ),
        const SizedBox(height: 6),
        Text('${widget.count}', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: widget.color)),
      ],
    );
  }
}

/// La face d'une carte révélée — extrait de l'ancien `_CardSlot` pour
/// être positionnée indépendamment (voir `_WarCardDuelArea`, la carte
/// voyage désormais de la pile vers le centre puis vers le vainqueur).
class _WarCardFaceCard extends StatelessWidget {
  final String card;
  final Color color;

  const _WarCardFaceCard({required this.card, required this.color});

  @override
  Widget build(BuildContext context) {
    return PlayingCardFace(card: card, color: color, width: _kCardWidth, height: _kCardHeight);
  }
}

/// Cartes de guerre superposées d'un même côté — voir demande utilisateur :
/// "pas de remplacement... on voit qu'il a sorti 2 cartes" — chaque carte
/// jouée pendant la guerre en cours reste visible, légèrement décalée en
/// diagonale derrière la suivante (la plus récente au-dessus). Le décalage
/// est plafonné (voir [_maxVisibleOffset]) : au-delà, les cartes
/// supplémentaires restent bien présentes dans la liste (comptées par le
/// badge, voir _WarCardPotBadge) mais se superposent exactement pour ne
/// pas faire déborder l'écran lors d'une longue guerre.
class _WarCardStack extends StatelessWidget {
  static const _offset = 9.0;
  static const _maxVisibleOffset = 4;

  final List<String> cards;
  final Color color;

  const _WarCardStack({required this.cards, required this.color});

  @override
  Widget build(BuildContext context) {
    final depth = (cards.length - 1).clamp(0, _maxVisibleOffset);
    return SizedBox(
      width: _kCardWidth + depth * _offset,
      height: _kCardHeight + depth * _offset,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < cards.length; i++)
            Positioned(
              left: i.clamp(0, _maxVisibleOffset) * _offset,
              top: i.clamp(0, _maxVisibleOffset) * _offset,
              // Clé par carte+position (voir demande utilisateur : "voir la
              // carte se déplacer... comme ça se fait") — une NOUVELLE carte
              // ajoutée au tas obtient une clé inédite, donc un nouveau
              // widget monté à cet endroit, ce qui relance son animation
              // d'entrée depuis zéro (voir _WarCardStackEntry) ; les cartes
              // déjà là gardent la leur et ne rejouent pas l'animation.
              child: _WarCardStackEntry(
                key: ValueKey('${cards[i]}_$i'),
                card: cards[i],
                color: color,
              ),
            ),
        ],
      ),
    );
  }
}

/// Anime l'entrée d'UNE carte dans le tas — monte depuis la pile du joueur
/// (en dessous) jusqu'à sa position empilée, voir demande utilisateur :
/// "je veux que l'on voie la carte se déplacer pour monter dans la boîte
/// comme ça se fait" (jusqu'ici la carte apparaissait instantanément dans
/// le tas dès qu'elle s'y ajoutait).
class _WarCardStackEntry extends StatelessWidget {
  final String card;
  final Color color;

  const _WarCardStackEntry({super.key, required this.card, required this.color});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, (1 - t) * 70),
        child: Opacity(opacity: t, child: child),
      ),
      child: _WarCardFaceCard(card: card, color: color),
    );
  }
}

/// Le paquet complet, empilé — voir demande utilisateur : "on doit voir en
/// premier lieu toutes les cartes empilées ensemble", donc un seul tas
/// visuel bien épais (pas deux piles distinctes comme en cours de partie).
class _WarCardFullStack extends StatelessWidget {
  final int count;
  final Color color;
  // Animation "battre sa pile" (voir demande utilisateur : "éventail qui
  // s'ouvre puis se ferme") — 0 au repos (pile bien rangée), monte vers 1
  // au pic de l'éventail puis redescend à 0, piloté par
  // _WarCardPileBaseState. N'affecte que le rendu, jamais l'ordre réel des
  // cartes (voir _shufflePile, qui déclenche le vrai mélange côté
  // transport en parallèle).
  final double fanAmount;

  const _WarCardFullStack({required this.count, required this.color, this.fanAmount = 0});

  @override
  Widget build(BuildContext context) {
    // Jusqu'à 6 dos décalés pour suggérer l'épaisseur des 52 cartes, sans
    // dessiner littéralement 52 widgets superposés.
    final depth = count <= 0 ? 0 : (count >= 52 ? 6 : (1 + (count * 5 / 52)).round());
    // Ordre de dessin (arrière → avant) : les dos empilés en diagonale
    // (i = depth..1), puis la carte de face (i = 0, sans décalage).
    final backIndices = [for (var i = depth; i >= 1; i--) i, 0];
    const maxSpreadRadians = 0.5; // ~29°, éventail complet à fanAmount = 1

    return SizedBox(
      width: _kCardWidth + depth * 2.5 + _kCardWidth * 0.4 * fanAmount,
      height: _kCardHeight + depth * 2.5,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var layer = 0; layer < backIndices.length; layer++)
            _buildLayer(backIndices[layer], layer, backIndices.length, depth, maxSpreadRadians),
        ],
      ),
    );
  }

  Widget _buildLayer(int i, int layer, int layerCount, int depth, double maxSpreadRadians) {
    // t va de 0 (dos le plus enfoui) à 1 (carte de face) — l'angle est
    // centré sur 0 pour que l'éventail s'ouvre symétriquement autour de la
    // position empilée d'origine.
    final t = layerCount <= 1 ? 0.5 : layer / (layerCount - 1);
    final angle = (t - 0.5) * maxSpreadRadians * fanAmount;

    return Positioned(
      right: i == 0 ? null : (depth - i) * 2.5,
      left: i == 0 ? 0 : null,
      top: i == 0 ? null : (depth - i) * 2.5,
      bottom: i == 0 ? 0 : null,
      child: Transform.rotate(
        // Pivote depuis le coin bas-gauche, comme un éventail de cartes
        // tenu en main.
        angle: angle,
        alignment: Alignment.bottomLeft,
        child: _CardBack(color: color, dimmed: i > 1),
      ),
    );
  }
}

/// Pot de guerre accumulé (voir demande utilisateur : "toutes les cartes
/// empilées visibles + un petit badge X cartes") — réutilise le même
/// visuel de pile épaisse que le paquet ([_WarCardFullStack]), réduit,
/// avec un badge numéroté par-dessus plutôt que de dessiner chaque carte
/// individuellement (peu lisible dès qu'une guerre s'éternise).
// Juste le badge (voir demande utilisateur : "supprimer les cartes jaunes
// et garder juste le badge") — plus de dessin de pile, uniquement le
// nombre de cartes en jeu dans le pot de guerre, toujours affiché tel
// quel (y compris "0").
class _WarCardPotBadge extends StatelessWidget {
  final int count;

  const _WarCardPotBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: Colors.amber.shade700, borderRadius: BorderRadius.circular(12)),
      child: Text(
        '$count',
        style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
      ),
    );
  }
}

const _kCardWidth = 90.0;
const _kCardHeight = 126.0;

class _CardSlot extends StatelessWidget {
  final String? card;
  final Color color;
  final String label;
  final int pileCount;

  const _CardSlot({required this.card, required this.color, required this.label, required this.pileCount});

  @override
  Widget build(BuildContext context) {
    final rank = card?.substring(0, card!.length - 1);
    final suit = card?.substring(card!.length - 1);
    final suitSymbol = switch (suit) {
      'S' => '♠',
      'H' => '♥',
      'D' => '♦',
      'C' => '♣',
      _ => '',
    };
    final isRedSuit = suit == 'H' || suit == 'D';

    // Le nombre de cartes réellement encore en jeu (jusqu'à 3) détermine
    // combien de "dos" décalés dessiner derrière la carte du dessus — on
    // voit ainsi tout de suite qu'il s'agit d'une PILE, pas d'une carte
    // unique, même quand elle est presque vide.
    final stackDepth = pileCount <= 0 ? 0 : (pileCount >= 3 ? 3 : pileCount);

    return Column(
      children: [
        Text(label, style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 8),
        SizedBox(
          // Marge pour laisser respirer les dos de cartes décalés en haut
          // à droite de la pile.
          width: _kCardWidth + 10,
          height: _kCardHeight + 10,
          child: Stack(
            children: [
              for (var i = stackDepth; i >= 1; i--)
                Positioned(
                  right: (stackDepth - i) * 3.0,
                  top: (stackDepth - i) * 3.0,
                  child: _CardBack(color: color, dimmed: i > 1),
                ),
              Positioned(
                left: 0,
                bottom: 0,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  transitionBuilder: (child, animation) {
                    final flip = Tween<double>(begin: 1, end: 0).animate(animation);
                    return AnimatedBuilder(
                      animation: flip,
                      child: child,
                      builder: (context, child) {
                        final angle = flip.value * 3.14159 / 2;
                        return Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..setEntry(3, 2, 0.001)..rotateY(angle),
                          child: child,
                        );
                      },
                    );
                  },
                  child: card == null
                      ? _CardBack(key: const ValueKey('back'), color: color)
                      : Container(
                          key: ValueKey(card),
                          width: _kCardWidth,
                          height: _kCardHeight,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
                          ),
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                rank ?? '',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 26,
                                  color: isRedSuit ? _kRedColor : Colors.black87,
                                ),
                              ),
                              Text(suitSymbol, style: TextStyle(fontSize: 26, color: isRedSuit ? _kRedColor : Colors.black87)),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text('$pileCount', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

/// Dos de carte — un motif losange répété plutôt qu'un simple rectangle
/// vide, pour que même la carte du dessus se lise clairement comme une
/// carte à jouer (pas juste un rectangle blanc) tant qu'elle n'est pas
/// retournée.
class _CardBack extends StatelessWidget {
  final Color color;
  final bool dimmed;

  const _CardBack({super.key, required this.color, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    final backColor = dimmed ? color.withValues(alpha: 0.35) : color;
    return Container(
      width: _kCardWidth,
      height: _kCardHeight,
      decoration: BoxDecoration(
        color: backColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
        boxShadow: dimmed ? null : const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
      ),
      alignment: Alignment.center,
      child: dimmed
          ? null
          : Icon(Icons.diamond_outlined, color: Colors.white.withValues(alpha: 0.55), size: 28),
    );
  }
}

/// Feuille "éventail" — voir demande utilisateur : tape sur ta pile pour
/// voir toutes tes cartes restantes étalées, dans l'ORDRE où elles seront
/// jouées (la première de la liste est la prochaine retournée).
class _WarCardFanSheet extends StatelessWidget {
  final List<String> pile;
  final Color color;
  // `null` = titre/sous-titre par défaut ("Tes {count} cartes"...) — voir
  // demande utilisateur : la même feuille sert aussi à "déplier" le
  // paquet ENTIER avant la distribution (war_card_predeal_peek_title),
  // où ce texte n'aurait pas de sens ("tes cartes" alors que rien n'a
  // encore été distribué à personne).
  final String? title;
  final String? subtitle;

  const _WarCardFanSheet({required this.pile, required this.color, this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: theme.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.textOnBackgroundMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title ?? LocaleScope.t(context, 'war_card_fan_title', {'count': '${pile.length}'}),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w800, color: theme.textOnBackground),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle ?? LocaleScope.t(context, 'war_card_fan_subtitle'),
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 150,
              child: pile.isEmpty
                  ? Center(
                      child: Text(
                        LocaleScope.t(context, 'war_card_fan_empty'),
                        style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: pile.length,
                      itemBuilder: (context, index) {
                        final angle = (index.isEven ? -1 : 1) * 0.05 * ((index % 5) + 1);
                        return Transform.rotate(
                          angle: angle,
                          child: Padding(
                            padding: EdgeInsets.only(left: index == 0 ? 0 : 40, top: 10),
                            child: _FanCard(card: pile[index], color: color, isNext: index == 0),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FanCard extends StatelessWidget {
  final String card;
  final Color color;
  final bool isNext;

  const _FanCard({required this.card, required this.color, required this.isNext});

  @override
  Widget build(BuildContext context) {
    return PlayingCardFace(
      card: card,
      color: color,
      width: 62,
      height: 88,
      borderRadius: 10,
      borderColor: isNext ? color : color.withValues(alpha: 0.3),
      borderWidth: isNext ? 2.4 : 1.4,
    );
  }
}
