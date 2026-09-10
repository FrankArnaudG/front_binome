import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:google_fonts/google_fonts.dart';

import '../../../core/app_router.dart' show AppRouter;
import '../../../l10n/locale_scope.dart';
import '../../../models/app_user.dart';
import '../../../models/game.dart';
import '../../../theme/theme_scope.dart';
import '../../../theme/themed_background.dart';
import '../../box/box_scope.dart';
import '../widgets/battleship_match_scoreboard.dart';
import '../widgets/game_card_widgets.dart' show partnerReferenceLabel;
import '../widgets/game_comment_overlay.dart';
import '../widgets/voice_call_overlay.dart';
import 'battleship_transport.dart';
import 'battleship_transport_local.dart';
import 'battleship_transport_remote.dart';

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

  const BattleshipBoardScreen({
    super.key,
    required this.game,
    required this.user,
    required this.transport,
    required this.playerNames,
    required this.playerAvatars,
    this.onRematch,
  });

  @override
  State<BattleshipBoardScreen> createState() => _BattleshipBoardScreenState();
}

class _BattleshipBoardScreenState extends State<BattleshipBoardScreen> {
  late StreamSubscription<BattleshipBoardState> _subscription;
  late BattleshipBoardState _state;
  Timer? _clockTimer;
  bool _scoreboardShown = false;
  // Distingue "c'est moi qui viens d'abandonner" (voir _confirmAbandon,
  // déjà géré par le pop immédiat) de "le binôme vient d'abandonner à
  // distance" (voir _onState) — seul ce second cas doit afficher la
  // pop-up dédiée plutôt que de rester silencieux.
  bool _leavingMyself = false;

  bool get _isLocalPassAndPlay => widget.transport is LocalBattleshipTransport;

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
  }

  void _onState(BattleshipBoardState state) {
    if (!mounted) return;
    setState(() => _state = state);

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

  Future<void> _onTapOpponentCell(int cell) async {
    if (_state.finished || _state.isPaused || !_state.isMyTurn) return;
    if (_state.myShots.any((s) => s.cell == cell)) return;
    await widget.transport.fire(cell);
  }

  String _elapsed() {
    final started = _state.startedAt;
    if (started == null) return '0:00';
    final now = _state.pausedAt ?? DateTime.now();
    final seconds = now.difference(started).inSeconds.clamp(0, 1 << 31);
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _subscription.cancel();
    _clockTimer?.cancel();
    widget.transport.dispose();
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
              icon: const Icon(Icons.flag_outlined),
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
                              : (_state.isMyTurn
                                  ? LocaleScope.t(context, 'memory_board_your_turn')
                                  : LocaleScope.t(context, 'memory_board_partner_turn', {
                                      'name': widget.playerNames[_state.currentTurnUserId] ??
                                          LocaleScope.t(context, 'memory_board_partner_fallback'),
                                    })),
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 15, color: theme.primary),
                        ),
                        Row(
                          children: [
                            Icon(Icons.timer_outlined, size: 16, color: theme.textOnBackgroundMuted),
                            const SizedBox(width: 4),
                            Text(_elapsed(), style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted)),
                          ],
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
                          _OpponentGrid(state: _state, onTapCell: _onTapOpponentCell),
                          const SizedBox(height: 20),
                          Text(
                            LocaleScope.t(context, 'battleship_my_grid_label'),
                            style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: theme.textOnBackgroundMuted),
                          ),
                          const SizedBox(height: 6),
                          _MyGrid(state: _state),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ],
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
      ),
    ),
        ),
        if (commentsBoxId != null) GameCommentOverlay(boxId: commentsBoxId, enabled: true),
        if (commentsBoxId != null)
          VoiceCallOverlay(boxId: commentsBoxId, myUserId: widget.user.id, partnerUserId: _partnerUserId, enabled: true, paused: _state.isPaused),
      ],
      ),
    );
  }
}

class _OpponentGrid extends StatelessWidget {
  final BattleshipBoardState state;
  final void Function(int cell) onTapCell;

  const _OpponentGrid({required this.state, required this.onTapCell});

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
            final shotHit = shotByCell[cell];
            final sunk = sunkCells.contains(cell);
            return GestureDetector(
              onTap: shotHit == null ? () => onTapCell(cell) : null,
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
