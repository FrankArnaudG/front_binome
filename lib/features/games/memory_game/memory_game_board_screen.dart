import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api_client.dart';
import '../../../core/app_router.dart' show AppRouter;
import '../../../core/server_clock.dart';
import '../../../l10n/locale_scope.dart';
import '../../../models/app_user.dart';
import '../../../models/game.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../../../theme/themed_background.dart';
import 'package:showcaseview/showcaseview.dart';

import '../nearby/nearby_comms.dart';
import '../widgets/always_on_top_layer.dart';
import '../widgets/coin_billing_ring.dart';
import '../widgets/game_comment_overlay.dart';
import '../widgets/game_guide_voice_demo.dart';
import '../widgets/memory_game_match_scoreboard.dart';
import '../widgets/game_resume_action.dart';
import '../widgets/game_wallet_depleted_notice.dart';
import '../widgets/game_wallet_guard.dart';
import '../widgets/nearby_voice_overlay.dart';
import '../widgets/voice_call_overlay.dart';
import '../game_guide_storage.dart';
import '../game_service.dart';
import '../../shop/wallet_balance_notifier.dart';
import 'memory_emoji_pool.dart';
import 'memory_game_transport.dart';
import 'memory_game_transport_remote.dart';
import 'memory_game_transport_local.dart';

/// Étapes du guide pas-à-pas réactif du plateau (voir demande utilisateur,
/// message détaillé : "parler de chaque élément à tour de rôle... en
/// commençant par indication qui dit qui doit jouer, la coloration du
/// nom, celui qui joue retourner la carte 1... retourner la carte 2...
/// garder les deux cartes ouvertes et un guide... l'essai a échoué et
/// c'est le tour de ton binôme... revenir à l'indication qui dit qui doit
/// jouer. aussi un guide sur le temps/les tokens consommés" + message
/// suivant : "un guide sur comment envoyer un message, activer le micro
/// et la caméra"). Voir _startGuideStep/_checkGuideProgress dans
/// _MemoryGameBoardScreenState pour la machine à états qui enchaîne ces
/// étapes.
enum _BoardGuideStep {
  turn,
  activeName,
  card1,
  card2,
  mismatch,
  turnPassed,
  coins,
  pause,
  chat,
  micJoin,
  micReady,
  cameraReady,
}

/// Plateau de "Jeu de Mémoire" — UNIQUE écran de jeu partagé par les 3
/// modes (voir MemoryGameTransport) : ne connaît que l'état abstrait
/// [MemoryGameBoardState], jamais les détails de synchronisation
/// sous-jacents.
///
/// [playerNames]/[playerAvatars] sont indexés par les identifiants qui
/// apparaissent dans `state.matched`/`state.currentTurnUserId` — de vrais
/// identifiants utilisateur pour à distance/pass-and-play, ou les rôles
/// internes 'host'/'guest' pour le présentiel connecté (voir
/// memory_game_transport_nearby.dart).
class MemoryGameBoardScreen extends StatefulWidget {
  final Game game;
  final AppUser user;
  final MemoryGameTransport transport;
  final Map<String, String> playerNames;
  final Map<String, String?> playerAvatars;
  // Non-null uniquement pour les modes qui savent relancer une partie
  // identique (à distance/pass-and-play, voir startMemoryGameAndPush) —
  // reçoit le contexte de CET écran (toujours valide au moment de l'appel,
  // contrairement à celui de l'écran de difficulté d'origine qui a pu être
  // retiré de la pile entre-temps). `null` masque le bouton "Rejouer".
  final Future<void> Function(BuildContext context)? onRematch;
  // Celui qui a lancé la partie (voir demande utilisateur) : seul lui voit "Rejouer" et le
  // décompte de Tokens (c'est son temps qui est facturé). L'autre joueur ne voit que "Quitter".
  final bool isLauncher;
  // "Quitter" depuis la feuille de score : par défaut referme le jeu ; l'invité·e d'une partie à
  // distance y ouvre le choix de la difficulté (voir game_invite_navigation.dart).
  final Future<void> Function(BuildContext context)? onQuit;
  // Canal de chat texte en présentiel connecté (voir NearbyComms) — non-null
  // uniquement pour ce mode (voir demande utilisateur : communiquer sans
  // serveur ni internet). `null` pour à distance/pass-and-play.
  final NearbyComms? nearbyComms;
  final String? nearbyMyName;
  final String? nearbyPartnerName;

