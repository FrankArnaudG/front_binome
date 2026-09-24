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
import '../../../theme/theme_scope.dart';
import '../../../theme/themed_background.dart';
import '../game_guide_storage.dart';
import '../game_service.dart';
import '../nearby/nearby_comms.dart';
import '../widgets/battleship_match_scoreboard.dart';
import '../widgets/coin_billing_ring.dart';
import '../widgets/game_comment_overlay.dart';
import '../widgets/game_guide_voice_demo.dart';
import '../widgets/game_wallet_guard.dart';
import '../widgets/nearby_voice_overlay.dart';
import '../widgets/voice_call_overlay.dart';
import '../../shop/wallet_balance_notifier.dart';
import 'battleship_transport.dart';
import 'battleship_transport_local.dart';
import 'battleship_transport_remote.dart';

/// Étapes du guide pas-à-pas du plateau (voir doc de _BoardGuideStep dans
/// memory_game_board_screen.dart pour le principe général) — une bulle
/// sur chacune des deux grilles (celle où l'on tire, celle de sa propre
/// flotte), proportionné à ce jeu (voir demande utilisateur).
enum _BattleshipGuideStep {
  turn,
  fireTap,
  fireResult,
  myGrid,
  coins,
  pause,
  chat,
  micJoin,
  micReady,
  cameraReady,
}

const _kShipColor = Color(0xFF2F6FED);
const _kHitColor = Color(0xFFE5484D);
const _kMissColor = Color(0xFF9AA5B1);

/// Plateau de combat de "Bataille Navale" — UNIQUE écran partagé par les
/// 3 modes (voir BattleshipTransport). Montre DEUX grilles : "ma flotte"
/// (lecture seule, mes bateaux + ce que l'adversaire y a touché) et "sa
/// grille" (mes tirs déjà joués + zone tappable pour en jouer un nouveau).
///
/// En pass-and-play (voir [LocalBattleshipTransport]), quand ce n'est pas
/// au tour de la personne actuellement affichée (`!state.isMyTurn`), un
/// écran "passe le téléphone" masque tout le plateau — jamais les deux
/// grilles visibles par la mauvaise personne.
class BattleshipBoardScreen extends StatefulWidget {
  final Game game;
  final AppUser user;
  final BattleshipTransport transport;
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

  const BattleshipBoardScreen({
    super.key,
    required this.game,
    required this.user,
    required this.transport,
    required this.playerNames,
    required this.playerAvatars,
    this.nearbyComms,
    this.nearbyMyName,
    this.nearbyPartnerName,
    this.onRematch,
    this.isLauncher = true,
    this.onQuit,
  });

  @override
  State<BattleshipBoardScreen> createState() => _BattleshipBoardScreenState();
}

class _BattleshipBoardScreenState extends State<BattleshipBoardScreen> {
  late StreamSubscription<BattleshipBoardState> _subscription;
  late BattleshipBoardState _state;
  Timer? _clockTimer;
  bool _scoreboardShown = false;
  // Instant de fin de partie vu par CET appareil : fige chrono et pièces.
  DateTime? _finishedAt;
  // Réglage admin (minutes_per_coin/grace_period_seconds) pour l'anneau de
  // progression coté pièce (voir CoinBillingRing/demande utilisateur) —
  // chargé une seule fois, uniquement utile en mode à distance.
  Map<String, int>? _economyRate;

  bool get _isLocalPassAndPlay => widget.transport is LocalBattleshipTransport;

  // Guide pas-à-pas (voir doc de classe de _BattleshipGuideStep et
  // demande utilisateur : "prends le même soin pour les autres jeux").
  final _turnGuideKey = GlobalKey();
  final _opponentGridGuideKey = GlobalKey();
  final _myGridGuideKey = GlobalKey();
  final _coinsGuideKey = GlobalKey();
  final _pauseGuideKey = GlobalKey();
  final _chatGuideKey = GlobalKey();
  final _micGuideKey = GlobalKey();
  final _cameraGuideKey = GlobalKey();
  static const _boardGuideKey = 'battleship_board';
  _BattleshipGuideStep? _guideStep;
  bool _guideMicConnecting = false;
  // Démo "tire sur une case" du guide (voir demande utilisateur : "guider
  // le user vers quelque action pour qu'il comprenne le mécanisme") — une
  // VRAIE case jamais encore tirée (voir _pickGuideFireCell), marquée
  // localement comme touchée au tap (voir _onGuideFireTap), jamais
  // widget.transport.fire().
  int? _guideFireCell;
  bool? _guideFireHit;

