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
import '../../box/box_scope.dart';
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
import '../../shop/subscription_status_notifier.dart';
import '../../shop/wallet_balance_notifier.dart';
import 'suit_battle_engine.dart';
import 'suit_battle_transport.dart';
import 'suit_battle_transport_remote.dart';

/// Étapes du guide pas-à-pas du plateau (voir doc de _BoardGuideStep dans
/// memory_game_board_screen.dart pour le principe général) — une bulle
/// sur le bandeau de tour et une sur SA main (proportionné à ce jeu, voir
/// demande utilisateur), pas de simulation carte par carte.
enum _SuitBattleGuideStep { turn, hand, handResult, coins, pause, chat, micJoin, micReady, cameraReady }

const _kRedColor = Color(0xFFE5484D);
const _kBlueColor = Color(0xFF2F6FED);

const _kHandCardWidth = 56.0;
const _kHandCardHeight = 80.0;
const _kTableCardWidth = 96.0;
const _kTableCardHeight = 136.0;

/// Plateau du "Jeu de Carte Classique" — UNIQUE écran de jeu partagé par
/// les 2 modes (voir SuitBattleTransport), copie structurelle conforme des
/// autres jeux (pause/reprise, chrono, commentaires/appel vocal en mode à
/// distance). Contrairement à "Bataille" (piles cachées retournées une à
/// une), les deux mains sont ici en ÉVENTAIL, FACE VISIBLE en permanence
/// pour les deux joueurs — on tape DIRECTEMENT sur sa carte pour la jouer,
/// jamais de bouton "Retourner" séparé.
class SuitBattleBoardScreen extends StatefulWidget {
  final Game game;
  final AppUser user;
  final SuitBattleTransport transport;
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