  const MemoryGameBoardScreen({
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
  State<MemoryGameBoardScreen> createState() => _MemoryGameBoardScreenState();
}

class _MemoryGameBoardScreenState extends State<MemoryGameBoardScreen> {
  late StreamSubscription<MemoryGameBoardState> _subscription;
  late MemoryGameBoardState _state;
  List<int>? _displayMismatch;
  bool _resuming = false;
  Timer? _mismatchTimer;
  Timer? _clockTimer;
  bool _scoreboardShown = false;
  // Voir demande utilisateur : "le modèle qui affiche le score ne doit pas
  // cacher le micro" — showMemoryGameMatchScoreboard utilise `showBottomSheet`
  // (non modal), qui exige un Scaffold ANCÊTRE (`Scaffold.of`) ; `context`
  // (celui de CET État) est au-dessus du Scaffold que ce build() retourne,
  // jamais en dessous, et AUCUN autre Scaffold n'englobe cet écran pendant
  // une partie (barre de nav globale masquée, voir AppRouter.showGlobalNavBar
  // dans initState) — cette clé donne donc accès au bon Scaffold, LE SIEN.
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  // Instant où la partie s'est terminée (vu par CET appareil) : fige le chrono
  // et le compteur de tokens au lieu de les laisser tourner après la fin.
  // Réglage admin (minutes_per_coin/grace_period_seconds) pour l'anneau de
  // progression coté token (voir CoinBillingRing/demande utilisateur) —
  // chargé une seule fois, uniquement utile en mode à distance.
  Map<String, int>? _economyRate;
  // Guide pas-à-pas (voir demande utilisateur : "ajouter dans tous les
  // écrans qui suivent, surtout là où on joue" puis, en détail, "il te
  // manque beaucoup d'éléments de précision... parler de chaque élément à
  // tour de rôle" puis, en dernier lieu, "chacun peut tester sans dépendre
  // de l'autre... pendant ce temps, l'autre user ne voit rien") —
  // séquence ENTIÈREMENT SIMULÉE en LOCAL (voir _BoardGuideStep/
  // _startGuideStep/_onGuideCardTap ci-dessous) : les cartes "retournées"
  // pendant le guide (voir _guideFakeFlipped) et l'appel micro/caméra
  // "démarré" pendant le guide (voir _guideMicConnecting) sont de purs
  // artefacts visuels côté client — RIEN n'est envoyé à widget.transport
  // ni au binôme, précisément pour que chacun puisse lancer/rejouer le
  // guide à tout moment SANS dépendre d'une vraie action du binôme (voir
  // demande utilisateur, contrairement à une première version qui
  // attendait un vrai changement d'état réseau et restait donc bloquée
  // tant que le binôme ne jouait pas réellement). Vérifiée ICI,
  // indépendamment de comment on est arrivé sur cet écran (mode à
  // distance accepté via une notification push, présentiel connecté, un
  // seul téléphone...) — s'affiche la toute première fois qu'un plateau
  // de CE jeu s'ouvre pour ce compte, jamais plus ensuite automatiquement
  // (voir GameGuideStorage), mais rejouable à tout moment via le bouton
  // "?" (voir _startGuide).
  final _turnGuideKey = GlobalKey();
  final _activeNameGuideKey = GlobalKey();
  final _card1GuideKey = GlobalKey();
  final _card2GuideKey = GlobalKey();
  final _coinsGuideKey = GlobalKey();
  final _pauseGuideKey = GlobalKey();
  final _chatGuideKey = GlobalKey();
  final _micGuideKey = GlobalKey();
  final _cameraGuideKey = GlobalKey();
  static const _boardGuideKey = 'memory_game_board';
  _BoardGuideStep? _guideStep;
  // Les deux cartes que le guide va indiquer d'ouvrir — choisies pour ne
  // JAMAIS former une paire (voir demande utilisateur : "s'assurer que les
  // deux cartes que tu vas indiquer... ne se ressemblent jamais"), tirées
  // du plateau RÉEL au moment de démarrer l'étape carte 1 (voir
  // _pickGuideCardPair), jamais deux indices fixes qui pourraient tomber
  // sur une vraie paire selon le mélange.
  int? _guideCardA;
  int? _guideCardB;
  // Cartes visuellement "retournées" PAR LE GUIDE uniquement (voir doc
  // ci-dessus) — jamais ajoutées à _state.flipped, jamais transmises à
  // widget.transport.flip().
  final Set<int> _guideFakeFlipped = {};
  // Fausse séquence de connexion du micro pendant le guide (voir demande
  // utilisateur : "ça lance une recherche, ça passe en orange... notre
  // binôme doit cliquer sur le micro pour rejoindre") — jamais un vrai
  // appel VoiceCallService/NearbyComms.
  bool _guideMicConnecting = false;

  @override
  void initState() {
    super.initState();
    _state = widget.transport.currentState;
    _subscription = widget.transport.stateStream.listen(_onState);
    ShowcaseView.get().addOnCompleteCallback(_onGuideStepTapped);
    ShowcaseView.get().addOnDismissCallback(_onGuideDismissed);
    _maybeStartGuide();
    // Rejoue juste le rendu du chrono chaque seconde — aucun appel réseau,
    // même principe que TimelineScreen._tickTimer.
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppRouter.showGlobalNavBar.value = false;
    });
    if (_commentsBoxId != null) _loadEconomyRate();
  }

  /// Le guide "Comment jouer" n'existe que dans le mode "Présentiel, un seul téléphone" (voir demande
  /// utilisateur) : pas de lancement automatique ni de bouton "?" en partie à distance ou en présentiel
  /// connecté. Les guides qui y mènent renvoient vers ce mode (voir game_guide_notes.dart).
  bool get _guideAvailable => widget.transport is LocalMemoryGameTransport;

  Future<void> _maybeStartGuide() async {
    if (!_guideAvailable) return;
    final seen = await GameGuideStorage.instance.hasSeen(widget.user.id, _boardGuideKey);
    if (seen || !mounted) return;
    GameGuideStorage.instance.markSeen(widget.user.id, _boardGuideKey);
    _startGuide();
  }

  /// Point d'entrée UNIQUE pour démarrer le guide, automatique ou via le
  /// bouton "?" (voir AppBar) — met la partie en pause en premier (voir
  /// demande utilisateur : "il sera contraint de mettre en pause pour
  /// pouvoir lancer le guide pour ne pas le facturer") : le guide peut
  /// prendre du temps à parcourir, et on ne veut pas continuer à décompter
  /// le chrono/les tokens pendant ce temps. Le binôme voit alors juste la
  /// partie "en pause" habituelle (voir demande utilisateur : "l'autre
  /// user ne voit rien"), jamais les bulles du guide elles-mêmes, qui
  /// restent purement locales à cet écran.
  void _startGuide() {
    if (!_state.isPaused && !_state.finished) {
      widget.transport.pause();
    }
    _startGuideStep(_BoardGuideStep.turn);
  }

