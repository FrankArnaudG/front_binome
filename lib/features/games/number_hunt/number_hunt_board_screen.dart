import 'dart:async';

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
import '../../box/box_scope.dart';
import '../game_guide_storage.dart';
import '../game_service.dart';
import '../nearby/nearby_comms.dart';
import '../widgets/always_on_top_layer.dart';
import '../widgets/coin_billing_ring.dart';
import '../widgets/game_comment_overlay.dart';
import '../widgets/game_guide_voice_demo.dart';
import '../widgets/number_hunt_match_scoreboard.dart';
import '../widgets/game_resume_action.dart';
import '../widgets/game_wallet_depleted_notice.dart';
import '../widgets/game_wallet_guard.dart';
import '../widgets/nearby_voice_overlay.dart';
import '../widgets/voice_call_overlay.dart';
import '../../shop/subscription_status_notifier.dart';
import '../../shop/wallet_balance_notifier.dart';
import 'number_hunt_transport.dart';
import 'number_hunt_transport_remote.dart';
import 'number_hunt_transport_local.dart';

/// Étapes du guide pas-à-pas du plateau (voir doc de _BoardGuideStep dans
/// memory_game_board_screen.dart pour le principe général) — pas de tour
/// par tour ici (voir doc de classe de NumberHuntBoardScreen), donc pas
/// d'étape "à qui de jouer" ; [tapNumber] désigne la vraie case du
/// nombre-cible pour un vrai tap (voir demande utilisateur : "guider le
/// user vers quelque action pour qu'il comprenne le mécanisme"), jamais
/// une bulle générique sur toute la grille.
enum _NumberHuntGuideStep { target, tapNumber, numberFound, coins, pause, chat, micJoin, micReady, cameraReady }

const _kRedColor = Color(0xFFE5484D);
const _kBlueColor = Color(0xFF2F6FED);

/// Plateau de "Chasse aux Chiffres" — UNIQUE écran de jeu partagé par les
/// 3 modes (voir NumberHuntTransport), copie structurelle conforme des 3
/// autres jeux (pause/reprise, chrono), SAUF qu'il n'y a pas de tour par
/// tour : n'importe lequel des deux peut taper à tout moment sur le
/// nombre-cible annoncé en haut de l'écran.
class NumberHuntBoardScreen extends StatefulWidget {
  final Game game;
  final AppUser user;
  final NumberHuntTransport transport;
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

  const NumberHuntBoardScreen({
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

  /// Pop-up "qui a trouvé ?" pour le mode pass-and-play — voir
  /// LocalNumberHuntTransport.askWhoFound. Appelé AVANT que l'écran de
  /// plateau n'existe forcément encore (construit dès startNumberHuntAndPush,
  /// voir number_hunt_mode_screen.dart), d'où l'usage du Navigator global
  /// plutôt que le contexte de CETTE instance.
  static Future<String> askWhoFoundFor(String creatorId, String partnerId) async {
    final ctx = AppRouter.navigatorKey.currentContext;
    if (ctx == null) return creatorId;

    final box = BoxScope.of(ctx).currentBox;
    final creatorName = box?.creatorId == creatorId ? (box?.creator?.prenom ?? 'Joueur 1') : (box?.partner?.prenom ?? 'Joueur 1');
    final partnerName = box?.creatorId == partnerId ? (box?.creator?.prenom ?? 'Joueur 2') : (box?.partner?.prenom ?? 'Joueur 2');
    final theme = ThemeScope.paletteOf(ctx);

    final result = await showDialog<String>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: Text(LocaleScope.t(dialogCtx, 'number_hunt_who_found_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _WhoFoundButton(color: _kRedColor, name: creatorName, onTap: () => Navigator.of(dialogCtx).pop(creatorId)),
            const SizedBox(height: 10),
            _WhoFoundButton(color: _kBlueColor, name: partnerName, onTap: () => Navigator.of(dialogCtx).pop(partnerId)),
          ],
        ),
        backgroundColor: theme.background,
      ),
    );
    return result ?? creatorId;
  }

  @override
  State<NumberHuntBoardScreen> createState() => _NumberHuntBoardScreenState();
}

class _NumberHuntBoardScreenState extends State<NumberHuntBoardScreen> {
  bool _resuming = false;
  late StreamSubscription<NumberHuntBoardState> _subscription;
  late NumberHuntBoardState _state;
  Timer? _clockTimer;
  bool _scoreboardShown = false;
  // Instant de fin de partie vu par CET appareil : fige chrono et tokens.
  // Réglage admin (minutes_per_coin/grace_period_seconds) pour l'anneau de
  // progression coté token (voir CoinBillingRing/demande utilisateur) —
  // chargé une seule fois, uniquement utile en mode à distance.
  Map<String, int>? _economyRate;
  int? _lastFoundNumber;
  Timer? _highlightTimer;