  const SuitBattleBoardScreen({
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
  State<SuitBattleBoardScreen> createState() => _SuitBattleBoardScreenState();
}

class _SuitBattleBoardScreenState extends State<SuitBattleBoardScreen> with SingleTickerProviderStateMixin {
  bool _resuming = false;
  late StreamSubscription<SuitBattleBoardState> _subscription;
  late SuitBattleBoardState _state;
  Timer? _clockTimer;
  bool _scoreboardShown = false;
  // Réglage admin (minutes_per_coin/grace_period_seconds) pour l'anneau de
  // progression coté token (voir CoinBillingRing/demande utilisateur) —
  // chargé une seule fois, uniquement utile en mode à distance.
  Map<String, int>? _economyRate;

  // Secousse locale d'une carte tapée hors couleur en phase "response" —
  // voir demande utilisateur : rejetée SANS jamais appeler le transport
  // (validation cliente identique à SuitBattleEngine.respondCard).
  late final AnimationController _rejectController;
  int? _rejectingIndex;
  bool _handSorted = false;

  // Guide pas-à-pas (voir doc de classe de _SuitBattleGuideStep et
  // demande utilisateur : "prends le même soin pour les autres jeux").
  final _turnGuideKey = GlobalKey();
  final _handGuideKey = GlobalKey();
  final _tableGuideKey = GlobalKey();
  final _coinsGuideKey = GlobalKey();
  final _pauseGuideKey = GlobalKey();
  final _chatGuideKey = GlobalKey();
  final _micGuideKey = GlobalKey();
  final _cameraGuideKey = GlobalKey();
  static const _boardGuideKey = 'suit_battle_board';
  _SuitBattleGuideStep? _guideStep;
  bool _guideMicConnecting = false;
  // Démo "joue une carte" du guide (voir demande utilisateur : "guider le
  // user vers quelque action pour qu'il comprenne le mécanisme") — la
  // carte tapée disparaît localement de ma main (voir _HandFan.
  // excludeIndex) et s'affiche sur la table (voir _displayTableCard),
  // jamais widget.transport.playLead()/respondCard().
  int? _guidePlayedIndex;
  String? _guidePlayedCard;

  // Animation de balayage (voir demande utilisateur : "quand je balaie on
  // doit voir les cartes se réunir et aller se ranger en haut") —
  // instantané pris au tap sur "Balayer" (voir _tapSweep), juste pour
  // l'animation de SORTIE, jamais relu comme source de vérité. Borné dans
  // le temps (toujours refermé après un délai fixe), ne peut donc jamais
  // rester bloqué.
  bool _collecting = false;
  String? _collectingMyCard;
  String? _collectingPartnerCard;
  // Vrai pour "Capturer" (voir demande utilisateur : "si je capture une
  // carte c'est pour la garder dans ma pile de cartes EN MAIN" — repart
  // dans ma main, PAS un gain) — la carte vole alors vers le BAS (ma main),
  // pas vers le badge de pile en haut (réservé à "Balayer", un vrai gain).
  bool _collectingToHand = false;

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
    _rejectController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _rejectingIndex = null);
        }
      });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppRouter.showGlobalNavBar.value = false;
    });
    if (_isRemoteSession) _loadEconomyRate();
  }

  /// Le guide "Comment jouer" n'existe que dans le mode "Présentiel, un seul téléphone" (voir demande
  /// utilisateur) : pas de lancement automatique ni de bouton "?" en partie à distance ou en présentiel
  /// connecté. Les guides qui y mènent renvoient vers ce mode (voir game_guide_notes.dart).
  bool get _guideAvailable => false; // pas de mode "un seul téléphone" pour ce jeu

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
    _startGuideStep(_SuitBattleGuideStep.turn);
  }

  void _startGuideStep(_SuitBattleGuideStep step) {
    if (!mounted) return;
    setState(() {
      _guideStep = step;
      if (step == _SuitBattleGuideStep.micReady) _guideMicConnecting = true;
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

  GlobalKey _guideKeyFor(_SuitBattleGuideStep step) {
    switch (step) {
      case _SuitBattleGuideStep.turn:
        return _turnGuideKey;
      case _SuitBattleGuideStep.hand:
        return _handGuideKey;
      case _SuitBattleGuideStep.handResult:
        return _tableGuideKey;
      case _SuitBattleGuideStep.coins:
        return _coinsGuideKey;
      case _SuitBattleGuideStep.pause:
        return _pauseGuideKey;
      case _SuitBattleGuideStep.chat:
        return _chatGuideKey;
      case _SuitBattleGuideStep.micJoin:
      case _SuitBattleGuideStep.micReady:
        return _micGuideKey;
      case _SuitBattleGuideStep.cameraReady:
        return _cameraGuideKey;
    }
  }

  void _onGuideStepTapped(int? index, GlobalKey key) {
    switch (_guideStep) {
      case _SuitBattleGuideStep.turn:
        _startGuideStep(_SuitBattleGuideStep.hand);
        break;
      case _SuitBattleGuideStep.hand:
        // N'avance PAS ici (gestes de cible désactivés) — seul un vrai
        // tap sur la carte désignée fait avancer (voir _onGuideHandTap).
        break;
      case _SuitBattleGuideStep.handResult:
        setState(() {
          _guidePlayedIndex = null;
          _guidePlayedCard = null;
        });
        _startGuideStep(_SuitBattleGuideStep.coins);
        break;
      case _SuitBattleGuideStep.coins:
        _startGuideStep(_SuitBattleGuideStep.pause);
        break;
      case _SuitBattleGuideStep.pause:
        _startGuideStep(_SuitBattleGuideStep.chat);
        break;
      case _SuitBattleGuideStep.chat:
        _startGuideStep(_SuitBattleGuideStep.micJoin);
        break;
      case _SuitBattleGuideStep.micJoin:
        _startGuideStep(_SuitBattleGuideStep.micReady);
        break;
      case _SuitBattleGuideStep.micReady:
        _startGuideStep(_SuitBattleGuideStep.cameraReady);
        break;
      case _SuitBattleGuideStep.cameraReady:
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
      _guidePlayedIndex = null;
      _guidePlayedCard = null;
    });
  }

  /// Tap RÉEL sur la carte désignée par le guide (voir _HandFan.
  /// onGuideTap) — la retire visuellement de ma main et l'affiche sur la
  /// table, purement en local.
  void _onGuideHandTap(int index, String card) {
    setState(() {
      _guidePlayedIndex = index;
      _guidePlayedCard = card;
    });
    _startGuideStep(_SuitBattleGuideStep.handResult);
  }

  Widget _buildGuideVoiceDemo() {
    final phase = switch (_guideStep) {
      _SuitBattleGuideStep.micJoin => GameGuideVoicePhase.micJoin,
      _SuitBattleGuideStep.micReady => GameGuideVoicePhase.micReady,
      _SuitBattleGuideStep.cameraReady => GameGuideVoicePhase.cameraReady,
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
    // Voir demande utilisateur : le chrono continue de tourner après la fin
    // de la manche, tant que la session n'est pas VRAIMENT fermée (voir
    // GameSessionLifecycleController) — plus de repli sur un instant figé.
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

  void _onState(SuitBattleBoardState state) {
    if (!mounted) return;
    setState(() {
      _state = state;
    });

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
    final rematch = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SuitBattleScoreboardSheet(
        state: _state,
        playerNames: widget.playerNames,
        playerAvatars: widget.playerAvatars,
        colorFor: _colorFor,
        allowRematch: widget.isLauncher && widget.onRematch != null,
      ),
    );
    if (rematch == true && widget.isLauncher && widget.onRematch != null && mounted) {
      // Voir demande utilisateur : "le chrono et l'appel doivent continuer
      // sans coupure entre les deux manches" — pas de closeGameSession ici,
      // seule une VRAIE sortie ferme la session (voir la branche ci-dessous).
      await widget.onRematch!(context);
    } else if (mounted) {
      // "Quitter", ou tap à côté de la feuille (voir demande utilisateur) : referme le jeu
      // (retour au choix de la difficulté pour l'invité·e, voir onQuit).
      // Voir demande utilisateur : "on peut quitter sans forcément cliquer
      // sur le bouton quitter" — CE branchement couvre déjà les deux cas
      // (bouton "Quitter" ET tap en dehors de la feuille/retour arrière,
      // qui resolvent tous deux `rematch` à autre chose que `true`), donc
      // un seul point d'appel suffit. Ferme VRAIMENT la session (arrête
      // micro/caméra/chrono/facturation pour les DEUX, voir
      // GameSessionLifecycleController) — seulement en mode à distance, où
      // une vraie session serveur existe.
      final transport = widget.transport;
      if (transport is RemoteSuitBattleTransport) {
        unawaited(GameService.instance.closeGameSession('suit_battle', transport.sessionId));
      }
      if (widget.onQuit != null) {
        await widget.onQuit!(context);
      } else {
        Navigator.of(context).pop();
      }
    }
  }

  /// Voir demande utilisateur : "vérifier... si l'un des deux micros est
  /// actif" — repousse la coupure automatique d'inactivité tant que NOTRE
  /// PROPRE micro se rouvre après la fin de la manche (voir
  /// VoiceCallOverlay.onMicActiveChanged). Sans effet pendant une partie
  /// encore en cours (rien à repousser) ni hors mode à distance (pas de
  /// session serveur à prévenir).
  void _onMicActiveChanged(bool active) {
    if (!active || !_state.finished) return;
    final transport = widget.transport;
    if (transport is RemoteSuitBattleTransport) {
      unawaited(GameService.instance.pingGameSessionMic('suit_battle', transport.sessionId));
    }
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
  /// les autres jeux.
  Color _colorFor(String userId) {
    final ids = widget.playerNames.keys.toList()..sort();
    return userId == ids.first ? _kRedColor : _kBlueColor;
  }

  /// Une carte de MA main est tapée. En phase "lead" (mon tour), n'importe
  /// laquelle est jouable. En phase "response", seule une carte de la même
  /// couleur que la carte sur table (ou un Joker) est valide — sinon
  /// rejetée LOCALEMENT (secousse), sans jamais appeler le transport (voir
  /// doc de classe).
  Future<void> _tapMyCard(int index, String card) async {
    if (_state.finished || _state.isPaused) return;

    // Voir demande utilisateur : "si on ne balaie pas et on clique pour
    // sortir, afficher une petite info" — l'échange précédent doit être
    // balayé (voir _tapSweep) avant de pouvoir en rejouer un nouveau.
    if (_state.isRevealing) {
      _showSweepFirstHint();
      return;
    }

    // Voir demande utilisateur : "que se passe-t-il si je clique sur une
    // carte alors que c'est mon binôme qui doit jouer" — jusqu'ici
    // silencieux, aucun retour visuel ; message d'info désormais, comme
    // pour la phase "reveal" ci-dessus.
    if (!_state.isMyTurn) {
      _showHint("Ce n'est pas ton tour.");
      return;
    }

    if (_state.phase == 'lead') {
      await widget.transport.playLead(widget.user.id, card);
      return;
    }

    if (_state.phase == 'response') {
      final tableCard = _state.tableCard;
      if (tableCard == null) return;
      // Voir demande utilisateur : "face à un Joker on peut sortir
      // n'importe laquelle des cartes" — doit rester synchronisé avec la
      // même règle dans SuitBattleEngine.respondCard, sinon cette
      // pré-validation locale rejetterait à tort (secousse) une carte que
      // le moteur accepterait bel et bien.
      final valid = SuitBattleEngine.isJoker(tableCard) ||
          SuitBattleEngine.isJoker(card) ||
          SuitBattleEngine.suitOf(card) == SuitBattleEngine.suitOf(tableCard);
      if (!valid) {
        setState(() => _rejectingIndex = index);
        unawaited(_rejectController.forward(from: 0));
        // Voir demande utilisateur : la secousse seule ne suffisait pas,
        // un message explicite en plus.
        _showHint('Cette carte ne correspond pas à la couleur demandée.');
        return;
      }
      await widget.transport.respondCard(widget.user.id, card);
    }
  }

  /// Voir demande utilisateur : "on n'utilise pas de modèle. on dispose et
  /// le reste peut déborder descendre... je peux défiler" — bascule
  /// l'affichage de MA main, EN PLACE (jamais de popup par-dessus le
  /// plateau), entre l'éventail normal et les colonnes groupées par même
  /// symbole/couleur, triées du plus petit au plus grand, Jokers à part.
  void _toggleHandSorted() => setState(() => _handSorted = !_handSorted);

  /// Même règles que `_tapMyCard`, mais sans la secousse locale par index
  /// (propre à la rangée compacte, voir `_rejectingIndex`) — un message
  /// suffit ici.
  Future<void> _tapSortedCard(String card) async {
    if (_state.finished || _state.isPaused) return;

    if (_state.isRevealing) {
      _showSweepFirstHint();
      return;
    }

    if (!_state.isMyTurn) {
      _showHint("Ce n'est pas ton tour.");
      return;
    }

    if (_state.phase == 'lead') {
      if (!await _confirmPlaySortedCard(card)) return;
      await widget.transport.playLead(widget.user.id, card);
      return;
    }

    if (_state.phase == 'response') {
      final tableCard = _state.tableCard;
      if (tableCard == null) return;
      final valid = SuitBattleEngine.isJoker(tableCard) ||
          SuitBattleEngine.isJoker(card) ||
          SuitBattleEngine.suitOf(card) == SuitBattleEngine.suitOf(tableCard);
      if (!valid) {
        _showHint('Cette carte ne correspond pas à la couleur demandée.');
        return;
      }
      if (!await _confirmPlaySortedCard(card)) return;
      await widget.transport.respondCard(widget.user.id, card);
    }
  }

  /// Voir demande utilisateur : "il faut demander confirmation en
  /// affichant la carte qui sera jouée" — uniquement pour la vue triée en
  /// place (l'éventail normal `_tapMyCard` n'a pas ce risque de clic
  /// approximatif entre cartes serrées, donc reste inchangé).
  Future<bool> _confirmPlaySortedCard(String card) async {
    final theme = ThemeScope.paletteOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Jouer cette carte ?'),
        content: SizedBox(
          height: 130,
          child: Center(
            child: PlayingCardFace(card: card, isJoker: SuitBattleEngine.isJoker(card), width: 80, height: 112),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(LocaleScope.t(ctx, 'common_cancel'))),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Jouer', style: TextStyle(color: theme.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  void _showSweepFirstHint() => _showHint('Balaie les deux cartes avant de rejouer.');

  void _showHint(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        // Voir demande utilisateur : "l'info... est cachée par les icônes
        // micro" — VoiceCallOverlay/NearbyVoiceOverlay/GameCommentOverlay
        // flottent en Positioned(bottom: 24, ...) par-dessus tout l'écran
        // (voir build()) ; un SnackBar "floating" avec une marge basse
        // dédiée passe au-dessus au lieu de se coller au bord.
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
      ),
    );
  }

  /// Voir demande utilisateur : "si je capture une carte c'est pour la
  /// garder dans ma pile de cartes EN MAIN, et je pourrai la jouer plus
  /// tard" — la carte repart donc dans MA MAIN (pas un gain), l'animation
  /// vole vers le bas au lieu du badge de pile en haut (voir
  /// _collectingToHand).
  Future<void> _tapCapture() async {
    if (_state.finished || _state.isPaused || _collecting) return;
    if (!_state.isMyTurn || _state.phase != 'response') return;
    final tableCard = _state.tableCard;
    setState(() {
      _collecting = true;
      _collectingToHand = true;
      _collectingMyCard = tableCard;
      _collectingPartnerCard = null;
    });
    unawaited(widget.transport.captureLead(widget.user.id));
    await Future.delayed(const Duration(milliseconds: 520));
    if (!mounted) return;
    setState(() => _collecting = false);
  }

  /// "Balayer" (voir demande utilisateur) — n'importe lequel des deux
  /// joueurs peut le déclencher, l'issue de l'échange est déjà tranchée.
  /// [myCard]/[partnerCard] : instantané pris au moment du tap (voir
  /// build(), qui les calcule déjà pour l'affichage) — sans lui, il n'y
  /// aurait plus rien à animer dès que `widget.transport.sweepExchange()`
  /// fait sortir `_state` de la phase "reveal". Destination commune (voir
  /// demande utilisateur : "une seule pile"), peu importe qui a gagné cet
  /// échange.
  Future<void> _tapSweep(String? myCard, String? partnerCard) async {
    if (_state.finished || _state.isPaused || !_state.isRevealing || _collecting) return;
    setState(() {
      _collecting = true;
      _collectingToHand = false;
      _collectingMyCard = myCard;
      _collectingPartnerCard = partnerCard;
    });
    unawaited(widget.transport.sweepExchange());
    await Future.delayed(const Duration(milliseconds: 550));
    if (!mounted) return;
    setState(() => _collecting = false);
  }

  @override
  void dispose() {
    _subscription.cancel();
    ShowcaseView.get().removeOnCompleteCallback(_onGuideStepTapped);
    ShowcaseView.get().removeOnDismissCallback(_onGuideDismissed);
    _clockTimer?.cancel();
    _rejectController.dispose();
    widget.transport.dispose();
    widget.nearbyComms?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppRouter.showGlobalNavBar.value = true;
    });
    super.dispose();
  }

  Future<void> _shuffle() => widget.transport.shuffleDeck();

  Future<void> _dealAutomatic() => widget.transport.dealAutomatic();

  Future<void> _readyUp() => widget.transport.readyUp();

  String? get _commentsBoxId {
    final transport = widget.transport;
    return transport is RemoteSuitBattleTransport ? transport.boxId : null;
  }

  String get _sessionId {
    final transport = widget.transport;
    return transport is RemoteSuitBattleTransport ? transport.sessionId : '';
  }

  // Voir memory_game_board_screen.dart (même pattern, phase 4).
  String? get _friendSessionType =>
      (widget.transport is RemoteSuitBattleTransport && _commentsBoxId == null) ? 'suit_battle' : null;

  // Voir demande utilisateur : "pareil je ne voi pa mon decompte de piece
  // comme dan le jeu distance avec mon binome" — voir dot_squares_board_
  // screen.dart (même correctif).
  bool get _isRemoteSession => widget.transport is RemoteSuitBattleTransport;

  // Voir memory_game_board_screen.dart (même pattern, voir demande
  // utilisateur : "jai lancer le defi mai je ne voi pa de facturation").
  String? get _walletGuardBoxId {
    if (_commentsBoxId != null) return _commentsBoxId;
    if (_friendSessionType == null) return null;
    return BoxScope.of(context).currentBox?.id;
  }

  /// Bouton "Terminer la partie" du popup de solde épuisé (voir
  /// GameWalletGuard) — même geste qu'un abandon volontaire.
  String _partnerId() => widget.playerNames.keys.firstWhere((id) => id != widget.user.id, orElse: () => widget.user.id);

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final commentsBoxId = _commentsBoxId;

    if (!_state.dealt) {
      return _SuitBattlePreDealScreen(
        game: widget.game,
        theme: theme,
        state: _state,
        playerNames: widget.playerNames,
        colorFor: _colorFor,
        onShuffle: _shuffle,
        onDealAutomatic: _dealAutomatic,
      );
    }

    if (!_state.started) {
      return _SuitBattleReadyScreen(
        game: widget.game,
        theme: theme,
        state: _state,
        playerNames: widget.playerNames,
        colorFor: _colorFor,
        onReadyUp: _readyUp,
      );
    }

    final myColor = _colorFor(widget.user.id);
    final partnerId = _partnerId();
    final partnerColor = _colorFor(partnerId);
    final canRespond = _state.isMyTurn && _state.phase == 'response' && !_state.finished && !_state.isPaused;
    final canLead = _state.isMyTurn && _state.phase == 'lead' && !_state.finished && !_state.isPaused;
    // Voir demande utilisateur : "les deux cartes sorties se disposent
    // côte à côte... couronne au-dessus de la carte la plus forte" — MA
    // carte est celle du meneur si J'AI mené, sinon celle du répondant
    // (l'inverse pour celle du binôme) ; ne sert qu'en phase "reveal", où
    // les deux sont garanties non nulles.
    final leaderId = _state.tableOwnerUserId;
    final myRevealCard = leaderId == widget.user.id ? _state.tableCard : _state.responseCard;
    final partnerRevealCard = leaderId == widget.user.id ? _state.responseCard : _state.tableCard;
    final myRevealWins = _state.pendingRoundWinnerId == widget.user.id;

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
                                Text(
                                  _state.finished
                                      ? LocaleScope.t(context, 'game_board_finished_label')
                                      : 'Manche ${_state.roundsCount}',
                                  style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 16, color: theme.primary),
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
                                            style:
                                                GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: theme.primary),
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
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Showcase(
                              key: _turnGuideKey,
                              title: 'À qui de jouer ?',
                              description: 'Ce bandeau indique à qui c\'est le tour et ce qu\'il reste à faire (jouer, répondre, capturer).',
                              targetBorderRadius: BorderRadius.circular(8),
                              child: _TurnBanner(
                                theme: theme,
                                state: _state,
                                partnerName: widget.playerNames[partnerId] ?? LocaleScope.t(context, 'memory_score_player_fallback'),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                            child: _HandFan(
                              cards: _state.partnerSpread,
                              color: partnerColor,
                              interactive: false,
                              faceUp: false,
                              rejectingIndex: null,
                              onTapCard: null,
                            ),
                          ),
                          Expanded(
                            child: Center(
                              child: _guideStep == _SuitBattleGuideStep.handResult
                                  ? Showcase(
                                      key: _tableGuideKey,
                                      title: 'Elle part sur la table',
                                      description:
                                          "Cette carte est maintenant sur la table. Si c'était à toi d'entamer, n'importe quelle carte convenait. Si tu répondais à ton binôme, elle devait être de la même couleur — sinon il aurait fallu capturer ou la perdre.",
                                      targetBorderRadius: BorderRadius.circular(12),
                                      child: _TableArea(
                                        theme: theme,
                                        tableCard: _guidePlayedCard ?? _state.tableCard,
                                        tableCardName: null,
                                        fromBelow: true,
                                        canCapture: canRespond,
                                        onCapture: _tapCapture,
                                      ),
                                    )
                                  // Voir demande utilisateur : "les deux
                                  // cartes sorties se disposent côte à
                                  // côte... couronne... bouton Balayer" —
                                  // le guide (démo, jamais de vraie phase
                                  // "reveal") reste sur l'affichage simple.
                                  // Masqué pendant l'animation de balayage
                                  // (voir _collecting ci-dessous, qui prend
                                  // le relais avec son propre instantané).
                                  : _state.isRevealing && !_collecting
                                      ? _DuelRevealArea(
                                          myCard: myRevealCard,
                                          partnerCard: partnerRevealCard,
                                          myCardWins: myRevealWins,
                                          myName: widget.playerNames[widget.user.id] ?? LocaleScope.t(context, 'memory_score_player_fallback'),
                                          partnerName: widget.playerNames[partnerId] ?? LocaleScope.t(context, 'memory_score_player_fallback'),
                                          onSweep: () => _tapSweep(myRevealCard, partnerRevealCard),
                                        )
                                      : _TableArea(
                                          theme: theme,
                                          tableCard: _guidePlayedCard ?? _state.tableCard,
                                          tableCardName: _state.tableOwnerUserId == null
                                              ? null
                                              : (_state.tableOwnerUserId == widget.user.id
                                                  ? (widget.playerNames[widget.user.id] ?? LocaleScope.t(context, 'memory_score_player_fallback'))
                                                  : (widget.playerNames[partnerId] ?? LocaleScope.t(context, 'memory_score_player_fallback'))),
                                          fromBelow: _state.tableOwnerUserId == widget.user.id,
                                          canCapture: canRespond,
                                          onCapture: _tapCapture,
                                        ),
                            ),
                          ),
                          if (!_state.finished)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                              child: Align(
                                alignment: Alignment.centerRight,
                                // Voir demande utilisateur : "tu peux déplacer
                                // le bouton de tri directement au-dessus de
                                // la main" — juste au-dessus de la zone de
                                // main, plus dans l'AppBar.
                                child: TextButton.icon(
                                  onPressed: _toggleHandSorted,
                                  icon: Icon(_handSorted ? Icons.view_agenda_rounded : Icons.sort_rounded, size: 18),
                                  label: Text(_handSorted ? 'Vue normale' : 'Trier mes cartes'),
                                  style: TextButton.styleFrom(foregroundColor: theme.textOnBackgroundMuted, padding: EdgeInsets.zero),
                                ),
                              ),
                            ),
                          Padding(
                            // Voir demande utilisateur : "faire remonter les
                            // cartes d'en bas pour éviter que les icônes
                            // micro... cachent les cartes" — VoiceCallOverlay/
                            // NearbyVoiceOverlay/GameCommentOverlay flottent
                            // en Positioned(bottom: 24, ...) par-dessus tout
                            // l'écran (voir plus bas dans ce build()) ; sans
                            // marge dédiée, ils recouvraient le bas de cette
                            // main, la seule interactive.
                            padding: EdgeInsets.fromLTRB(12, 4, 12, (_isRemoteSession || widget.nearbyComms != null) ? 84 : 10),
                            child: _handSorted
                                ? _SortedHandStrip(
                                    cards: _state.mySpread,
                                    interactive: canLead || canRespond,
                                    onTapCard: _tapSortedCard,
                                  )
                                : AnimatedBuilder(
                                    animation: _rejectController,
                                    builder: (context, _) => _HandFan(
                                      cards: _state.mySpread,
                                      color: myColor,
                                      interactive: canLead || canRespond,
                                      faceUp: true,
                                      rejectingIndex: _rejectingIndex,
                                      rejectProgress: _rejectController.value,
                                      onTapCard: _tapMyCard,
                                      excludeIndex: _guidePlayedIndex,
                                      guideIndex: _state.mySpread.isEmpty ? null : 0,
                                      guideKey: _guideStep == _SuitBattleGuideStep.hand ? _handGuideKey : null,
                                      onGuideTap: _onGuideHandTap,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                      // Pile de gains COMMUNE (voir demande utilisateur :
                      // "une seule pile" — la répartition entre les deux
                      // joueurs ne compte pas pour gagner la partie, voir
                      // SuitBattleEngine, seul vide sa main en premier
                      // importe) — un seul compteur, centré en haut, plutôt
                      // que deux badges séparés dans les coins.
                      Positioned(
                        top: 4,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: _WonPileBadge(color: theme.primary, count: _state.myWonPile.length + _state.partnerWonPile.length),
                        ),
                      ),
                      // "Balayer" tapé (voir demande utilisateur : "on doit
                      // voir les cartes se réunir et aller se ranger en
                      // haut") — les deux cartes (instantané pris au tap,
                      // voir _tapSweep) convergent vers la pile commune,
                      // centrée en haut, puis s'estompent. Positioned AU
                      // NIVEAU DU STACK ENTIER (pas dans la zone centrale)
                      // pour pouvoir voyager jusqu'en haut de l'écran.
                      if (_collecting)
                        Positioned.fill(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: 1),
                            duration: const Duration(milliseconds: 520),
                            curve: Curves.easeInCubic,
                            builder: (context, t, child) {
                              // Voir demande utilisateur : "Capturer" ->
                              // vers ma main (bas), "Balayer" -> vers la
                              // pile commune (haut) — voir _collectingToHand.
                              final target = _collectingToHand ? const Alignment(0, 0.92) : const Alignment(0, -0.92);
                              const start = Alignment(0, -0.05);
                              final align = Alignment.lerp(start, target, t)!;
                              return Align(
                                alignment: align,
                                child: Opacity(
                                  opacity: 1 - t * 0.85,
                                  child: Transform.scale(scale: 1 - t * 0.55, child: child),
                                ),
                              );
                            },
                            child: _CollectingCardsPair(cardA: _collectingMyCard, cardB: _collectingPartnerCard),
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
          // fin de la manche (plus de `!_state.finished` ici) jusqu'à ce
          // qu'on quitte vraiment (voir _showScoreboard) — et la feuille de
          // score, qui s'affiche PAR-DESSUS, ne doit ni les cacher ni
          // empêcher d'y toucher (voir AlwaysOnTopLayer).
          AlwaysOnTopLayer(
            child: commentsBoxId != null
                ? VoiceCallOverlay(
                    boxId: commentsBoxId,
                    myUserId: widget.user.id,
                    partnerUserId: partnerId,
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
                        partnerUserId: partnerId,
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
            sessionType: 'suit_battle',
            sessionId: _sessionId,
          ),
        ],
      ),
    );
  }
}