  /// Cherche deux indices du plateau RÉEL dont les emojis diffèrent (voir
  /// demande utilisateur : jamais une vraie paire) — `null` si le plateau
  /// n'a pas encore été reçu (invité en présentiel connecté) ou s'il ne
  /// reste plus deux cartes non trouvées à proposer (partie quasi finie).
  (int, int)? _pickGuideCardPair() {
    final board = _state.board;
    if (board.isEmpty) return null;
    // Colonnes de la grille actuelle (voir difficulty.columns dans build())
    // — nécessaire pour reconnaître un voisin direct (gauche/droite/haut/
    // bas), pas juste un indice consécutif dans le tableau.
    final columns = MemoryGameDifficulty.all
        .firstWhere((d) => d.cardCount == board.length, orElse: () => MemoryGameDifficulty.all.last)
        .columns;

    int? a;
    for (var i = 0; i < board.length; i++) {
      if (!_state.matchedIndices.contains(i)) {
        a = i;
        break;
      }
    }
    if (a == null) return null;

    // Deuxième carte : jamais une vraie paire (voir board[b] != board[a])
    // ET jamais une voisine directe de la première (voir demande
    // utilisateur : "ne pas prendre directement la carte d'à côté, risque
    // que le user croie qu'il faut forcément choisir la carte d'à côté")
    // — on préfère une carte visuellement éloignée ; à défaut (grille
    // minuscule où tout est voisin), n'importe quelle carte différente
    // fait l'affaire plutôt que de bloquer le guide.
    int? far;
    int? any;
    for (var b = 0; b < board.length; b++) {
      if (b == a || _state.matchedIndices.contains(b)) continue;
      if (board[b] == board[a]) continue;
      any ??= b;
      final sameRowNeighbor = (b - a).abs() == 1 && (a ~/ columns) == (b ~/ columns);
      final sameColumnNeighbor = (b - a).abs() == columns;
      if (!sameRowNeighbor && !sameColumnNeighbor) {
        far = b;
        break;
      }
    }
    final b = far ?? any;
    if (b == null) return null;
    return (a, b);
  }