  @override
  void initState() {
    super.initState();
    _state = widget.transport.currentState;
    if (_state.finished) _finishedAt = ServerClock.instance.now();
    _subscription = widget.transport.stateStream.listen(_onState);
    ShowcaseView.get().addOnCompleteCallback(_onGuideStepTapped);
    ShowcaseView.get().addOnDismissCallback(_onGuideDismissed);
    _maybeStartGuide();
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
  bool get _guideAvailable => widget.transport is LocalBattleshipTransport;

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
    _startGuideStep(_BattleshipGuideStep.turn);
  }

  /// Indice de la première case RÉELLE jamais encore tirée sur la grille
  /// de l'adversaire — `null` si toutes les cases ont déjà été tirées.
  int? _pickGuideFireCell() {
    final tried = {for (final s in _state.myShots) s.cell};
    for (var cell = 0; cell < _state.gridSize * _state.gridSize; cell++) {
      if (!tried.contains(cell)) return cell;
    }
    return null;
  }

  void _startGuideStep(_BattleshipGuideStep step) {
    if (!mounted) return;
    if (step == _BattleshipGuideStep.fireTap) {
      _guideFireHit = null;
      _guideFireCell = _pickGuideFireCell();
      if (_guideFireCell == null) {
        _startGuideStep(_BattleshipGuideStep.myGrid);
        return;
      }
    }
    setState(() {
      _guideStep = step;
      if (step == _BattleshipGuideStep.micReady) _guideMicConnecting = true;
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

  /// Tap RÉEL sur la case désignée par le guide (voir
  /// _OpponentGrid.onGuideTap) — simule un tir réussi en local, jamais
  /// widget.transport.fire().
  void _onGuideFireTap() {
    setState(() => _guideFireHit = true);
    _startGuideStep(_BattleshipGuideStep.fireResult);
  }

  GlobalKey _guideKeyFor(_BattleshipGuideStep step) {
    switch (step) {
      case _BattleshipGuideStep.turn:
        return _turnGuideKey;
      case _BattleshipGuideStep.fireTap:
      case _BattleshipGuideStep.fireResult:
        return _opponentGridGuideKey;
      case _BattleshipGuideStep.myGrid:
        return _myGridGuideKey;
      case _BattleshipGuideStep.coins:
        return _coinsGuideKey;
      case _BattleshipGuideStep.pause:
        return _pauseGuideKey;
      case _BattleshipGuideStep.chat:
        return _chatGuideKey;
      case _BattleshipGuideStep.micJoin:
      case _BattleshipGuideStep.micReady:
        return _micGuideKey;
      case _BattleshipGuideStep.cameraReady:
        return _cameraGuideKey;
    }
  }

  void _onGuideStepTapped(int? index, GlobalKey key) {
    switch (_guideStep) {
      case _BattleshipGuideStep.turn:
        _startGuideStep(_BattleshipGuideStep.fireTap);
        break;
      case _BattleshipGuideStep.fireTap:
        // N'avance PAS ici (gestes de cible désactivés) — seul un vrai
        // tap sur la case désignée fait avancer (voir _onGuideFireTap).
        break;
      case _BattleshipGuideStep.fireResult:
        setState(() {
          _guideFireCell = null;
          _guideFireHit = null;
        });
        _startGuideStep(_BattleshipGuideStep.myGrid);
        break;
      case _BattleshipGuideStep.myGrid:
        _startGuideStep(_BattleshipGuideStep.coins);
        break;
      case _BattleshipGuideStep.coins:
        _startGuideStep(_BattleshipGuideStep.pause);
        break;
      case _BattleshipGuideStep.pause:
        _startGuideStep(_BattleshipGuideStep.chat);
        break;
      case _BattleshipGuideStep.chat:
        _startGuideStep(_BattleshipGuideStep.micJoin);
        break;
      case _BattleshipGuideStep.micJoin:
        _startGuideStep(_BattleshipGuideStep.micReady);
        break;
      case _BattleshipGuideStep.micReady:
        _startGuideStep(_BattleshipGuideStep.cameraReady);
        break;
      case _BattleshipGuideStep.cameraReady:
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
      _guideFireCell = null;
      _guideFireHit = null;
    });
  }

  Widget _buildGuideVoiceDemo() {
    final phase = switch (_guideStep) {
      _BattleshipGuideStep.micJoin => GameGuideVoicePhase.micJoin,
      _BattleshipGuideStep.micReady => GameGuideVoicePhase.micReady,
      _BattleshipGuideStep.cameraReady => GameGuideVoicePhase.cameraReady,
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
    final now = _state.pausedAt ?? _finishedAt ?? ServerClock.instance.now();
    final elapsed = now.difference(started).inSeconds - graceSeconds;
    return elapsed < 0 ? 0 : elapsed.toDouble();
  }

  /// Nombre de pièces consommées depuis le début de CETTE partie — fluide
  /// comme l'anneau (même calcul), voir demande utilisateur.
  double? _coinsConsumed() {
    final elapsed = _elapsedBillableSeconds();
    final cycleSeconds = (_economyRate?['minutes_per_coin'] ?? 8) * 60;
    if (elapsed == null || cycleSeconds <= 0) return 0;
    return elapsed / cycleSeconds;
  }

  /// Fraction (0..1) de progression vers la prochaine pièce déduite —
  /// purement indicatif (voir doc de CoinBillingRing), calculé à partir du
  /// même réglage que le serveur (minutes_per_coin/grace_period_seconds)
  /// mais jamais la source de vérité de la facturation elle-même.
  double _coinProgress() {
    final elapsed = _elapsedBillableSeconds();
    final cycleSeconds = (_economyRate?['minutes_per_coin'] ?? 8) * 60;
    if (elapsed == null || cycleSeconds <= 0) return 0;
    return (elapsed % cycleSeconds) / cycleSeconds;
  }

  void _onState(BattleshipBoardState state) {
    if (!mounted) return;
    setState(() {
      _state = state;
      if (state.finished) _finishedAt ??= ServerClock.instance.now();
    });

    if (state.finished && !_scoreboardShown) {
      _scoreboardShown = true;
      // Voir demande utilisateur : "ça doit être instantané".
      if (_commentsBoxId != null) unawaited(WalletBalanceNotifier.instance.refresh());
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
    final rematch = await showBattleshipMatchScoreboard(
      context,
      state: _state,
      playerNames: widget.playerNames,
      playerAvatars: widget.playerAvatars,
      allowRematch: widget.isLauncher && widget.onRematch != null,
    );
    if (rematch == true && widget.isLauncher && widget.onRematch != null && mounted) {
      await widget.onRematch!(context);
    } else if (mounted) {
      // "Quitter", ou tap à côté de la feuille (voir demande utilisateur) : referme le jeu
      // (retour au choix de la difficulté pour l'invité·e, voir onQuit).
      if (widget.onQuit != null) {
        await widget.onQuit!(context);
      } else {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _onTapOpponentCell(int cell) async {
    if (_state.finished || _state.isPaused || !_state.isMyTurn) return;
    if (_state.myShots.any((s) => s.cell == cell)) return;
    await widget.transport.fire(cell);
  }

  String _elapsed() {
    final started = _state.startedAt;
    if (started == null) return '0:00';
    final now = _state.pausedAt ?? _finishedAt ?? ServerClock.instance.now();
    // Le chrono attend la même période de grâce que l'anneau de pièce
    // (voir CoinBillingRing/demande utilisateur) — reste à 0:00 tant que
    // la grâce n'est pas écoulée, nul en dehors du mode à distance.
    final graceSeconds = _economyRate?['grace_period_seconds'] ?? 0;
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

  String? get _commentsBoxId {
    final transport = widget.transport;
    return transport is RemoteBattleshipTransport ? transport.boxId : null;
  }

  String get _sessionId {
    final transport = widget.transport;
    return transport is RemoteBattleshipTransport ? transport.sessionId : '';
  }

  /// Bouton "Terminer la partie" du popup de solde épuisé (voir
  /// GameWalletGuard) — même geste qu'un abandon volontaire.
  String get _partnerUserId =>
      widget.playerNames.keys.firstWhere((id) => id != widget.user.id, orElse: () => widget.user.id);

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final commentsBoxId = _commentsBoxId;

    // Pass-and-play : masque tout tant que ce n'est pas au tour de la
    // personne actuellement affichée (voir doc de classe).
    if (_isLocalPassAndPlay && !_state.finished && !_state.isMyTurn) {
      final nextName = widget.playerNames[_state.opponentUserId] ?? LocaleScope.t(context, 'memory_score_player_fallback');
      return Scaffold(
        backgroundColor: theme.background,
        body: ThemedBackground(
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.visibility_off_rounded, size: 48, color: theme.primary),
                    const SizedBox(height: 16),
                    Text(
                      LocaleScope.t(context, 'battleship_pass_device_title', {'name': nextName}),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: theme.textOnBackground),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => (widget.transport as LocalBattleshipTransport).setActiveViewer(_state.opponentUserId),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14)),
                      child: Text(LocaleScope.t(context, 'battleship_pass_device_ready')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

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
                      icon: const Icon(Icons.play_circle_outline),
                      tooltip: (_state.pausedByMe || _state.pausedByUserId == null)
                          ? LocaleScope.t(context, 'memory_board_resume_tooltip')
                          : LocaleScope.t(context, 'memory_board_paused_by_partner_tooltip', {
                              'name': widget.playerNames[_state.pausedByUserId] ??
                                  LocaleScope.t(context, 'memory_board_partner_fallback'),
                            }),
                      onPressed: (_state.pausedByMe || _state.pausedByUserId == null) ? () => widget.transport.resume() : null,
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
                          key: _turnGuideKey,
                          title: 'À qui de jouer ?',
                          description: 'Ce texte indique à qui c\'est le tour de tirer.',
                          targetBorderRadius: BorderRadius.circular(8),
                          child: Text(
                            _state.finished
                                ? LocaleScope.t(context, 'game_board_finished_label')
                                : (_state.isMyTurn
                                    ? LocaleScope.t(context, 'memory_board_your_turn')
                                    : LocaleScope.t(context, 'memory_board_partner_turn', {
                                        'name': widget.playerNames[_state.currentTurnUserId] ??
                                            LocaleScope.t(context, 'memory_board_partner_fallback'),
                                      })),
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 15, color: theme.primary),
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
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        children: [
                          Text(
                            LocaleScope.t(context, 'battleship_opponent_grid_label'),
                            style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: theme.textOnBackgroundMuted),
                          ),
                          const SizedBox(height: 6),
                          _OpponentGrid(
                            state: _state,
                            onTapCell: _onTapOpponentCell,
                            guideCell: _guideFireCell,
                            guideHit: _guideFireHit,
                            guideKey: (_guideStep == _BattleshipGuideStep.fireTap ||
                                    _guideStep == _BattleshipGuideStep.fireResult)
                                ? _opponentGridGuideKey
                                : null,
                            onGuideTap: _guideStep == _BattleshipGuideStep.fireTap ? _onGuideFireTap : null,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            LocaleScope.t(context, 'battleship_my_grid_label'),
                            style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: theme.textOnBackgroundMuted),
                          ),
                          const SizedBox(height: 6),
                          Showcase(
                            key: _myGridGuideKey,
                            title: 'Ta flotte',
                            description: "Ici, tu vois tes propres navires et les tirs que ton binôme t'a déjà portés — cette grille n'est pas tapable, elle est juste là pour suivre la partie.",
                            targetBorderRadius: BorderRadius.circular(8),
                            child: _MyGrid(state: _state),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
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
                              onPressed: () => widget.transport.resume(),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(LocaleScope.t(context, 'memory_board_resume_button')),
                              style: ElevatedButton.styleFrom(backgroundColor: theme.primary, foregroundColor: Colors.white),
                            ),
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
        if (commentsBoxId != null && !_state.finished)
          VoiceCallOverlay(
            boxId: commentsBoxId,
            myUserId: widget.user.id,
            partnerUserId: _partnerUserId,
            enabled: true,
            paused: _state.isPaused,
            forceEnded: _state.isPaused,
          )
        else if (widget.nearbyComms != null && !_state.finished)
          NearbyVoiceOverlay(comms: widget.nearbyComms, enabled: true, paused: _state.isPaused),
        _buildGuideVoiceDemo(),
        GameWalletGuard(
          boxId: commentsBoxId,
          sessionType: 'battleship',
          sessionId: _sessionId,
        ),
      ],
      ),
    );
  }
}

class _OpponentGrid extends StatelessWidget {
  final BattleshipBoardState state;
  final void Function(int cell) onTapCell;
  // Guide pas-à-pas (voir demande utilisateur : "guider le user vers
  // quelque action pour qu'il comprenne le mécanisme") — [guideCell]
  // désigne une vraie case jamais encore tirée ; [guideHit] simule
  // localement le résultat une fois tapée (voir
  // _BattleshipBoardScreenState._onGuideFireTap), jamais
  // widget.transport.fire().
  final int? guideCell;
  final bool? guideHit;
  final GlobalKey? guideKey;
  final VoidCallback? onGuideTap;

  const _OpponentGrid({
    required this.state,
    required this.onTapCell,
    this.guideCell,
    this.guideHit,
    this.guideKey,
    this.onGuideTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final shotByCell = {for (final s in state.myShots) s.cell: s.hit};
    final sunkCells = {for (final ship in state.opponentSunkShips) ...ship};

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: theme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.primary.withValues(alpha: 0.3)),
        ),
        padding: const EdgeInsets.all(4),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: state.gridSize),
          itemCount: state.gridSize * state.gridSize,
          itemBuilder: (context, cell) {
            final isGuideCell = cell == guideCell;
            final shotHit = isGuideCell && guideHit != null ? guideHit : shotByCell[cell];
            final sunk = sunkCells.contains(cell);
            final tile = GestureDetector(
              onTap: isGuideCell && onGuideTap != null ? onGuideTap : (shotHit == null ? () => onTapCell(cell) : null),
              child: Container(
                margin: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: sunk
                      ? _kHitColor
                      : shotHit == true
                          ? _kHitColor.withValues(alpha: 0.7)
                          : shotHit == false
                              ? _kMissColor.withValues(alpha: 0.4)
                              : theme.surface.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(3),
                ),
                alignment: Alignment.center,
                child: shotHit == null
                    ? null
                    : Icon(shotHit ? Icons.close_rounded : Icons.circle, size: 10, color: Colors.white),
              ),
            );
            if (!isGuideCell || guideKey == null) return tile;
            return Showcase(
              key: guideKey!,
              title: guideHit == null ? 'Tire ici' : 'Touché !',
              description: guideHit == null
                  ? 'Tape cette case pour y tirer.'
                  : "Touché ! Comme c'est réussi, tu rejoues aussitôt une autre case. Si ça avait été manqué (gris), ce serait passé au tour de ton binôme. Coule tous les navires pour gagner.",
              targetBorderRadius: BorderRadius.circular(3),
              disableDefaultTargetGestures: onGuideTap != null,
              child: tile,
            );
          },
        ),
      ),
    );
  }
}

class _MyGrid extends StatelessWidget {
  final BattleshipBoardState state;

  const _MyGrid({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final hitCells = state.myHitCells;
    final shipCells = {for (final ship in state.myFleet) ...ship.cells};

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: theme.surface.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.primary.withValues(alpha: 0.2)),
        ),
        padding: const EdgeInsets.all(4),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: state.gridSize),
          itemCount: state.gridSize * state.gridSize,
          itemBuilder: (context, cell) {
            final hasShip = shipCells.contains(cell);
            final isHit = hitCells.contains(cell);
            return Container(
              margin: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: isHit
                    ? _kHitColor
                    : hasShip
                        ? _kShipColor
                        : theme.surface.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          },
        ),
      ),
    );
  }
}