/// Bandeau court rappelant à qui le tour et quelle phase — "Jeu de Carte
/// Classique" n'ayant ni bouton "Retourner" ni animation de duel, ce
/// repère textuel est la seule indication explicite de ce qu'il reste à
/// faire (voir demande utilisateur : jouer une carte, répondre, ou
/// capturer).
class _TurnBanner extends StatelessWidget {
  final ThemePalette theme;
  final SuitBattleBoardState state;
  final String partnerName;

  const _TurnBanner({required this.theme, required this.state, required this.partnerName});

  @override
  Widget build(BuildContext context) {
    if (state.finished) return const SizedBox.shrink();

    final String label;
    // Voir demande utilisateur : phase "reveal" — l'échange est déjà
    // tranché, plus personne ne "joue" ou "répond", il reste juste à
    // balayer (voir _DuelRevealArea) avant de continuer.
    if (state.isRevealing) {
      label = 'Balayez pour continuer';
    } else if (state.isMyTurn) {
      label = state.phase == 'lead' ? 'À toi de jouer une carte' : 'À toi de répondre (ou capturer)';
    } else {
      label = state.phase == 'lead' ? '$partnerName pose une carte…' : '$partnerName répond…';
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: (state.isMyTurn ? theme.primary : theme.textOnBackgroundMuted).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: GoogleFonts.nunito(fontSize: 12.5, fontWeight: FontWeight.w700, color: state.isMyTurn ? theme.primary : theme.textOnBackgroundMuted),
      ),
    );
  }
}

