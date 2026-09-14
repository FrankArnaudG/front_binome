import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:google_fonts/google_fonts.dart';

import '../../../core/app_router.dart' show AppRouter;
import '../../../core/server_clock.dart';
import '../../../l10n/locale_scope.dart';
import '../../../models/app_user.dart';
import '../../../models/dot_square_session.dart';
import '../../../models/game.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../../../theme/themed_background.dart';
import '../../box/box_scope.dart';
import '../game_service.dart';
import '../nearby/nearby_comms.dart';
import '../widgets/coin_billing_ring.dart';
import '../widgets/dot_squares_match_scoreboard.dart';
import '../widgets/game_card_widgets.dart' show partnerReferenceLabel;
import '../widgets/game_comment_overlay.dart';
import '../widgets/game_wallet_guard.dart';
import '../widgets/nearby_voice_overlay.dart';
import '../widgets/voice_call_overlay.dart';
import 'dot_squares_engine.dart';
import 'dot_squares_transport.dart';
import 'dot_squares_transport_remote.dart';

const _kCellSize = 26.0;
const _kGridPadding = 18.0;
const _kRedColor = Color(0xFFE5484D);
const _kBlueColor = Color(0xFF2F6FED);

/// Feuille de "Le Jeu des Carrés" — UNIQUE écran de jeu partagé par les 3
/// modes (voir DotSquaresTransport), copie structurelle conforme de
/// TicTacToeBoardScreen/MemoryGameBoardScreen (pause/reprise, chrono).
///
/// Contrairement aux autres jeux, l'affichage n'est pas une grille de
/// tuiles carrées mais une vraie "feuille de points" dessinée à la main
/// (voir _DotSquaresPainter) — points aux intersections, rectangles tracés
/// et numérotés dès qu'ils sont formés (voir DotSquareRectangle).
class DotSquaresBoardScreen extends StatefulWidget {
  final Game game;
  final AppUser user;
  final DotSquaresTransport transport;
  final Map<String, String> playerNames;
  final Map<String, String?> playerAvatars;
  final Future<void> Function(BuildContext context)? onRematch;
  final NearbyComms? nearbyComms;
  final String? nearbyMyName;
  final String? nearbyPartnerName;

  const DotSquaresBoardScreen({
    super.key,
    required this.game,
    required this.user,
    required this.transport,
    required this.playerNames,
    required this.playerAvatars,
    this.onRematch,
    this.nearbyComms,
    this.nearbyMyName,
    this.nearbyPartnerName,
  });

  @override
  State<DotSquaresBoardScreen> createState() => _DotSquaresBoardScreenState();
}

class _DotSquaresBoardScreenState extends State<DotSquaresBoardScreen> {
  late StreamSubscription<DotSquaresBoardState> _subscription;
  late DotSquaresBoardState _state;
  Timer? _clockTimer;
  bool _scoreboardShown = false;
  // Distingue "c'est moi qui viens d'abandonner" (voir _confirmAbandon,
  // déjà géré par le pop immédiat) de "le binôme vient d'abandonner à
  // distance" (voir _onState) — seul ce second cas doit afficher la
  // pop-up dédiée plutôt que de rester silencieux.
  bool _leavingMyself = false;
  // Solde de pièces du couple épuisé en cours de partie (voir
  // GameWalletGuard/demande utilisateur) — coupe le micro/vidéo en cours.
  bool _walletDepleted = false;
  // Réglage admin (minutes_per_coin/grace_period_seconds) pour l'anneau de
  // progression coté pièce (voir CoinBillingRing/demande utilisateur) —
  // chargé une seule fois, uniquement utile en mode à distance.
  Map<String, int>? _economyRate;

  // Défilement synchronisé PAR CHOIX (voir demande utilisateur : jamais
  // forcé sur l'écran du binôme, qui pourrait vouloir regarder ailleurs)
  // — juste de quoi savoir si le dernier coup est visible à l'écran, et
  // y sauter volontairement sur simple tap (voir _notifyPosition).
  final _horizontalController = ScrollController();
  final _verticalController = ScrollController();