  // Guide pas-à-pas (voir doc de classe de _NumberHuntGuideStep et
  // demande utilisateur : "prends le même soin pour les autres jeux").
  final _targetGuideKey = GlobalKey();
  final _numberGuideKey = GlobalKey();
  final _coinsGuideKey = GlobalKey();
  final _pauseGuideKey = GlobalKey();
  final _chatGuideKey = GlobalKey();
  final _micGuideKey = GlobalKey();
  final _cameraGuideKey = GlobalKey();
  static const _boardGuideKey = 'number_hunt_board';
  _NumberHuntGuideStep? _guideStep;
  bool _guideMicConnecting = false;
  // Démo "trouve le nombre" du guide (voir demande utilisateur : "guider
  // le user vers quelque action pour qu'il comprenne le mécanisme") —
  // l'indice de la VRAIE case portant le nombre-cible actuel (voir
  // _pickGuideTargetIndex), marquée localement comme "trouvée par moi"
  // au tap (voir _onGuideNumberTap), jamais widget.transport.attempt().
  int? _guideTargetIndex;
  bool _guideNumberFound = false;

  @override
  void initState() {
    super.initState();
    _state = widget.transport.currentState;
    _subscription = widget.transport.stateStream.listen(_onState);
    ShowcaseView.get().addOnCompleteCallback(_onGuideStepTapped);
    ShowcaseView.get().addOnDismissCallback(_onGuideDismissed);
    _maybeStartGuide();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // Masque la barre de navigation Android le temps de la partie — la
    // grille de 100 cases profite de tout l'espace vertical disponible.
    // Restaurée dans dispose() pour ne pas affecter le reste de l'app.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Masque aussi la barre de navigation DE L'APP (Carnet de bord/Duo/
    // Jeux/Profil) — voir AppShell, montée au-dessus de tout écran poussé
    // et donc visible par défaut même ici. Même principe que
    // TimelineScreen/EmojiStorySessionScreen. Différé à la fin de la frame
    // en cours (plutôt qu'un appel synchrone en plein milieu du montage de
    // CET écran) pour ne jamais déclencher la reconstruction d'AppShell
    // pendant qu'une autre partie de l'arbre est encore en cours de
    // construction.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppRouter.showGlobalNavBar.value = false;
    });
    if (_isRemoteSession) _loadEconomyRate();
  }

  /// Le guide "Comment jouer" n'existe que dans le mode "Présentiel, un seul téléphone" (voir demande
  /// utilisateur) : pas de lancement automatique ni de bouton "?" en partie à distance ou en présentiel
  /// connecté. Les guides qui y mènent renvoient vers ce mode (voir game_guide_notes.dart).
  bool get _guideAvailable => widget.transport is LocalNumberHuntTransport;

  Future<void> _maybeStartGuide() async {
    if (!_guideAvailable) return;
    final seen = await GameGuideStorage.instance.hasSeen(widget.user.id, _boardGuideKey);
    if (seen || !mounted) return;
    GameGuideStorage.instance.markSeen(widget.user.id, _boardGuideKey);
    _startGuide();
  }

  void _startGuide() {
    if (!_state.isPaused && !_state.finished) {
      widget.transport.pause();
    }
    _startGuideStep(_NumberHuntGuideStep.target);
  }

  /// Indice de la case du plateau RÉEL portant le nombre-cible actuel —
  /// `null` si la cible n'a pas encore été reçue ou n'existe plus sur le
  /// plateau.
  int? _pickGuideTargetIndex() {
    final target = _state.currentTarget;
    if (target == null) return null;
    final index = _state.board.indexOf(target);
    return index == -1 ? null : index;
  }

  void _startGuideStep(_NumberHuntGuideStep step) {
    if (!mounted) return;
    if (step == _NumberHuntGuideStep.tapNumber) {
      _guideNumberFound = false;
      _guideTargetIndex = _pickGuideTargetIndex();
      if (_guideTargetIndex == null) {
        _startGuideStep(_NumberHuntGuideStep.coins);
        return;
      }
    }
    setState(() {
      _guideStep = step;
      if (step == _NumberHuntGuideStep.micReady) _guideMicConnecting = true;
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

  /// Tap RÉEL sur la case du nombre-cible désignée (voir
  /// _NumberHuntTile.onGuideTap) — la marque localement comme trouvée par
  /// moi, jamais widget.transport.attempt() (bloqué de toute façon
  /// pendant la pause du guide, voir _startGuide).
  void _onGuideNumberTap() {
    setState(() => _guideNumberFound = true);
    _startGuideStep(_NumberHuntGuideStep.numberFound);
  }

  GlobalKey _guideKeyFor(_NumberHuntGuideStep step) {
    switch (step) {
      case _NumberHuntGuideStep.target:
        return _targetGuideKey;
      case _NumberHuntGuideStep.tapNumber:
      case _NumberHuntGuideStep.numberFound:
        return _numberGuideKey;
      case _NumberHuntGuideStep.coins:
        return _coinsGuideKey;
      case _NumberHuntGuideStep.pause:
        return _pauseGuideKey;
      case _NumberHuntGuideStep.chat:
        return _chatGuideKey;
      case _NumberHuntGuideStep.micJoin:
      case _NumberHuntGuideStep.micReady:
        return _micGuideKey;
      case _NumberHuntGuideStep.cameraReady:
        return _cameraGuideKey;
    }
  }

  void _onGuideStepTapped(int? index, GlobalKey key) {
    switch (_guideStep) {
      case _NumberHuntGuideStep.target:
        _startGuideStep(_NumberHuntGuideStep.tapNumber);
        break;
      case _NumberHuntGuideStep.tapNumber:
        // N'avance PAS ici (gestes de cible désactivés) — seul un vrai
        // tap sur la case désignée fait avancer (voir _onGuideNumberTap).
        break;
      case _NumberHuntGuideStep.numberFound:
        setState(() {
          _guideNumberFound = false;
          _guideTargetIndex = null;
        });
        _startGuideStep(_NumberHuntGuideStep.coins);
        break;
      case _NumberHuntGuideStep.coins:
        _startGuideStep(_NumberHuntGuideStep.pause);
        break;
      case _NumberHuntGuideStep.pause:
        _startGuideStep(_NumberHuntGuideStep.chat);
        break;
      case _NumberHuntGuideStep.chat:
        _startGuideStep(_NumberHuntGuideStep.micJoin);
        break;
      case _NumberHuntGuideStep.micJoin:
        _startGuideStep(_NumberHuntGuideStep.micReady);
        break;
      case _NumberHuntGuideStep.micReady:
        _startGuideStep(_NumberHuntGuideStep.cameraReady);
        break;
      case _NumberHuntGuideStep.cameraReady:
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
      _guideNumberFound = false;
      _guideTargetIndex = null;
    });
  }

  Widget _buildGuideVoiceDemo() {
    final phase = switch (_guideStep) {
      _NumberHuntGuideStep.micJoin => GameGuideVoicePhase.micJoin,
      _NumberHuntGuideStep.micReady => GameGuideVoicePhase.micReady,
      _NumberHuntGuideStep.cameraReady => GameGuideVoicePhase.cameraReady,
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

  /// Nombre de tokens consommés depuis le début de CETTE partie — fluide
  /// comme l'anneau (même calcul), voir demande utilisateur.
  double? _coinsConsumed() {
    final elapsed = _elapsedBillableSeconds();
    final cycleSeconds = (_economyRate?['minutes_per_coin'] ?? 8) * 60;
    if (elapsed == null || cycleSeconds <= 0) return 0;
    return elapsed / cycleSeconds;
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

  void _onState(NumberHuntBoardState state) {
    if (!mounted) return;
    final previouslyFound = _state.found;
    // Repère le nombre qui vient d'être trouvé (présent dans le nouvel état
    // mais pas dans l'ancien) pour un bref surlignage — `null` si rien de
    // nouveau (ex. simple resynchronisation, pas une vraie trouvaille).
    String? newlyFoundKey;
    for (final key in state.found.keys) {
      if (!previouslyFound.containsKey(key)) {
        newlyFoundKey = key;
        break;
      }
    }

    setState(() {
      _state = state;
    });

    if (newlyFoundKey != null) {
      _lastFoundNumber = int.tryParse(newlyFoundKey);
      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _lastFoundNumber = null);
      });
    }

    if (state.finished && !_scoreboardShown) {
      _scoreboardShown = true;
      // Voir demande utilisateur : "ça doit être instantané".
      if (_isRemoteSession) unawaited(WalletBalanceNotifier.instance.refresh());
      // Scoreboard systématique, même après un abandon (voir demande
      // utilisateur : "si on abandonne, on a le score en bas pour tous les
      // jeux, il faut proposer de quitter et pour rejouer c'est pour celui
      // qui a lancé le jeu") — _showScoreboard gère déjà "Quitter" pour
      // tous et "Rejouer" réservé à widget.isLauncher.
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
    final rematch = await showNumberHuntMatchScoreboard(
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
      if (transport is RemoteNumberHuntTransport) {
        unawaited(GameService.instance.closeGameSession('number_hunt', transport.sessionId));
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
    if (transport is RemoteNumberHuntTransport) {
      unawaited(GameService.instance.pingGameSessionMic('number_hunt', transport.sessionId));
    }
  }

  Future<void> _onTapNumber(int number) async {
    if (_state.finished || _state.isPaused) return;
    if (_state.found.containsKey('$number')) return;
    await widget.transport.attempt(number);
  }

  String _elapsed() {
    final started = _state.startedAt;
    if (started == null) return '0:00';
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
  /// Le Jeu des Carrés.
  Color _colorFor(String userId) {
    final ids = widget.playerNames.keys.toList()..sort();
    return userId == ids.first ? _kRedColor : _kBlueColor;
  }

  @override
  void dispose() {
    _subscription.cancel();
    ShowcaseView.get().removeOnCompleteCallback(_onGuideStepTapped);
    ShowcaseView.get().removeOnDismissCallback(_onGuideDismissed);
    _clockTimer?.cancel();
    _highlightTimer?.cancel();
    widget.transport.dispose();
    widget.nearbyComms?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Différé au frame suivant (voir memory_game_board_screen.dart).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppRouter.showGlobalNavBar.value = true;
    });
    super.dispose();
  }

  String? get _commentsBoxId {
    final transport = widget.transport;
    return transport is RemoteNumberHuntTransport ? transport.boxId : null;
  }

  String get _sessionId {
    final transport = widget.transport;
    return transport is RemoteNumberHuntTransport ? transport.sessionId : '';
  }

  // Voir memory_game_board_screen.dart (même pattern, phase 4).
  String? get _friendSessionType =>
      (widget.transport is RemoteNumberHuntTransport && _commentsBoxId == null) ? 'number_hunt' : null;

  // Voir demande utilisateur : "pareil je ne voi pa mon decompte de piece
  // comme dan le jeu distance avec mon binome" — voir dot_squares_board_
  // screen.dart (même correctif).
  bool get _isRemoteSession => widget.transport is RemoteNumberHuntTransport;

  // Voir memory_game_board_screen.dart (même pattern, voir demande
  // utilisateur : "jai lancer le defi mai je ne voi pa de facturation").
  String? get _walletGuardBoxId {
    if (_commentsBoxId != null) return _commentsBoxId;
    if (_friendSessionType == null) return null;
    return BoxScope.of(context).currentBox?.id;
  }

  /// Bouton "Terminer la partie" du popup de solde épuisé (voir
  /// GameWalletGuard) — même geste qu'un abandon volontaire.
  String get _partnerUserId =>
      widget.playerNames.keys.firstWhere((id) => id != widget.user.id, orElse: () => widget.user.id);

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final commentsBoxId = _commentsBoxId;

    return PopScope(
      canPop: _state.finished,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Ne referme plus l'écran soi-même (voir demande utilisateur :
        // scoreboard systématique après un abandon, même geste que le
        // bouton drapeau ci-dessous) — _onState détecte `state.finished` et
        // affiche le tableau de score (avec "Rejouer" pour le lanceur,
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
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Showcase(
                      key: _targetGuideKey,
                      title: 'Le nombre à trouver',
                      description: "N'importe lequel des deux peut taper ce nombre en premier sur la grille, pas besoin d'attendre son tour.",
                      targetBorderRadius: BorderRadius.circular(8),
                      child: Text(
                        _state.finished
                            ? LocaleScope.t(context, 'game_board_finished_label')
                            : LocaleScope.t(context, 'number_hunt_find_target', {'number': '${_state.currentTarget ?? '-'}'}),
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 20, color: theme.primary),
                      ),
                    ),
                    Showcase(
                      key: _coinsGuideKey,
                      title: 'Temps et Tokens',
                      description: _isRemoteSession && widget.isLauncher
                          ? 'Le chrono et le nombre de Tokens déjà consommés par cette partie à distance.'
                          : 'Le temps écoulé depuis le début de la partie.',
                      targetBorderRadius: BorderRadius.circular(8),
                      child: Row(
                        children: [
                          Icon(Icons.timer_outlined, size: 16, color: theme.textOnBackgroundMuted),
                          const SizedBox(width: 4),
                          Text(_elapsed(), style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted)),
                          if (_isRemoteSession && widget.isLauncher && !SubscriptionStatusNotifier.instance.isActive) ...[
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
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: Row(
                  children: [
                    for (final userId in widget.playerNames.keys) ...[
                      if (userId != widget.playerNames.keys.first) const SizedBox(width: 10),
                      Expanded(
                        child: _NumberHuntPlayerChip(
                          theme: theme,
                          name: widget.playerNames[userId] ?? '',
                          avatar: widget.playerAvatars[userId],
                          color: _colorFor(userId),
                          score: _state.scoreFor(userId),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: GridView.builder(
                        physics: const BouncingScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 8,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                          childAspectRatio: 1,
                        ),
                        itemCount: _state.board.length,
                        itemBuilder: (context, index) {
                          final number = _state.board[index];
                          final isGuideTarget = index == _guideTargetIndex;
                          final foundBy = isGuideTarget && _guideNumberFound ? widget.user.id : _state.found['$number'];
                          final tile = _NumberHuntTile(
                            theme: theme,
                            number: number,
                            color: foundBy != null ? _colorFor(foundBy) : null,
                            justFound: _lastFoundNumber == number,
                            onTap: isGuideTarget && _guideStep == _NumberHuntGuideStep.tapNumber
                                ? _onGuideNumberTap
                                : () => _onTapNumber(number),
                          );
                          if (!isGuideTarget || _guideStep == null) return tile;
                          return Showcase(
                            key: _numberGuideKey,
                            title: _guideNumberFound ? 'Trouvé !' : 'Tape le bon nombre',
                            description: _guideNumberFound
                                ? "Bravo, tu marques un point. Le nombre change aussitôt pour le suivant — le premier des deux à taper le bon nombre marque le point à chaque fois."
                                : 'Cette case porte le nombre affiché plus haut — tape-la pour la trouver.',
                            targetBorderRadius: BorderRadius.circular(8),
                            disableDefaultTargetGestures: _guideStep == _NumberHuntGuideStep.tapNumber,
                            child: tile,
                          );
                        },
                      ),
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
            ],
          ),
        ),
      ),
    ),
        ),
        if (commentsBoxId != null)
          GameCommentOverlay(boxId: commentsBoxId, enabled: true, guideKey: _chatGuideKey)
        else if (_friendSessionType != null)
          GameCommentOverlay(
            sessionType: _friendSessionType,
            sessionId: _sessionId,
            enabled: true,
            guideKey: _chatGuideKey,
          )
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
                  forceEnded: _state.isPaused,
                  onMicActiveChanged: _onMicActiveChanged,
                )
              : _friendSessionType != null
                  ? VoiceCallOverlay(
                      sessionType: _friendSessionType,
                      sessionId: _sessionId,
                      myUserId: widget.user.id,
                      partnerUserId: _partnerUserId,
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
          boxId: _walletGuardBoxId,
          sessionType: 'number_hunt',
          sessionId: _sessionId,
        ),
      ],
      ),
    );
  }
}