/// La zone centrale de la table — la carte du meneur (le cas échéant) et
/// le bouton "Capturer" (voir demande utilisateur : visible UNIQUEMENT
/// quand c'est mon tour ET qu'on est en phase "response").
class _TableArea extends StatelessWidget {
  final ThemePalette theme;
  final String? tableCard;
  // Voir demande utilisateur : "ajouter aussi les prénoms de chacun à
  // côté de sa carte" — `null` tant qu'aucune carte n'est encore posée.
  final String? tableCardName;
  // Sens d'arrivée de l'animation (voir _DuelCardEntry) : vrai si c'est
  // MOI qui ai posé cette carte (monte depuis ma main, en bas), faux si
  // c'est le binôme (descend depuis la sienne, en haut).
  final bool fromBelow;
  final bool canCapture;
  final VoidCallback onCapture;

  const _TableArea({
    required this.theme,
    required this.tableCard,
    required this.tableCardName,
    required this.fromBelow,
    required this.canCapture,
    required this.onCapture,
  });

  @override
  Widget build(BuildContext context) {
    final card = tableCard;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: _kTableCardWidth,
          height: _kTableCardHeight,
          // Voir demande utilisateur : "on doit voir la carte se déplacer
          // pour le centre" — animation d'entrée dès que le meneur pose sa
          // carte, même mécanisme que la phase "reveal" (voir
          // _DuelCardEntry).
          child: card == null
              ? DottedTablePlaceholder(theme: theme)
              : _DuelCardEntry(
                  key: ValueKey(card),
                  fromBelow: fromBelow,
                  child: PlayingCardFace(
                    card: card,
                    isJoker: SuitBattleEngine.isJoker(card),
                    width: _kTableCardWidth,
                    height: _kTableCardHeight,
                  ),
                ),
        ),
        if (tableCardName != null) ...[
          const SizedBox(height: 4),
          Text(
            tableCardName!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.nunito(fontSize: 11.5, fontWeight: FontWeight.w700, color: theme.textOnBackgroundMuted),
          ),
        ],
        if (canCapture) ...[
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onCapture,
            icon: const Icon(Icons.front_hand_rounded),
            label: const Text('Capturer'),
            style: FilledButton.styleFrom(backgroundColor: theme.primary, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
          ),
        ],
      ],
    );
  }
}