  /// Démarre UNE étape du guide (voir doc de classe de _BoardGuideStep) —
  /// TOUTES les étapes avancent désormais vers la suivante par un TAP de
  /// l'utilisateur (voir _onGuideStepTapped/_onGuideCardTap), jamais en
  /// attendant un vrai changement d'état réseau (voir doc de classe :
  /// "chacun peut tester sans dépendre de l'autre").
  void _startGuideStep(_BoardGuideStep step) {
    if (!mounted) return;
    if (step == _BoardGuideStep.card1) {
      final pair = _pickGuideCardPair();
      if (pair == null) {
        // Rien à démontrer (plateau pas encore reçu ou presque terminé) —
        // on saute directement à la suite plutôt que de bloquer le guide.
        _startGuideStep(_BoardGuideStep.coins);
        return;
      }
      _guideCardA = pair.$1;
      _guideCardB = pair.$2;
    }
    if (step == _BoardGuideStep.turnPassed) {
      // Les deux cartes "retournées" par le guide se referment (voir
      // demande utilisateur : les cartes restent ouvertes UNIQUEMENT
      // pendant l'étape "mismatch" qui explique le raté) — jamais un vrai
      // état de partie modifié, donc rien côté serveur/binôme à annuler.
      _guideFakeFlipped.clear();
    }
    if (step == _BoardGuideStep.micReady) {
      _guideMicConnecting = true;
    }
    setState(() => _guideStep = step);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _guideKeyFor(step);
      // Le bouton caméra (voir VoiceCallOverlay) n'existe dans l'arbre
      // qu'une fois l'appel connecté — s'il n'est pas encore monté, mieux
      // vaut terminer proprement le guide que de rester bloqué à
      // attendre une cible qui n'apparaîtra peut-être jamais.
      if (!ShowcaseView.get().isTargetRendered(key)) {
        setState(() => _guideStep = null);
        return;
      }
      ShowcaseView.get().startShowCase([key]);
    });
  }

  GlobalKey _guideKeyFor(_BoardGuideStep step) {
    switch (step) {
      case _BoardGuideStep.turn:
      case _BoardGuideStep.turnPassed:
        return _turnGuideKey;
      case _BoardGuideStep.activeName:
        return _activeNameGuideKey;
      case _BoardGuideStep.card1:
        return _card1GuideKey;
      case _BoardGuideStep.card2:
      case _BoardGuideStep.mismatch:
        return _card2GuideKey;
      case _BoardGuideStep.coins:
        return _coinsGuideKey;
      case _BoardGuideStep.pause:
        return _pauseGuideKey;
      case _BoardGuideStep.chat:
        return _chatGuideKey;
      case _BoardGuideStep.micJoin:
      case _BoardGuideStep.micReady:
        return _micGuideKey;
      case _BoardGuideStep.cameraReady:
        return _cameraGuideKey;
    }
  }

  /// Appelé quand l'utilisateur tape lui-même la bulle active (voir
  /// ShowcaseView.get().addOnCompleteCallback dans initState) — fait
  /// avancer les étapes purement informatives ; pour card1/card2, rien ne
  /// se passe ici (le TARGET a ses gestes par défaut désactivés, voir
  /// disableDefaultTargetGestures dans build()) — seul un vrai tap sur la
  /// carte simulée (voir _onGuideCardTap) fait avancer la suite. L'étape
  /// "mismatch", elle, avance normalement au tap comme les étapes
  /// informatives (les deux cartes ont déjà été "retournées").
  void _onGuideStepTapped(int? index, GlobalKey key) {
    switch (_guideStep) {
      case _BoardGuideStep.turn:
        _startGuideStep(_BoardGuideStep.activeName);
        break;
      case _BoardGuideStep.activeName:
        _startGuideStep(_BoardGuideStep.card1);
        break;
      case _BoardGuideStep.mismatch:
        _startGuideStep(_BoardGuideStep.turnPassed);
        break;
      case _BoardGuideStep.turnPassed:
        _startGuideStep(_BoardGuideStep.coins);
        break;
      case _BoardGuideStep.coins:
        _startGuideStep(_BoardGuideStep.pause);
        break;
      case _BoardGuideStep.pause:
        _startGuideStep(_BoardGuideStep.chat);
        break;
      case _BoardGuideStep.chat:
        _startGuideStep(_BoardGuideStep.micJoin);
        break;
      case _BoardGuideStep.micJoin:
        _startGuideStep(_BoardGuideStep.micReady);
        break;
      case _BoardGuideStep.micReady:
        _startGuideStep(_BoardGuideStep.cameraReady);
        break;
      case _BoardGuideStep.cameraReady:
        setState(() {
          _guideStep = null;
          _guideMicConnecting = false;
        });
        break;
      case _BoardGuideStep.card1:
      case _BoardGuideStep.card2:
      case null:
        break;
    }
  }

  /// Tap sur une carte du plateau PENDANT le guide (voir _guideCardA/
  /// _guideCardB) — retourne la carte visuellement en LOCAL uniquement
  /// (voir _guideFakeFlipped), sans jamais appeler widget.transport.flip()
  /// ni dépendre de _state.isMyTurn (voir demande utilisateur : "chacun
  /// peut tester sans dépendre de l'autre"). En dehors des étapes
  /// card1/card2, ce tap ne fait rien (la carte n'est alors pas une carte
  /// du guide, voir index == _guideCardA/_guideCardB dans build()).
  void _onGuideCardTap(int index) {
    if (_guideStep == _BoardGuideStep.card1 && index == _guideCardA) {
      setState(() => _guideFakeFlipped.add(index));
      _startGuideStep(_BoardGuideStep.card2);
    } else if (_guideStep == _BoardGuideStep.card2 && index == _guideCardB) {
      setState(() => _guideFakeFlipped.add(index));
      _startGuideStep(_BoardGuideStep.mismatch);
    }
  }

  /// Le tour entier du guide a été fermé avant la fin (croix, tap hors de
  /// la bulle...) — nettoie les artefacts visuels locaux (voir doc de
  /// classe) pour ne pas laisser une carte "retournée" ou un micro
  /// "orange" qui resterait affiché sans bulle pour l'expliquer.
  void _onGuideDismissed(GlobalKey? key) {
    if (!mounted) return;
    setState(() {
      _guideStep = null;
      _guideFakeFlipped.clear();
      _guideMicConnecting = false;
    });
  }

  /// Faux bouton micro/caméra affiché UNIQUEMENT pendant les étapes
  /// micJoin/micReady/cameraReady du guide (voir doc de classe de
  /// _BoardGuideStep) — voir GameGuideVoiceDemo (widget partagé par tous
  /// les jeux, voir demande utilisateur : "prends le même soin pour les
  /// autres jeux").
  Widget _buildGuideVoiceDemo(ThemePalette theme) {
    final phase = switch (_guideStep) {
      _BoardGuideStep.micJoin => GameGuideVoicePhase.micJoin,
      _BoardGuideStep.micReady => GameGuideVoicePhase.micReady,
      _BoardGuideStep.cameraReady => GameGuideVoicePhase.cameraReady,
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

  /// Temps facturable écoulé, en secondes — voir demande utilisateur :
  /// "même si le user trafique l'heure de son téléphone, le serveur
  /// connaît la vérité" (voir ServerClock, calibré sur l'en-tête HTTP
  /// Date du serveur, jamais l'horloge brute de l'appareil). `null` tant
  /// que le réglage admin n'est pas encore chargé. Base commune à
  /// [_coinProgress] et [_coinsConsumed] pour qu'ils restent PARFAITEMENT
  /// synchronisés (voir demande utilisateur : le compteur doit passer au
  /// nombre entier suivant exactement quand l'anneau se complète).
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

  /// Nombre de tokens consommés depuis le début de CETTE partie —
  /// fluide comme l'anneau (même calcul, voir _elapsedBillableSeconds),
  /// plutôt que calé sur le vrai débit serveur qui n'arrive qu'une fois
  /// par minute (voir demande utilisateur : "il s'incrémente pas au fur
  /// et à mesure... il faut un truc dynamique"). `null` tant que le
  /// réglage admin n'est pas encore chargé.
  double? _coinsConsumed() {
    final elapsed = _elapsedBillableSeconds();
    final cycleSeconds = (_economyRate?['minutes_per_coin'] ?? 8) * 60;
    if (elapsed == null || cycleSeconds <= 0) return 0;
    return elapsed / cycleSeconds;
  }

  void _onState(MemoryGameBoardState state) {
    if (!mounted) return;
    setState(() {
      _state = state;
      if (state.mismatch != null) {
        _displayMismatch = state.mismatch;
        _mismatchTimer?.cancel();
        _mismatchTimer = Timer(const Duration(milliseconds: 900), () {
          if (mounted) setState(() => _displayMismatch = null);
        });
      }
    });

    if (state.finished && !_scoreboardShown) {
      _scoreboardShown = true;
      // Voir demande utilisateur : "ça doit être instantané" — dès que la
      // partie est vraiment terminée (quelle qu'en soit la cause), on
      // rafraîchit le solde tout de suite plutôt que d'attendre que
      // l'utilisateur retourne au tableau de bord ; le score/pop-up qui
      // suit laisse largement le temps à cet appel réseau d'aboutir
      // avant que l'écran ne se ferme.
      if (_commentsBoxId != null) unawaited(WalletBalanceNotifier.instance.refresh());
      // Scoreboard systématique, même après un abandon (voir demande
      // utilisateur : "si on abandonne, on a le score en bas pour tous les
      // jeux, il faut proposer de quitter et pour rejouer c'est pour celui
      // qui a lancé le jeu") — _showScoreboard gère déjà "Quitter" pour
      // tous et "Rejouer" réservé à widget.isLauncher.
      WidgetsBinding.instance.addPostFrameCallback((_) => _showScoreboard());
    }
  }

  /// Même dialogue de confirmation pour les deux façons de quitter une
  /// partie en cours : le bouton drapeau explicite ET la flèche retour
  /// (voir PopScope dans build()) — sans cette seconde interception, la
  /// flèche retour laissait la partie "en l'air" sans jamais prévenir le
  /// binôme ni le serveur (voir demande utilisateur : après être revenu en
  /// arrière puis avoir relancé une invitation, le binôme ne recevait
  /// plus rien — les deux appareils n'étaient jamais repartis d'un état
  /// propre).
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

  /// Voir demande utilisateur : "j'abandonne, je clique mais rien ne se
  /// passe" — `widget.transport.abandon()` n'avait AUCUNE gestion d'erreur
  /// (un raté réseau/serveur échouait en silence total, sans aucun retour
  /// visible) — désormais utilisé aux deux points d'appel (drapeau ET
  /// retour arrière) pour au moins prévenir au lieu de ne rien montrer.
  Future<void> _abandonWithFeedback() async {
    try {
      await widget.transport.abandon();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'abandonner la partie, réessaie.")),
      );
    }
  }

  Future<void> _showScoreboard() async {
    if (!mounted) return;
    final rematch = await showMemoryGameMatchScoreboard(
      _scaffoldKey,
      state: _state,
      playerNames: widget.playerNames,
      playerAvatars: widget.playerAvatars,
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
      if (transport is RemoteMemoryGameTransport) {
        unawaited(GameService.instance.closeGameSession('memory_game', transport.sessionId));
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
    if (transport is RemoteMemoryGameTransport) {
      unawaited(GameService.instance.pingGameSessionMic('memory_game', transport.sessionId));
    }
  }

  Future<void> _onTapCard(int index) async {
    if (_state.finished) return;
    if (_state.isPaused) return;
    if (_state.matchedIndices.contains(index)) return;
    if (_state.flipped.contains(index)) return;
    if (_displayMismatch != null) return; // laisse le temps de voir la paire ratée
    if (widget.transport.requiresTurnToFlip && !_state.isMyTurn) return;

    await widget.transport.flip(index);
  }

  // Réactions en direct (voir GameCommentOverlay) : uniquement en mode "à
  // distance", seul mode où un canal de Box existe déjà côté client — le
  // présentiel connecté (Nearby) reste du pur P2P sans notion de Box.
  String? get _commentsBoxId {
    final transport = widget.transport;
    return transport is RemoteMemoryGameTransport ? transport.boxId : null;
  }

  String get _sessionId {
    final transport = widget.transport;
    return transport is RemoteMemoryGameTransport ? transport.sessionId : '';
  }

  /// Bouton "Terminer la partie" du popup de solde épuisé (voir
  /// GameWalletGuard) — même geste qu'un abandon volontaire.
  String get _partnerUserId =>
      widget.playerNames.keys.firstWhere((id) => id != widget.user.id, orElse: () => widget.user.id);

  int _pairsFoundBy(String userId) => _state.matched.where((pair) => pair.userId == userId).length;

  String _elapsed() {
    final started = _state.startedAt;
    if (started == null) return '0:00';
    // Figé au moment où la pause a commencé (voir MemoryGameBoardState.
    // pausedAt) — sinon le chrono continuerait de tourner à l'écran pendant
    // la pause, alors que startedAt n'est décalé qu'à la reprise.
    final now = _state.pausedAt ?? ServerClock.instance.now();
    // Le chrono attend la même période de grâce que l'anneau de token
    // (voir CoinBillingRing/demande utilisateur : "les 10 secondes
    // doivent représenter le temps que doit patienter le chrono avant de
    // se mettre en marche officiellement") — reste à 0:00 tant que la
    // grâce n'est pas écoulée, nul en dehors du mode à distance
    // (_economyRate jamais chargé ailleurs).
    final graceSeconds = _economyRate?['grace_period_seconds'] ?? 0;
    // max(0, ...) : si l'horloge du téléphone est en retard sur celle du
    // serveur (courant sur un appareil de test dont la date n'est pas
    // synchronisée), la différence peut devenir négative — un chrono
    // négatif n'a aucun sens à l'écran (voir demande utilisateur, capture
    // "-27:59").
    final seconds = (now.difference(started).inSeconds - graceSeconds).clamp(0, 1 << 31);
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _subscription.cancel();
    ShowcaseView.get().removeOnCompleteCallback(_onGuideStepTapped);
    ShowcaseView.get().removeOnDismissCallback(_onGuideDismissed);
    _mismatchTimer?.cancel();
    _clockTimer?.cancel();
    widget.transport.dispose();
    widget.nearbyComms?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Différé au frame suivant — assigné en direct, cette mise à jour
    // pouvait planter silencieusement pendant le démontage (arbre de
    // widgets verrouillé, voir demande utilisateur : après avoir quitté une
    // partie, plus aucune invitation ne s'affichait jusqu'à relancer l'app
    // entière — la coquille globale entière restait coincée masquée).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppRouter.showGlobalNavBar.value = true;
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final board = _state.board;

    if (board.isEmpty) {
      // Invité en présentiel connecté, en attente du plateau envoyé par
      // l'hôte (voir NearbyMemoryGameTransport.guest).
      return Scaffold(
        backgroundColor: theme.background,
        body: ThemedBackground(
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: theme.primary),
                  const SizedBox(height: 16),
                  Text(
                    LocaleScope.t(context, 'memory_board_waiting'),
                    style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final difficulty = MemoryGameDifficulty.all.firstWhere((d) => d.cardCount == board.length);
    final turnName = _state.currentTurnUserId != null ? widget.playerNames[_state.currentTurnUserId] : null;

    final commentsBoxId = _commentsBoxId;
    return PopScope(
      // Bloqué tant que la partie n'est pas finie — voir _confirmAbandon,
      // rejoué manuellement ci-dessous après confirmation (voir demande
      // utilisateur).
      canPop: _state.finished,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Ne referme plus l'écran soi-même (voir demande utilisateur :
        // scoreboard systématique après un abandon, même geste que le
        // bouton drapeau ci-dessous) — _onState détecte `state.finished`
        // et affiche le tableau de score (avec "Rejouer" pour le lanceur,
        // "Quitter" pour tous), qui referme l'écran lui-même.
        if (await _confirmAbandon()) {
          await _abandonWithFeedback();
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
      key: _scaffoldKey,
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
            // Le guide met la partie en pause avant de démarrer (voir
            // _startGuide) — la bulle doit donc pouvoir pointer sur les
            // DEUX boutons possibles (pause OU reprendre), selon lequel
            // est visible au moment où l'étape "pause" du guide est
            // atteinte, plutôt que de ne connaître que le bouton "pause"
            // qui, en pratique, n'existe plus pendant le guide.
            Showcase(
              key: _pauseGuideKey,
              title: _state.isPaused ? 'Reprends la partie' : 'Mets en pause',
              description: _state.isPaused
                  ? "Ce bouton reprend la partie quand tu es prêt·e — tant qu'elle est en pause, le chrono et les Tokens ne bougent pas."
                  : "Tu peux mettre la partie en pause à tout moment si tu dois t'absenter.",
              targetShapeBorder: const CircleBorder(),
              child: _state.isPaused
                  ? // En pause : bouton "Reprendre" UNIQUEMENT pour qui l'a
                    // posée (voir demande utilisateur) — désactivé (grisé,
                    // pas caché) côté binôme, pour que ça reste visible que
                    // le jeu est en pause sans laisser croire qu'iel peut
                    // la lever.
                    IconButton(
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
          // Masqué une fois la partie terminée — sinon un retap n'a plus
          // aucun effet visible (la partie est déjà `finished`) et donne
          // l'impression que le bouton "ne fonctionne pas" (même bug
          // trouvé et corrigé sur Morpion à Deux, voir demande utilisateur).
          if (!_state.finished)
            IconButton(
              icon: const Icon(Icons.flag_outlined),
              tooltip: LocaleScope.t(context, 'memory_board_abandon_tooltip'),
              onPressed: () async {
                if (await _confirmAbandon()) {
                  await _abandonWithFeedback();
                  // Ce bouton ne quitte pas l'écran lui-même (voir
                  // _onState, qui affiche le score une fois `finished`
                  // reçu) — le rafraîchissement s'y fait déjà (voir
                  // plus bas), inutile de le refaire ici.
                }
              },
            ),
          // Une fois la partie finie, le seul moyen de rejouer était la
          // fenêtre de score qui vient de se fermer — bouton permanent une
          // fois qu'elle a disparu (même correctif que Morpion à Deux, voir
          // demande utilisateur).
          if (_state.finished && widget.isLauncher && widget.onRematch != null)
            IconButton(
              icon: const Icon(Icons.replay_rounded),
              tooltip: LocaleScope.t(context, 'memory_score_rematch'),
              onPressed: () => widget.onRematch!(context),
            ),
          // Bouton "?" pour rejouer le guide à tout moment (voir demande
          // utilisateur : "si je clique sur le point d'interrogation le
          // guide se relance pour cette page mais dans la page suivante...
          // rien") — même principe que MemoryGameModeScreen._startGuide,
          // indépendant du flag "déjà vu" (déjà marqué dès le premier
          // affichage automatique, voir _maybeStartGuide).
          if (!_state.finished && _guideAvailable)
            IconButton(
              icon: const Icon(Icons.help_outline_rounded),
              tooltip: 'Revoir le guide',
              onPressed: _startGuide,
            ),
        ],
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                // Entête resserrée (voir demande utilisateur : "remonter
                // l'entête et réduire un peu l'espace, mais toujours bien
                // lisible") — plus de hauteur libre pour la grille elle-même,
                // sans rien couper à la taille du texte.
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Showcase(
                        key: _turnGuideKey,
                        title: _guideStep == _BoardGuideStep.turnPassed ? 'Le tour passe' : 'À qui de jouer ?',
                        description: _guideStep == _BoardGuideStep.turnPassed
                            ? "L'essai a échoué : dans une vraie partie, ce texte afficherait maintenant le nom de ton binôme, à qui la main serait passée. (Si les deux cartes avaient été identiques, tu aurais continué à jouer.)"
                            : 'Ce texte indique à qui c\'est le tour de retourner une carte.',
                        targetBorderRadius: BorderRadius.circular(8),
                        child: Text(
                          // Une fois la partie finie, "Au tour de..." n'a
                          // plus de sens (même correctif que Morpion à Deux,
                          // voir demande utilisateur).
                          _state.finished
                              ? LocaleScope.t(context, 'game_board_finished_label')
                              : (widget.transport.requiresTurnToFlip
                                  ? (_state.isMyTurn
                                      ? LocaleScope.t(context, 'memory_board_your_turn')
                                      : LocaleScope.t(context, 'memory_board_partner_turn', {
                                          'name': turnName ?? LocaleScope.t(context, 'memory_board_partner_fallback'),
                                        }))
                                  : LocaleScope.t(context, 'memory_board_partner_turn', {'name': turnName ?? '...'})),
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: theme.primary),
                          overflow: TextOverflow.ellipsis,
                        ),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Row(
                  children: [
                    for (final userId in widget.playerNames.keys) ...[
                      if (userId != widget.playerNames.keys.first) const SizedBox(width: 10),
                      Expanded(
                        child: Builder(builder: (context) {
                          final chip = _PlayerStatChip(
                            theme: theme,
                            name: widget.playerNames[userId] ?? '',
                            avatar: widget.playerAvatars[userId],
                            pairsFound: _pairsFoundBy(userId),
                            moves: _state.movesByUser[userId] ?? 0,
                            active: _state.currentTurnUserId == userId,
                          );
                          // Bulle sur le nom mis en évidence uniquement
                          // (voir demande utilisateur : "la coloration du
                          // nom") — inerte tant que _activeNameGuideKey
                          // n'est pas inclus dans un startShowCase actif,
                          // même principe que la première carte ci-dessous.
                          if (_state.currentTurnUserId != userId) return chip;
                          return Showcase(
                            key: _activeNameGuideKey,
                            title: 'Le nom en surbrillance',
                            description: 'Le nom coloré indique le joueur dont c\'est le tour en ce moment.',
                            targetBorderRadius: BorderRadius.circular(14),
                            child: chip,
                          );
                        }),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Ratio calculé pour que la grille remplisse
                      // exactement l'espace disponible (ni débordement, ni
                      // espace mort), quel que soit le palier de difficulté
                      // (3×4 à 8×14) ou la taille d'écran — au lieu d'un
                      // ratio fixe qui ne convenait qu'à une seule grille.
                      // clamp() large (pas 0.55–1.3) : cette fourchette
                      // resserrait le ratio dès qu'une grille avait peu de
                      // colonnes pour beaucoup de lignes (ex. 16 paires,
                      // 4×8) — le ratio RESSERRÉ (pas le naturel) servait
                      // alors à calculer la hauteur de chaque carte, et
                      // gonflait la grille entière au-delà de l'espace
                      // disponible (voir demande utilisateur : "le 16
                      // paires déborde"). Le calcul ci-dessus garantit déjà
                      // un ajustement exact par construction ; ce clamp()
                      // élargi ne sert plus que de filet de sécurité contre
                      // un cas dégénéré (fenêtre quasi nulle), jamais à
                      // resserrer un ratio par ailleurs valide.
                      const spacing = 8.0;
                      final cardWidth = (constraints.maxWidth - (difficulty.columns - 1) * spacing) / difficulty.columns;
                      final cardHeight = (constraints.maxHeight - (difficulty.rows - 1) * spacing) / difficulty.rows;
                      final aspectRatio = (cardWidth / cardHeight).clamp(0.35, 2.2);

                      return GridView.builder(
                        // Le ratio ci-dessus fait déjà tenir la grille dans
                        // l'espace disponible dans le cas normal — le
                        // scroll reste actif uniquement comme filet de
                        // sécurité si le clamp() a dû resserrer le ratio
                        // (fenêtre quasi nulle uniquement, voir plus haut).
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: difficulty.columns,
                          mainAxisSpacing: spacing,
                          crossAxisSpacing: spacing,
                          childAspectRatio: aspectRatio,
                        ),
                        itemCount: board.length,
                        itemBuilder: (context, index) {
                          final isMatched = _state.matchedIndices.contains(index);
                          final isFlipped = _state.flipped.contains(index) ||
                              (_displayMismatch?.contains(index) ?? false) ||
                              _guideFakeFlipped.contains(index);
                          // Pendant les étapes card1/card2, le tap est
                          // détourné vers _onGuideCardTap (voir doc de
                          // classe : simulation 100% locale, jamais
                          // widget.transport.flip()) — en dehors de ces
                          // étapes, ces mêmes cartes redeviennent de
                          // vraies cartes jouables normalement.
                          final isGuideCard = index == _guideCardA || index == _guideCardB;
                          // Tant que le guide tourne (partie déjà mise en
                          // pause, voir _startGuide), ces deux cartes ne
                          // doivent JAMAIS déclencher un vrai flip — que ce
                          // soit à leur propre étape (voir _onGuideCardTap)
                          // ou à une étape suivante (mismatch, coins...) où
                          // elles restent affichées sans être "actives".
                          final card = _MemoryCardTile(
                            emoji: board[index],
                            faceUp: isMatched || isFlipped,
                            dimmed: isMatched,
                            onTap: (isGuideCard && _guideStep != null) ? () => _onGuideCardTap(index) : () => _onTapCard(index),
                          );
                          // Bulles sur les DEUX cartes choisies par le
                          // guide (voir _pickGuideCardPair) — inertes tant
                          // que leur clé n'est pas incluse dans un
                          // startShowCase actif, comme partout ailleurs
                          // dans ce guide. `disableDefaultTargetGestures`
                          // laisse notre propre onTap (voir isGuideCardActive
                          // ci-dessus) gérer le tap au lieu que le paquet
                          // se contente de fermer la bulle — le guide
                          // n'avance que lorsque la carte est VRAIMENT
                          // "retournée" en local (voir _onGuideCardTap).
                          if (!isGuideCard) return card;
                          if (index == _guideCardA) {
                            return Showcase(
                              key: _card1GuideKey,
                              title: 'Retourne une première carte',
                              description: 'Tape ici pour retourner cette carte.',
                              targetBorderRadius: BorderRadius.circular(12),
                              disableDefaultTargetGestures: true,
                              child: card,
                            );
                          }
                          return Showcase(
                            key: _card2GuideKey,
                            title: _guideStep == _BoardGuideStep.mismatch ? 'Ça ne correspond pas' : 'Retourne une deuxième carte',
                            description: _guideStep == _BoardGuideStep.mismatch
                                ? "Ces deux cartes ne se ressemblent pas : l'essai a échoué."
                                : 'Retourne cette autre carte pour essayer de trouver sa paire.',
                            targetBorderRadius: BorderRadius.circular(12),
                            disableDefaultTargetGestures: true,
                            child: card,
                          );
                        },
                      );
                    },
                  ),
                    ),
                    if (_state.isPaused && _guideStep == null)
                      // Empêche tout tap sur la grille en dessous tant que
                      // la pause est active (en plus du garde-fou dans
                      // _onTapCard) — Positioned.fill capte tous les gestes
                      // de cette zone. Masqué tant que le guide tourne
                      // (voir demande utilisateur : "ici y'a pas de carte
                      // à retourner" — le guide met la partie en pause
                      // pour ne pas facturer, voir _startGuide, mais a
                      // justement besoin que la grille reste visible et
                      // tapable pour ses étapes card1/card2, voir
                      // _onGuideCardTap qui contourne déjà le garde-fou
                      // `_state.isPaused` de _onTapCard).
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.background,
                            borderRadius: BorderRadius.circular(20),
                          ),
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
                  partnerUserId: _partnerUserId,
                  enabled: true,
                  paused: _state.isPaused,
                  // Coupe l'appel en cours dès la mise en pause (voir demande
                  // utilisateur : "couper tout les procecusse lour comme
                  // l'audio, la video" à la pause), même mécanisme que pour
                  // un solde épuisé.
                  forceEnded: _state.isPaused,
                  onMicActiveChanged: _onMicActiveChanged,
                )
              : widget.nearbyComms != null
                  ? NearbyVoiceOverlay(comms: widget.nearbyComms, enabled: true, paused: _state.isPaused)
                  : const SizedBox.shrink(),
        ),
        // Démo micro/caméra du guide (voir doc de classe de
        // _BoardGuideStep) — volontairement SÉPARÉE des vrais boutons
        // ci-dessus (voir VoiceCallOverlay/NearbyVoiceOverlay) : le
        // bouton caméra réel n'existe même pas tant qu'un appel n'est pas
        // connecté (voir VoiceCallOverlay), et la partie est de toute
        // façon en pause pendant tout le guide (voir _startGuide), donc
        // un vrai appel ne pourrait jamais réellement se connecter.
        // Rendue APRÈS les vrais boutons dans ce Stack : elle les
        // recouvre visuellement et capte le tap à la même position
        // pendant ces étapes, aucun risque de toucher le vrai bouton en
        // dessous par erreur.
        _buildGuideVoiceDemo(theme),
        GameWalletGuard(
          boxId: commentsBoxId,
          sessionType: 'memory_game',
          sessionId: _sessionId,
        ),
      ],
      ),
    );
  }
}

/// Score + coups d'UN joueur, affichés en direct pendant la partie (voir
/// demande utilisateur : le compteur de coups était partagé/global, il
/// doit être séparé par joueur, comme le score) — [active] met en
/// évidence le joueur dont c'est le tour.
class _PlayerStatChip extends StatelessWidget {
  final ThemePalette theme;
  final String name;
  final String? avatar;
  final int pairsFound;
  final int moves;
  final bool active;

  const _PlayerStatChip({
    required this.theme,
    required this.name,
    required this.avatar,
    required this.pairsFound,
    required this.moves,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? theme.primary.withValues(alpha: 0.12) : theme.surface.withValues(alpha: theme.isDark ? 0.5 : 0.75),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: active ? theme.primary.withValues(alpha: 0.5) : theme.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: theme.primary.withValues(alpha: 0.16),
            backgroundImage: (avatar != null && avatar!.isNotEmpty) ? NetworkImage(avatar!) : null,
            child: (avatar == null || avatar!.isEmpty)
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.primary, fontSize: 12),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: theme.textOnBackground),
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Icon(Icons.favorite_rounded, size: 12, color: theme.primary),
                    const SizedBox(width: 3),
                    Text('$pairsFound', style: GoogleFonts.nunito(fontSize: 11, color: theme.textOnBackgroundMuted)),
                    const SizedBox(width: 8),
                    Icon(Icons.touch_app_outlined, size: 12, color: theme.textOnBackgroundMuted),
                    const SizedBox(width: 3),
                    Text('$moves', style: GoogleFonts.nunito(fontSize: 11, color: theme.textOnBackgroundMuted)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryCardTile extends StatelessWidget {
  final String emoji;
  final bool faceUp;
  final bool dimmed;
  final VoidCallback onTap;

  const _MemoryCardTile({required this.emoji, required this.faceUp, required this.dimmed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);

    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: faceUp ? 1 : 0),
        duration: const Duration(milliseconds: 260),
        builder: (context, t, child) {
          final showFront = t > 0.5;
          final angle = t * 3.14159265;
          return Opacity(
            opacity: dimmed ? 0.45 : 1,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..setEntry(3, 2, 0.001)..rotateY(angle),
              child: showFront
                  ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(3.14159265),
                      child: _CardFace(
                        color: theme.surface,
                        border: theme.primary.withValues(alpha: 0.4),
                        child: Text(emoji, style: const TextStyle(fontSize: 26)),
                      ),
                    )
                  : _CardFace(
                      color: theme.primary.withValues(alpha: 0.85),
                      border: Colors.transparent,
                      child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 20),
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _CardFace extends StatelessWidget {
  final Color color;
  final Color border;
  final Widget child;

  const _CardFace({required this.color, required this.border, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Center(child: child),
    );
  }
}