class _WhoFoundButton extends StatelessWidget {
  final Color color;
  final String name;
  final VoidCallback onTap;

  const _WhoFoundButton({required this.color, required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(backgroundColor: color, padding: const EdgeInsets.symmetric(vertical: 14)),
        child: Text(name, style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _NumberHuntPlayerChip extends StatelessWidget {
  final ThemePalette theme;
  final String name;
  final String? avatar;
  final Color color;
  final int score;

  const _NumberHuntPlayerChip({
    required this.theme,
    required this.name,
    required this.avatar,
    required this.color,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.surface.withValues(alpha: theme.isDark ? 0.5 : 0.75),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: color.withValues(alpha: 0.16),
            backgroundImage: (avatar != null && avatar!.isNotEmpty) ? NetworkImage(avatar!) : null,
            child: (avatar == null || avatar!.isEmpty)
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: color, fontSize: 12),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: theme.textOnBackground),
            ),
          ),
          const SizedBox(width: 4),
          Text('$score', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

class _NumberHuntTile extends StatelessWidget {
  final ThemePalette theme;
  final int number;
  final Color? color;
  final bool justFound;
  final VoidCallback onTap;

  const _NumberHuntTile({
    required this.theme,
    required this.number,
    required this.color,
    required this.justFound,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final found = color != null;
    return Material(
      color: justFound
          ? (color ?? theme.primary).withValues(alpha: 0.85)
          : found
              ? (color ?? theme.primary).withValues(alpha: 0.12)
              : theme.surface.withValues(alpha: theme.isDark ? 0.5 : 0.85),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: found ? null : onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: found ? (color ?? theme.primary).withValues(alpha: 0.4) : theme.primary.withValues(alpha: 0.15)),
          ),
          child: Center(
            child: Text(
              '$number',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: justFound
                    ? Colors.white
                    : found
                        ? (color ?? theme.primary)
                        : theme.textOnBackground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