/// Phase "reveal" (voir demande utilisateur : "les deux cartes sorties se
/// disposent côte à côte pour qu'on puisse lire... couronne au-dessus de
/// la carte la plus forte... bouton Balayer en bas pour ressortir les
/// prochaines cartes") — [myCard]/[partnerCard] restent posées jusqu'au
/// balayage explicite, jamais fusionnées automatiquement.
class _DuelRevealArea extends StatelessWidget {
  final String? myCard;
  final String? partnerCard;
  final bool myCardWins;
  final String myName;
  final String partnerName;
  final VoidCallback onSweep;

  const _DuelRevealArea({
    required this.myCard,
    required this.partnerCard,
    required this.myCardWins,
    required this.myName,
    required this.partnerName,
    required this.onSweep,
  });

  // Voir demande utilisateur : "ajouter aussi les prénoms de chacun à
  // côté de sa carte pour savoir quelle carte chacun a sorti" — [fromBelow]
  // distingue le SENS d'arrivée (voir _DuelCardEntry) : ma carte vient de
  // ma main, EN BAS de l'écran, celle du binôme de la sienne, EN HAUT.
  Widget _slot(String? card, bool crowned, String name, bool fromBelow) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 22,
          child: crowned ? Icon(Icons.emoji_events_rounded, color: Colors.amber.shade700, size: 22) : null,
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: _kTableCardWidth,
          height: _kTableCardHeight,
          child: card == null
              ? null
              : _DuelCardEntry(
                  key: ValueKey(card),
                  fromBelow: fromBelow,
                  child: PlayingCardFace(card: card, isJoker: SuitBattleEngine.isJoker(card), width: _kTableCardWidth, height: _kTableCardHeight),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.nunito(fontSize: 11.5, fontWeight: FontWeight.w700, color: crowned ? Colors.amber.shade800 : null),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _slot(partnerCard, !myCardWins, partnerName, false),
            const SizedBox(width: 18),
            _slot(myCard, myCardWins, myName, true),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onSweep,
          icon: const Icon(Icons.cleaning_services_rounded),
          label: const Text('Balayer'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
        ),
      ],
    );
  }
}

/// Anime l'entrée d'une carte de duel — monte depuis la main du joueur
/// (voir demande utilisateur : "on doit voir la carte se déplacer pour le
/// centre"), même principe que _WarCardStackEntry dans
/// war_card_board_screen.dart.
class _DuelCardEntry extends StatelessWidget {
  final Widget child;
  // Voir demande utilisateur : "mon œil ne perçoit pas la carte se
  // déplacer" — trajet nettement plus long (depuis la main réelle du
  // joueur : en bas pour moi, en haut pour le binôme) et plus lent, pour
  // que le mouvement soit sans ambiguïté visible.
  final bool fromBelow;

  const _DuelCardEntry({super.key, required this.child, required this.fromBelow});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, (1 - t) * (fromBelow ? 160 : -160)),
        child: Opacity(opacity: t, child: Transform.scale(scale: 0.85 + 0.15 * t, child: child)),
      ),
      child: child,
    );
  }
}