  // Position du dernier point posé — un bref halo pulsé s'y affiche
  // toujours (voir demande utilisateur : "signaler visuellement l'endroit
  // où je clique"), et si cette case n'est PAS visible à l'écran, un
  // bandeau discret propose d'y sauter (voir _scrollToPosition).
  int? _pulsePosition;
  Timer? _pulseTimer;
  int? _notifyPosition;
  String? _notifyByUserId;

  @override
  void initState() {
    super.initState();
    _state = widget.transport.currentState;
    _subscription = widget.transport.stateStream.listen(_onState);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppRouter.showGlobalNavBar.value = false;
    });
    if (_commentsBoxId != null) _loadEconomyRate();
  }

  Future<void> _loadEconomyRate() async {
    try {
      final rate = await GameService.instance.fetchGameEconomyRate();
      if (mounted) setState(() => _economyRate = rate);
    } catch (_) {
      // Best-effort — l'anneau reste simplement invisible sans ce détail.
    }
  }

  /// Fraction (0..1) de progression vers la prochaine pièce déduite —
  /// purement indicatif (voir doc de CoinBillingRing), calculé à partir du
  /// même réglage que le serveur (minutes_per_coin/grace_period_seconds)
  /// mais jamais la source de vérité de la facturation elle-même.
  double _coinProgress() {
    final rate = _economyRate;
    final started = _state.startedAt;
    if (rate == null || started == null) return 0;
    final minutesPerCoin = rate['minutes_per_coin'] ?? 8;
    final graceSeconds = rate['grace_period_seconds'] ?? 0;
    final cycleSeconds = minutesPerCoin * 60;
    if (cycleSeconds <= 0) return 0;
    final now = _state.pausedAt ?? ServerClock.instance.now();
    final elapsedSeconds = now.difference(started).inSeconds - graceSeconds;
    if (elapsedSeconds <= 0) return 0;
    return (elapsedSeconds % cycleSeconds) / cycleSeconds;
  }

  void _onState(DotSquaresBoardState state) {
    if (!mounted) return;
    final previousPoints = _state.points;
    int? newlyPlaced;
    if (previousPoints.length == state.points.length) {
      for (var i = 0; i < state.points.length; i++) {
        if (previousPoints[i] == null && state.points[i] != null) {
          newlyPlaced = i;
          break;
        }
      }
    }

    setState(() => _state = state);

    if (newlyPlaced != null) {
      _pulseTimer?.cancel();
      setState(() => _pulsePosition = newlyPlaced);
      _pulseTimer = Timer(const Duration(milliseconds: 1000), () {
        if (mounted) setState(() => _pulsePosition = null);
      });

      // Après le premier frame de ce nouvel état (la feuille a fini de se
      // reconstruire) — sinon `hasClients`/`viewportDimension` peuvent
      // encore refléter l'ancienne mise en page.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final by = state.points[newlyPlaced!];
        // Pas de bandeau pour son propre coup (voir demande utilisateur :
        // seul le coup DU BINÔME doit proposer de sauter dessus).
        final show = by != widget.user.id && !_isPositionVisible(newlyPlaced);
        setState(() {
          _notifyPosition = show ? newlyPlaced : null;
          _notifyByUserId = show ? by : null;
        });
      });
    }

    if (state.newlyScored.isNotEmpty) _showScoreToast(state.newlyScored.length);

    if (state.finished && !_scoreboardShown) {
      _scoreboardShown = true;
      if (state.abandoned && !_leavingMyself) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showPartnerLeftDialog());
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showScoreboard());
      }
    }
  }

  /// Affichée UNIQUEMENT quand le binôme vient d'abandonner à distance
  /// (voir _onState) — jamais quand c'est nous qui venons de le faire (voir
  /// _confirmAbandon, qui referme déjà l'écran tout seul). "OK" laisse
  /// consulter le plateau tel qu'il était ; "Sortir" referme l'écran tout de
  /// suite (voir demande utilisateur).
  Future<void> _showPartnerLeftDialog() async {
    if (!mounted) return;
    final box = BoxScope.of(context).currentBox;
    final partner = box?.partnerOf(widget.user.id);
    final label = partnerReferenceLabel(context, partner, widget.game.id);
    final exit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(LocaleScope.t(ctx, 'game_board_partner_left_title')),
        content: Text(LocaleScope.t(ctx, 'game_board_partner_left_content', {'partner': label})),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(LocaleScope.t(ctx, 'game_board_partner_left_ok'))),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(LocaleScope.t(ctx, 'game_board_partner_left_exit'), style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (exit == true && mounted) Navigator.of(context).pop();
  }

  bool _isPositionVisible(int position) {
    final row = position ~/ _state.gridCols;
    final col = position % _state.gridCols;
    final vertexX = _kGridPadding + col * _kCellSize;
    final vertexY = _kGridPadding + row * _kCellSize;

    if (_horizontalController.hasClients) {
      final h = _horizontalController.position;
      if (vertexX < h.pixels || vertexX > h.pixels + h.viewportDimension) return false;
    }
    if (_verticalController.hasClients) {
      final v = _verticalController.position;
      if (vertexY < v.pixels || vertexY > v.pixels + v.viewportDimension) return false;
    }
    return true;
  }

  Future<void> _scrollToPosition(int position) async {
    final row = position ~/ _state.gridCols;
    final col = position % _state.gridCols;
    final vertexX = _kGridPadding + col * _kCellSize;
    final vertexY = _kGridPadding + row * _kCellSize;

    final jumps = <Future<void>>[];
    if (_horizontalController.hasClients) {
      final h = _horizontalController.position;
      final target = (vertexX - h.viewportDimension / 2).clamp(0.0, h.maxScrollExtent);
      jumps.add(_horizontalController.animateTo(target, duration: const Duration(milliseconds: 400), curve: Curves.easeOut));
    }
    if (_verticalController.hasClients) {
      final v = _verticalController.position;
      final target = (vertexY - v.viewportDimension / 2).clamp(0.0, v.maxScrollExtent);
      jumps.add(_verticalController.animateTo(target, duration: const Duration(milliseconds: 400), curve: Curves.easeOut));
    }
    await Future.wait(jumps);
    if (mounted) setState(() { _notifyPosition = null; _notifyByUserId = null; });
  }

  void _showScoreToast(int count) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count > 1
              ? LocaleScope.t(context, 'dot_squares_rectangles_scored', {'count': '$count'})
              : LocaleScope.t(context, 'dot_squares_rectangle_scored'),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showScoreboard() async {
    if (!mounted) return;
    final rematch = await showDotSquaresMatchScoreboard(
      context,
      state: _state,
      playerNames: widget.playerNames,
      playerAvatars: widget.playerAvatars,
      colorFor: _colorFor,
      allowRematch: widget.onRematch != null,
    );
    if (rematch == true && widget.onRematch != null && mounted) {
      await widget.onRematch!(context);
    } else if (mounted) {
      // Voir demande utilisateur : fermer ce modal — croix, glisser, ou
      // taper à côté, peu importe le geste — doit refermer le jeu et
      // revenir à la liste, comme un retour classique.
      Navigator.of(context).pop();
    }
  }

  bool get _myTurnActionable => !widget.transport.requiresTurnToPlay || _state.isMyTurn;

  Future<void> _onTapPoint(int position) async {
    if (_state.finished || _state.isPaused) return;
    if (_state.closeRequested) return;
    if (!_myTurnActionable) return;
    if (_state.points[position] != null) return;
    // Case sur le bord d'un rectangle déjà formé — ignorée comme une case
    // déjà prise (voir demande utilisateur), plutôt que de laisser
    // transport.place() lever une exception non rattrapée ici.
    if (DotSquaresEngine.isPositionBlocked(_state.rectangles, position ~/ _state.gridCols, position % _state.gridCols)) {
      return;
    }

    await widget.transport.place(position);
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

  String _elapsed() {
    final started = _state.startedAt;
    if (started == null) return '0:00';
    final now = _state.pausedAt ?? ServerClock.instance.now();
    // Le chrono attend la même période de grâce que l'anneau de pièce
    // (voir CoinBillingRing/demande utilisateur) — reste à 0:00 tant que
    // la grâce n'est pas écoulée, nul en dehors du mode à distance.
    final graceSeconds = _economyRate?['grace_period_seconds'] ?? 0;
    // max(0, ...) : horloge du téléphone en retard sur celle du serveur
    // (courant sur un appareil de test) -> différence négative, un chrono
    // négatif n'a aucun sens à l'écran (même correctif que MemoryGameBoardScreen).
    final seconds = (now.difference(started).inSeconds - graceSeconds).clamp(0, 1 << 31);
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  /// Rouge pour la première des deux id (par ordre lexicographique) et
  /// bleu pour l'autre — déterministe des deux côtés (voir demande
  /// utilisateur : "couleur rouge et couleur bleu"), même principe que le
  /// cœur/étoile du Morpion.
  Color _colorFor(String userId) {
    final ids = widget.playerNames.keys.toList()..sort();
    return userId == ids.first ? _kRedColor : _kBlueColor;
  }

  @override
  void dispose() {
    _subscription.cancel();
    _clockTimer?.cancel();
    _pulseTimer?.cancel();
    _horizontalController.dispose();
    _verticalController.dispose();
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
    return transport is RemoteDotSquaresTransport ? transport.boxId : null;
  }

  String get _sessionId {
    final transport = widget.transport;
    return transport is RemoteDotSquaresTransport ? transport.sessionId : '';
  }

  /// Bouton "Terminer la partie" du popup de solde épuisé (voir
  /// GameWalletGuard) — même geste qu'un abandon volontaire.
  Future<void> _endGameFromWalletDepletion() async {
    _leavingMyself = true;
    await widget.transport.abandon();
    if (mounted) Navigator.of(context).pop();
  }

  String get _partnerUserId =>
      widget.playerNames.keys.firstWhere((id) => id != widget.user.id, orElse: () => widget.user.id);

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final commentsBoxId = _commentsBoxId;
    final gridWidth = (_state.gridCols - 1) * _kCellSize + 2 * _kGridPadding;
    final gridHeight = (DotSquaresEngine.gridRows - 1) * _kCellSize + 2 * _kGridPadding;

    return PopScope(
      canPop: _state.finished,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmAbandon()) {
          _leavingMyself = true;
          await widget.transport.abandon();
          if (context.mounted) Navigator.of(context).pop();
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
            if (_state.isPaused)
              IconButton(
                icon: const Icon(Icons.play_circle_outline),
                tooltip: _state.pausedByMe
                    ? LocaleScope.t(context, 'memory_board_resume_tooltip')
                    : LocaleScope.t(context, 'memory_board_paused_by_partner_tooltip', {
                        'name': widget.playerNames[_state.pausedByUserId] ??
                            LocaleScope.t(context, 'memory_board_partner_fallback'),
                      }),
                onPressed: _state.pausedByMe ? () => widget.transport.resume() : null,
              )
            else
              IconButton(
                icon: const Icon(Icons.pause_circle_outline),
                tooltip: LocaleScope.t(context, 'memory_board_pause_tooltip'),
                onPressed: () => widget.transport.pause(),
              ),
          if (!_state.finished)
            IconButton(
              icon: const Icon(Icons.outlined_flag_rounded),
              tooltip: LocaleScope.t(context, 'memory_board_abandon_tooltip'),
              onPressed: () async {
                if (await _confirmAbandon()) {
                  _leavingMyself = true;
                  await widget.transport.abandon();
                }
              },
            ),
          if (_state.finished && widget.onRematch != null)
            IconButton(
              icon: const Icon(Icons.replay_rounded),
              tooltip: LocaleScope.t(context, 'memory_score_rematch'),
              onPressed: () => widget.onRematch!(context),
            ),
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
                    Flexible(
                      child: Text(
                        _state.finished
                            ? LocaleScope.t(context, 'game_board_finished_label')
                            : (widget.transport.requiresTurnToPlay
                                ? (_state.isMyTurn
                                    ? LocaleScope.t(context, 'memory_board_your_turn')
                                    : LocaleScope.t(context, 'memory_board_partner_turn', {
                                        'name': widget.playerNames[_state.currentTurnUserId] ??
                                            LocaleScope.t(context, 'memory_board_partner_fallback'),
                                      }))
                                : LocaleScope.t(context, 'memory_board_partner_turn', {
                                    'name': widget.playerNames[_state.currentTurnUserId] ?? '...',
                                  })),
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: theme.primary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      children: [
                        Icon(Icons.timer_outlined, size: 16, color: theme.textOnBackgroundMuted),
                        const SizedBox(width: 4),
                        Text(_elapsed(), style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted)),
                        if (commentsBoxId != null) ...[
                          const SizedBox(width: 8),
                          CoinBillingRing(theme: theme, progress: _coinProgress()),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                child: Row(
                  children: [
                    for (final userId in widget.playerNames.keys) ...[
                      if (userId != widget.playerNames.keys.first) const SizedBox(width: 10),
                      Expanded(
                        child: _DotSquaresPlayerChip(
                          theme: theme,
                          name: widget.playerNames[userId] ?? '',
                          avatar: widget.playerAvatars[userId],
                          color: _colorFor(userId),
                          active: _state.currentTurnUserId == userId,
                          score: _state.scoreFor(userId),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_notifyPosition != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Material(
                    color: theme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _scrollToPosition(_notifyPosition!),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            Icon(Icons.touch_app_rounded, size: 18, color: theme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                LocaleScope.t(context, 'dot_squares_played_here', {
                                  'name': widget.playerNames[_notifyByUserId] ??
                                      LocaleScope.t(context, 'memory_board_partner_fallback'),
                                }),
                                style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: theme.textOnBackground),
                              ),
                            ),
                            Icon(Icons.arrow_forward_rounded, size: 18, color: theme.primary),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Expanded(
                // Voir demande utilisateur (capture : l'overlay de pause
                // n'apparaissait qu'en partie, comme une simple barre rose,
                // selon où la feuille était scrollée) — l'overlay était
                // imbriqué DANS le Stack qui enveloppe le CustomPaint,
                // lui-même bien plus grand que l'écran (jusqu'à des
                // milliers de pixels de large selon le palier) : un
                // `Positioned.fill` s'y étend sur la TOTALITÉ de cette
                // immense zone scrollable, pas sur ce qui est
                // effectivement visible — son contenu centré tombait donc
                // n'importe où selon la position du défilement. Sorti ici
                // dans un Stack englobant tout le viewport (Expanded), pour
                // que `Positioned.fill` corresponde enfin à l'écran visible.
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      controller: _verticalController,
                      child: Center(
                        child: SingleChildScrollView(
                          controller: _horizontalController,
                          scrollDirection: Axis.horizontal,
                          child: GestureDetector(
                            onTapUp: (details) => _handleTap(details.localPosition),
                            child: CustomPaint(
                              size: Size(gridWidth, gridHeight),
                              painter: _DotSquaresPainter(
                                points: _state.points,
                                rectangles: _state.rectangles,
                                gridCols: _state.gridCols,
                                colorFor: _colorFor,
                                mutedColor: theme.textOnBackgroundMuted,
                                gridLineColor: theme.primary.withValues(alpha: 0.08),
                                backgroundColor: theme.background,
                                pulsePosition: _pulsePosition,
                                pulseColor: theme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_state.isPaused)
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
                                  _state.pausedByMe
                                      ? LocaleScope.t(context, 'memory_board_paused_subtitle_me')
                                      : LocaleScope.t(context, 'memory_board_paused_subtitle_partner', {
                                          'name': widget.playerNames[_state.pausedByUserId] ??
                                              LocaleScope.t(context, 'memory_board_partner_fallback'),
                                        }),
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                                ),
                                if (_state.pausedByMe) ...[
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
            ],
          ),
        ),
      ),
    ),
        ),
        if (commentsBoxId != null)
          GameCommentOverlay(boxId: commentsBoxId, enabled: true)
        else if (widget.nearbyComms != null)
          GameCommentOverlay(
            nearbyComms: widget.nearbyComms,
            enabled: true,
            myName: widget.nearbyMyName ?? '',
            partnerName: widget.nearbyPartnerName ?? '',
          ),
        if (commentsBoxId != null)
          VoiceCallOverlay(
            boxId: commentsBoxId,
            myUserId: widget.user.id,
            partnerUserId: _partnerUserId,
            enabled: true,
            paused: _state.isPaused,
            forceEnded: _walletDepleted,
          )
        else if (widget.nearbyComms != null)
          NearbyVoiceOverlay(comms: widget.nearbyComms, enabled: true, paused: _state.isPaused),
        GameWalletGuard(
          boxId: commentsBoxId,
          sessionType: 'dot_squares',
          sessionId: _sessionId,
          onDepletedChanged: (v) => setState(() => _walletDepleted = v),
          onEndGame: _endGameFromWalletDepletion,
        ),
      ],
      ),
    );
  }

  void _handleTap(Offset local) {
    final col = ((local.dx - _kGridPadding) / _kCellSize).round();
    final row = ((local.dy - _kGridPadding) / _kCellSize).round();
    if (row < 0 || row >= DotSquaresEngine.gridRows || col < 0 || col >= _state.gridCols) return;

    final vertexX = _kGridPadding + col * _kCellSize;
    final vertexY = _kGridPadding + row * _kCellSize;
    final distance = math.sqrt(math.pow(local.dx - vertexX, 2) + math.pow(local.dy - vertexY, 2));
    if (distance > _kCellSize * 0.5) return;

    _onTapPoint(row * _state.gridCols + col);
  }
}

class _DotSquaresPlayerChip extends StatelessWidget {
  final ThemePalette theme;
  final String name;
  final String? avatar;
  final Color color;
  final bool active;
  final int score;

  const _DotSquaresPlayerChip({
    required this.theme,
    required this.name,
    required this.avatar,
    required this.color,
    required this.active,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.12) : theme.surface.withValues(alpha: theme.isDark ? 0.5 : 0.75),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: active ? color.withValues(alpha: 0.5) : color.withValues(alpha: 0.18)),
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
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text('$score', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

/// Dessine la feuille : grille légère type papier quadrillé, points aux
/// intersections, rectangles tracés/numérotés (voir demande utilisateur :
/// "tu traces pour les relier et tu numérotes à l'intérieur").
class _DotSquaresPainter extends CustomPainter {
  final List<String?> points;
  final List<DotSquareRectangle> rectangles;
  final int gridCols;
  final Color Function(String userId) colorFor;
  final Color mutedColor;
  final Color gridLineColor;
  final Color backgroundColor;
  final int? pulsePosition;
  final Color pulseColor;

  _DotSquaresPainter({
    required this.points,
    required this.rectangles,
    required this.gridCols,
    required this.colorFor,
    required this.mutedColor,
    required this.gridLineColor,
    required this.backgroundColor,
    this.pulsePosition,
    this.pulseColor = Colors.orange,
  });

  Offset _vertex(int row, int col) => Offset(_kGridPadding + col * _kCellSize, _kGridPadding + row * _kCellSize);

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridLineColor
      ..strokeWidth = 1;

    for (var row = 0; row < DotSquaresEngine.gridRows; row++) {
      canvas.drawLine(_vertex(row, 0), _vertex(row, gridCols - 1), gridPaint);
    }
    for (var col = 0; col < gridCols; col++) {
      canvas.drawLine(_vertex(0, col), _vertex(DotSquaresEngine.gridRows - 1, col), gridPaint);
    }

    // Dessine d'abord tous les traits, PUIS tous les numéros par-dessus —
    // sinon un trait d'un rectangle voisin traverse visuellement le badge
    // d'un autre numéro déjà posé.
    for (final rect in rectangles) {
      final color = colorFor(rect.ownerUserId);
      final rectPaint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawRect(Rect.fromPoints(_vertex(rect.r1, rect.c1), _vertex(rect.r2, rect.c2)), rectPaint);
    }

    for (final rect in rectangles) {
      final color = colorFor(rect.ownerUserId);
      final topLeft = _vertex(rect.r1, rect.c1);
      final bottomRight = _vertex(rect.r2, rect.c2);
      final center = Offset((topLeft.dx + bottomRight.dx) / 2, (topLeft.dy + bottomRight.dy) / 2);

      final textPainter = TextPainter(
        text: TextSpan(
          text: '${rect.number}',
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Halo plein derrière chaque numéro (couleur de fond + liseré de la
      // couleur du propriétaire) pour qu'il reste lisible même quand
      // plusieurs rectangles imbriqués/proches se chevauchent visuellement
      // (voir demande utilisateur — capture où les numéros se
      // superposaient en un tas illisible).
      final haloRadius = (textPainter.width > textPainter.height ? textPainter.width : textPainter.height) / 2 + 3;
      canvas.drawCircle(center, haloRadius, Paint()..color = backgroundColor);
      canvas.drawCircle(center, haloRadius, Paint()
        ..color = color.withValues(alpha: 0.6)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke);

      textPainter.paint(canvas, center - Offset(textPainter.width / 2, textPainter.height / 2));
    }

    for (var i = 0; i < points.length; i++) {
      final owner = points[i];
      final row = i ~/ gridCols;
      final col = i % gridCols;
      final center = _vertex(row, col);

      if (owner == null) {
        // Case bloquée (bord d'un rectangle déjà formé) : point encore
        // plus estompé, pour signaler visuellement qu'un tap ici n'aura
        // aucun effet (voir demande utilisateur).
        final blocked = DotSquaresEngine.isPositionBlocked(rectangles, row, col);
        canvas.drawCircle(center, 2, Paint()..color = mutedColor.withValues(alpha: blocked ? 0.12 : 0.35));
      } else {
        canvas.drawCircle(center, 5, Paint()..color = colorFor(owner));
      }
    }

    // Halo pulsé sur le dernier point posé — signale visuellement
    // "l'endroit où j'ai cliqué" (voir demande utilisateur), pour les
    // DEUX joueurs, pas seulement celui qui a joué.
    if (pulsePosition != null && pulsePosition! < points.length) {
      final row = pulsePosition! ~/ gridCols;
      final col = pulsePosition! % gridCols;
      final center = _vertex(row, col);
      canvas.drawCircle(center, 12, Paint()..color = pulseColor.withValues(alpha: 0.25));
      canvas.drawCircle(center, 12, Paint()
        ..color = pulseColor.withValues(alpha: 0.7)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _DotSquaresPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.rectangles != rectangles ||
      oldDelegate.gridCols != gridCols ||
      oldDelegate.pulsePosition != pulsePosition;
}