/// Les deux cartes du dernier échange balayé, légèrement décalées l'une
/// sur l'autre (voir demande utilisateur : "on doit voir les cartes se
/// réunir") — utilisé UNIQUEMENT par l'animation de balayage ci-dessus,
/// jamais affiché statiquement.
class _CollectingCardsPair extends StatelessWidget {
  final String? cardA;
  final String? cardB;

  const _CollectingCardsPair({required this.cardA, required this.cardB});

  @override
  Widget build(BuildContext context) {
    const width = _kTableCardWidth * 0.7;
    const height = _kTableCardHeight * 0.7;
    const offset = 10.0;
    return SizedBox(
      width: width + offset,
      height: height + offset,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (cardA != null)
            Positioned(
              left: 0,
              top: 0,
              child: PlayingCardFace(card: cardA!, isJoker: SuitBattleEngine.isJoker(cardA!), width: width, height: height),
            ),
          if (cardB != null)
            Positioned(
              left: offset,
              top: offset,
              child: PlayingCardFace(card: cardB!, isJoker: SuitBattleEngine.isJoker(cardB!), width: width, height: height),
            ),
        ],
      ),
    );
  }
}

/// Emplacement vide de la table, tant qu'aucune carte n'y a encore été
/// posée (avant le tout premier coup de la partie).
class DottedTablePlaceholder extends StatelessWidget {
  final ThemePalette theme;

  const DottedTablePlaceholder({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.textOnBackgroundMuted.withValues(alpha: 0.3), width: 1.4),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.style_outlined, color: theme.textOnBackgroundMuted.withValues(alpha: 0.4), size: 28),
    );
  }
}

/// Compteur de la pile de gains, en coin d'écran (voir demande
/// utilisateur : "un petit indicateur... épinglé dans le coin
/// supérieur-droit") — quelques dos de carte empilés + le nombre total.
class _WonPileBadge extends StatelessWidget {
  final Color color;
  final int count;

  const _WonPileBadge({required this.color, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 26,
            height: 20,
            child: Stack(
              children: [
                Positioned(left: 6, top: 0, child: _MiniCardBack(color: color)),
                Positioned(left: 0, top: 2, child: _MiniCardBack(color: color)),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Text('$count', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

class _MiniCardBack extends StatelessWidget {
  final Color color;

  const _MiniCardBack({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 20,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 1),
      ),
    );
  }
}

/// Une main en éventail, défilable horizontalement (voir demande
/// utilisateur : "sa main comme une rangée/wrap de cartes tapables") —
/// reprend le principe de chevauchement/rotation de _WarCardFanSheet, ici
/// utilisé directement sur le plateau plutôt que dans une feuille à part.
/// Non interactive pour la main du binôme (voir doc de classe :
/// [interactive] = false) — voir demande utilisateur : "il ne doit pas
/// voir ma pile de cartes mais il peut les voir retourner" — SA main
/// ([faceUp] vrai) reste TOUJOURS face visible, celle du binôme ([faceUp]
/// faux) s'affiche TOUJOURS dos tourné (voir [_CardBack] ci-dessous),
/// qu'elle soit interactive ou non ; une carte JOUÉE reste normalement
/// visible via `tableCard`, jamais affectée par ceci. [faceUp] est
/// délibérément SÉPARÉ de [interactive] : "ce n'est pas mon tour" (donc
/// pile non interactive) ne doit jamais rendre MA propre main invisible
/// (voir demande utilisateur, capture où "mes cartes" — celles interactives
/// à `false` en attente du binôme — se cachaient à tort).
class _HandFan extends StatelessWidget {
  final List<String> cards;
  final Color color;
  final bool interactive;
  final bool faceUp;
  final int? rejectingIndex;
  final double rejectProgress;
  final void Function(int index, String card)? onTapCard;
  // Guide pas-à-pas (voir demande utilisateur : "guider le user vers
  // quelque action pour qu'il comprenne le mécanisme") — [excludeIndex]
  // masque la carte "jouée" par la démo (voir
  // _SuitBattleBoardScreenState._onGuideHandTap, jamais un vrai
  // widget.transport) ; [guideIndex]/[guideKey]/[onGuideTap] désignent LA
  // carte que le guide fait taper, indépendamment de [interactive]
  // (toujours faux pendant le guide, partie en pause).
  final int? excludeIndex;
  final int? guideIndex;
  final GlobalKey? guideKey;
  final void Function(int index, String card)? onGuideTap;

  const _HandFan({
    required this.cards,
    required this.color,
    required this.interactive,
    required this.faceUp,
    required this.rejectingIndex,
    this.rejectProgress = 0,
    required this.onTapCard,
    this.excludeIndex,
    this.guideIndex,
    this.guideKey,
    this.onGuideTap,
  });

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return SizedBox(height: _kHandCardHeight, child: Center(child: Icon(Icons.check_circle_outline_rounded, color: color.withValues(alpha: 0.4))));
    }

    return SizedBox(
      height: _kHandCardHeight + 12,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: cards.length,
        itemBuilder: (context, index) {
          if (index == excludeIndex) return const SizedBox.shrink();
          final card = cards[index];
          final shaking = rejectingIndex == index;
          final shakeOffset = shaking ? math.sin(rejectProgress * math.pi * 6) * 6 * (1 - rejectProgress) : 0.0;
          final isGuideTarget = index == guideIndex && guideKey != null;

          // Main du binôme (voir demande utilisateur : "il ne doit pas voir
          // ma pile de cartes mais il peut les voir retourner") — dos de
          // carte, jamais la face, tant qu'elle reste en main ; seule LA
          // MIENNE ([faceUp] vrai pour moi, TOUJOURS — indépendant de
          // [interactive], voir doc de classe) est face visible. Une carte
          // JOUÉE reste visible normalement via `tableCard`, jamais
          // affectée par ceci.
          // Voir demande utilisateur : "si on ne balaie pas et on clique
          // pour sortir, afficher une petite info" — le tap doit rester
          // reçu même hors tour/hors phase jouable pour que _tapMyCard
          // puisse distinguer "pas mon tour" (silencieux) de "phase reveal
          // en cours" (message d'info) ; [interactive] ne pilote plus que
          // l'estompage visuel ci-dessous.
          final cardTile = GestureDetector(
            onTap: isGuideTarget ? () => onGuideTap?.call(index, card) : (onTapCard != null ? () => onTapCard!(index, card) : null),
            child: Opacity(
              opacity: interactive ? 1 : 0.92,
              child: faceUp
                  ? PlayingCardFace(
                      card: card,
                      isJoker: SuitBattleEngine.isJoker(card),
                      width: _kHandCardWidth,
                      height: _kHandCardHeight,
                    )
                  : _CardBack(color: color, width: _kHandCardWidth, height: _kHandCardHeight),
            ),
          );

          return Padding(
            padding: EdgeInsets.only(left: index == 0 ? 0 : 22, top: 6),
            child: Transform.translate(
              offset: Offset(shakeOffset, 0),
              child: isGuideTarget
                  ? Showcase(
                      key: guideKey!,
                      title: 'Tape cette carte',
                      description: 'Tape ici pour la jouer.',
                      targetBorderRadius: BorderRadius.circular(8),
                      disableDefaultTargetGestures: true,
                      child: cardTile,
                    )
                  : cardTile,
            ),
          );
        },
      ),
    );
  }
}

/// Disposition en colonnes de la main (voir demande utilisateur :
/// "réorganise les cartes de façon groupée par même symbole et même
/// couleur et du plus petit nombre au plus grand... les jokers ont leur
/// propre groupe de leur côté") — une colonne par couleur (♠♥♦♣, dans cet
/// ordre) + une colonne dédiée aux Jokers à la fin, cartes empilées
/// verticalement en éventail, triées du plus petit rang au plus grand.
/// En feuille modale plutôt que dans la rangée compacte du bas : une
/// colonne peut compter jusqu'à 13 cartes, largement plus que la hauteur
/// disponible dans la barre de main habituelle.
/// Voir demande utilisateur : "on n'utilise pas de modèle. on dispose et
/// le reste peut déborder descendre... je peux défiler sur le lot
/// concerné... on clique la carte que l'on veut et elle sort si elle
/// remplit les conditions" — affichage EN PLACE (jamais par-dessus le
/// plateau) de la main groupée par même symbole/couleur, triée du plus
/// petit au plus grand, Jokers dans leur propre groupe ; chaque groupe
/// défile verticalement s'il dépasse la hauteur disponible, l'ensemble
/// défile horizontalement.
class _SortedHandStrip extends StatelessWidget {
  final List<String> cards;
  final bool interactive;
  final void Function(String card) onTapCard;

  const _SortedHandStrip({
    required this.cards,
    required this.interactive,
    required this.onTapCard,
  });

  static const _suitOrder = ['S', 'H', 'D', 'C'];
  static const _suitSymbols = {'S': '♠', 'H': '♥', 'D': '♦', 'C': '♣'};

  static const _cardWidth = 50.0;
  static const _cardHeight = 70.0;
  static const _overlap = 22.0;
  // Voir demande utilisateur : le tri s'affiche EN PLACE, dans le même
  // espace que l'éventail normal (_kHandCardHeight + 12 = 92) — jamais
  // plus haut, sinon ça déborde sur les icônes micro/caméra du bas
  // (bug observé par l'utilisateur en test).
  static const _stripHeight = _kHandCardHeight + 12;

  Widget _column(ThemePalette theme, String label, Color labelColor, List<String> group) {
    if (group.isEmpty) return const SizedBox.shrink();
    final stackHeight = _cardHeight + (group.length - 1) * _overlap;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      // Hauteur FIXE garantie (voir demande utilisateur : "ça déborde") —
      // Expanded prend exactement l'espace restant sous le label, quelle
      // que soit sa hauteur réelle de rendu, au lieu d'une soustraction
      // approximative qui débordait selon la police/densité d'affichage.
      child: SizedBox(
        height: _stripHeight,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 12, color: labelColor)),
            const SizedBox(height: 2),
            Expanded(
              child: SingleChildScrollView(
                child: SizedBox(
                  width: _cardWidth,
                  height: stackHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (var i = 0; i < group.length; i++)
                        Positioned(
                          top: i * _overlap,
                          child: Opacity(
                            opacity: interactive ? 1 : 0.6,
                            // Tap reçu même hors tour/hors phase jouable
                            // (même principe que _HandFan) : _tapSortedCard
                            // affiche alors le message d'info ("pas ton
                            // tour", "balaie d'abord"...) ; [interactive] ne
                            // pilote que l'estompage.
                            child: GestureDetector(
                              onTap: () => onTapCard(group[i]),
                              child: PlayingCardFace(
                                card: group[i],
                                isJoker: SuitBattleEngine.isJoker(group[i]),
                                width: _cardWidth,
                                height: _cardHeight,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final jokers = cards.where(SuitBattleEngine.isJoker).toList();
    final bySuit = {for (final s in _suitOrder) s: <String>[]};
    for (final card in cards) {
      if (SuitBattleEngine.isJoker(card)) continue;
      bySuit[SuitBattleEngine.suitOf(card)]?.add(card);
    }
    for (final group in bySuit.values) {
      group.sort((a, b) => SuitBattleEngine.rankValue(a).compareTo(SuitBattleEngine.rankValue(b)));
    }

    return SizedBox(
      height: _stripHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final suit in _suitOrder)
              _column(theme, _suitSymbols[suit]!, suit == 'H' || suit == 'D' ? _kRedColor : Colors.black87, bySuit[suit]!),
            _column(theme, 'JOK', kPlayingCardJokerColor, jokers),
          ],
        ),
      ),
    );
  }
}

/// Score de fin de partie — copie structurelle de
/// _WarCardScoreboardSheet, mais le "score" affiché est le nombre de
/// cartes RESTANT en main (voir _leftFor), pas la taille d'une pile.
class _SuitBattleScoreboardSheet extends StatelessWidget {
  final SuitBattleBoardState state;
  final Map<String, String> playerNames;
  final Map<String, String?> playerAvatars;
  final Color Function(String userId) colorFor;
  final bool allowRematch;

  const _SuitBattleScoreboardSheet({
    required this.state,
    required this.playerNames,
    required this.playerAvatars,
    required this.colorFor,
    required this.allowRematch,
  });

  // Voir demande utilisateur : le score affiché est le nombre de cartes
  // RESTANT en main — le moins gagne, même nombre = match nul.
  int _leftFor(String userId) => userId == state.creatorId ? state.spreadCreator.length : state.spreadPartner.length;

  /// Gagnant déclaré par le moteur/serveur, sinon déduit des cartes
  /// restantes — l'écran de l'invité en présentiel peut s'ouvrir sur son
  /// propre état "abandonné" avant que l'hôte n'ait diffusé le résultat.
  String? get _winnerId {
    if (state.winnerUserId != null || state.isTie) return state.winnerUserId;
    final creatorLeft = _leftFor(state.creatorId);
    final partnerLeft = _leftFor(state.partnerId);
    if (creatorLeft == partnerLeft) return null;
    return creatorLeft < partnerLeft ? state.creatorId : state.partnerId;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final players = playerNames.keys.toList();

    final minutes = state.startedAt != null ? ServerClock.instance.now().difference(state.startedAt!).inSeconds ~/ 60 : 0;
    final seconds = state.startedAt != null ? ServerClock.instance.now().difference(state.startedAt!).inSeconds % 60 : 0;

    final winnerId = _winnerId;
    final effectiveTie = state.isTie || winnerId == null;

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
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(false),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, color: theme.textOnBackgroundMuted, size: 22),
                ),
              ),
            ),
            const SizedBox(height: 6),
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
            const SizedBox(height: 18),
            Icon(effectiveTie ? Icons.handshake_rounded : Icons.emoji_events_rounded, size: 40, color: theme.primary),
            const SizedBox(height: 10),
            Text(
              effectiveTie
                  ? 'Égalité !'
                  : '${playerNames[winnerId] ??LocaleScope.t(context, 'memory_score_player_fallback')} a gagné !',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w800, color: theme.textOnBackground),
            ),
            const SizedBox(height: 4),
            Text(
              'Manche ${state.roundsCount}  ·  $minutes:${seconds.toString().padLeft(2, '0')}',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
            ),
            const SizedBox(height: 20),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < players.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(
                      child: _PlayerResultCard(
                        theme: theme,
                        name: playerNames[players[i]] ?? LocaleScope.t(context, 'memory_score_player_fallback'),
                        avatar: playerAvatars[players[i]],
                        color: colorFor(players[i]),
                        cardCount: _leftFor(players[i]),
                        isWinner: players[i] == winnerId,
                        isTie: effectiveTie,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (allowRematch) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.replay_rounded),
                label: Text(LocaleScope.t(context, 'memory_score_rematch')),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ],
            // "Quitter" : referme le jeu et ramène au choix de la difficulté (voir demande
            // utilisateur) — taper à côté de la feuille revient au même (résultat null).
            SizedBox(height: allowRematch ? 10 : 20),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: Text(LocaleScope.t(context, 'game_score_quit')),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerResultCard extends StatelessWidget {
  final ThemePalette theme;
  final String name;
  final String? avatar;
  final Color color;
  final int cardCount;
  final bool isWinner;
  final bool isTie;

  const _PlayerResultCard({
    required this.theme,
    required this.name,
    required this.avatar,
    required this.color,
    required this.cardCount,
    required this.isWinner,
    required this.isTie,
  });

  @override
  Widget build(BuildContext context) {
    final highlighted = isWinner || isTie;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highlighted ? color.withValues(alpha: 0.45) : color.withValues(alpha: 0.15),
          width: highlighted ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: color.withValues(alpha: 0.16),
                backgroundImage: (avatar != null && avatar!.isNotEmpty) ? NetworkImage(avatar!) : null,
                child: (avatar == null || avatar!.isEmpty)
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: color, fontSize: 18),
                      )
                    : null,
              ),
              if (isWinner)
                Positioned(
                  top: -6,
                  right: 6,
                  child: Icon(Icons.emoji_events_rounded, size: 18, color: color),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: theme.textOnBackground),
          ),
          const SizedBox(height: 6),
          Text(
            '$cardCount',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: color),
          ),
          Text(
            cardCount > 1 ? 'cartes restantes' : 'carte restante',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(fontSize: 10, color: theme.textOnBackgroundMuted),
          ),
          const SizedBox(height: 4),
          Text(
            isTie
                ? LocaleScope.t(context, 'dot_squares_score_tie_short')
                : (isWinner ? LocaleScope.t(context, 'ttt_score_won') : LocaleScope.t(context, 'ttt_score_lost')),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}

/// Phase "avant partie" : le paquet complet est visible empilé, "Battre"
/// le remélange réellement autant de fois qu'on veut, "Distribuer" coupe
/// instantanément les deux éventails de 27 — pas de partage manuel pour ce
/// jeu (contrairement à "Bataille", voir demande utilisateur : seulement
/// shuffle + deal-auto côté backend).
class _SuitBattlePreDealScreen extends StatefulWidget {
  final Game game;
  final ThemePalette theme;
  final SuitBattleBoardState state;
  final Map<String, String> playerNames;
  final Color Function(String userId) colorFor;
  final Future<void> Function() onShuffle;
  final Future<void> Function() onDealAutomatic;

  const _SuitBattlePreDealScreen({
    required this.game,
    required this.theme,
    required this.state,
    required this.playerNames,
    required this.colorFor,
    required this.onShuffle,
    required this.onDealAutomatic,
  });

  @override
  State<_SuitBattlePreDealScreen> createState() => _SuitBattlePreDealScreenState();
}

class _SuitBattlePreDealScreenState extends State<_SuitBattlePreDealScreen> with SingleTickerProviderStateMixin {
  bool _busy = false;
  late final AnimationController _shuffleController;

  @override
  void initState() {
    super.initState();
    _shuffleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  }

  @override
  void dispose() {
    _shuffleController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final deck = widget.state.deck;

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
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Le paquet est prêt',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: theme.textOnBackground),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Battez les cartes puis distribuez deux éventails de 27 cartes',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                        ),
                        const SizedBox(height: 28),
                        AnimatedBuilder(
                          animation: _shuffleController,
                          builder: (context, child) {
                            final shake = math.sin(_shuffleController.value * math.pi * 6) * 6 * (1 - _shuffleController.value);
                            return Transform.translate(offset: Offset(shake, 0), child: child);
                          },
                          child: _SuitBattleFullStack(count: deck.length, color: theme.primary),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${deck.length} cartes',
                          style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w800, color: theme.primary),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(widget.onShuffle, animateShuffle: true),
                    icon: const Icon(Icons.shuffle_rounded),
                    label: const Text('Battre les cartes'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _run(widget.onDealAutomatic),
                    icon: const Icon(Icons.flash_on_rounded),
                    label: const Text('Distribuer'),
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

/// Le paquet complet, empilé — même approche que _WarCardFullStack (dos de
/// cartes décalés pour suggérer l'épaisseur, sans dessiner littéralement
/// les 54 widgets).
class _SuitBattleFullStack extends StatelessWidget {
  final int count;
  final Color color;

  const _SuitBattleFullStack({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    final depth = count <= 0 ? 0 : (count >= 54 ? 6 : (1 + (count * 5 / 54)).round());

    return SizedBox(
      width: _kTableCardWidth + depth * 2.5,
      height: _kTableCardHeight + depth * 2.5,
      child: Stack(
        children: [
          for (var i = depth; i >= 1; i--)
            Positioned(
              right: (depth - i) * 2.5,
              top: (depth - i) * 2.5,
              child: _CardBack(color: color, dimmed: i > 1),
            ),
          Positioned(left: 0, bottom: 0, child: _CardBack(color: color)),
        ],
      ),
    );
  }
}

class _CardBack extends StatelessWidget {
  final Color color;
  final bool dimmed;
  final double width;
  final double height;

  const _CardBack({required this.color, this.dimmed = false, this.width = _kTableCardWidth, this.height = _kTableCardHeight});

  @override
  Widget build(BuildContext context) {
    final backColor = dimmed ? color.withValues(alpha: 0.35) : color;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: backColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
        boxShadow: dimmed ? null : const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
      ),
      alignment: Alignment.center,
      child: dimmed ? null : Icon(Icons.style_rounded, color: Colors.white.withValues(alpha: 0.55), size: width * 0.34),
    );
  }
}

/// Phase "prêt ?" — une fois les deux éventails distribués, un bouton
/// "Commencer" apparaît ; LES DEUX doivent taper avant que la partie ne
/// démarre réellement (voir SuitBattleEngine.readyUp) — copie structurelle
/// de _WarCardReadyScreen.
class _SuitBattleReadyScreen extends StatefulWidget {
  final Game game;
  final ThemePalette theme;
  final SuitBattleBoardState state;
  final Map<String, String> playerNames;
  final Color Function(String userId) colorFor;
  final Future<void> Function() onReadyUp;

  const _SuitBattleReadyScreen({
    required this.game,
    required this.theme,
    required this.state,
    required this.playerNames,
    required this.colorFor,
    required this.onReadyUp,
  });

  @override
  State<_SuitBattleReadyScreen> createState() => _SuitBattleReadyScreenState();
}

class _SuitBattleReadyScreenState extends State<_SuitBattleReadyScreen> with SingleTickerProviderStateMixin {
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
                        _HandCountBadge(
                          color: widget.colorFor(state.creatorId),
                          label: widget.playerNames[state.creatorId] ?? '',
                          count: state.spreadCreator.length,
                        ),
                        const SizedBox(width: 24),
                        _HandCountBadge(
                          color: widget.colorFor(state.partnerId),
                          label: widget.playerNames[state.partnerId] ?? '',
                          count: state.spreadPartner.length,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Prêt·e à jouer ?',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: theme.textOnBackground),
                ),
                const SizedBox(height: 6),
                Text(
                  state.iAmReady
                      ? 'En attente de $partnerName…'
                      : (state.partnerIsReady ? '$partnerName est prêt·e → à toi !' : 'Chacun sa main, à vous de jouer'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: (_busy || state.iAmReady) ? null : _tapReady,
                    icon: state.iAmReady
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.play_circle_fill_rounded),
                    label: const Text('Commencer'),
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

class _HandCountBadge extends StatelessWidget {
  final Color color;
  final String label;
  final int count;

  const _HandCountBadge({required this.color, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 8),
        _CardBack(color: color),
        const SizedBox(height: 6),
        Text('$count', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}
