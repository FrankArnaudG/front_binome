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
import '../widgets/connect_four_match_scoreboard.dart';
import '../widgets/game_comment_overlay.dart';
import '../widgets/voice_call_overlay.dart';
import 'connect_four_engine.dart';
import 'connect_four_transport.dart';
import 'connect_four_transport_remote.dart';

const _kRedColor = Color(0xFFE5484D);
const _kBlueColor = Color(0xFF2F6FED);

/// Plateau de "Puissance 4" — UNIQUE écran de jeu partagé par les 3 modes
/// (voir ConnectFourTransport), copie structurelle conforme des autres
/// jeux (pause/reprise, chrono, tour par tour) — single round, le bouton
/// "Rejouer" gère la rejouabilité.
class ConnectFourBoardScreen extends StatefulWidget {
  final Game game;
  final AppUser user;
  final ConnectFourTransport transport;
  final Map<String, String> playerNames;
  final Map<String, String?> playerAvatars;
  final Future<void> Function(BuildContext context)? onRematch;

  const ConnectFourBoardScreen({
    super.key,
    required this.game,
    required this.user,
    required this.transport,
    required this.playerNames,
    required this.playerAvatars,
    this.onRematch,
  });

  @override
  State<ConnectFourBoardScreen> createState() => _ConnectFourBoardScreenState();
}

class _ConnectFourBoardScreenState extends State<ConnectFourBoardScreen> {
  late StreamSubscription<ConnectFourBoardState> _subscription;
  late ConnectFourBoardState _state;
  Timer? _clockTimer;
  bool _scoreboardShown = false;

  bool get _myTurnActionable => !widget.transport.requiresTurnToPlay || _state.isMyTurn;

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

  void _onState(ConnectFourBoardState state) {
    if (!mounted) return;
    setState(() => _state = state);

    if (state.finished && !_scoreboardShown) {
      _scoreboardShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showScoreboard());
    }
  }

  Future<void> _showScoreboard() async {
    if (!mounted) return;
    final rematch = await showConnectFourMatchScoreboard(
      context,
      state: _state,
      playerNames: widget.playerNames,
      playerAvatars: widget.playerAvatars,
      colorFor: _colorFor,
      allowRematch: widget.onRematch != null,
    );
    if (rematch == true && widget.onRematch != null && mounted) {
      await widget.onRematch!(context);
    }
  }

  /// "Tuyaux" (voir demande utilisateur) — [pipe] est une position
  /// d'affichage (0..cols-1) SANS rapport visible avec la colonne réelle
  /// où le jeton va tomber (mélange aléatoire, un par partie, jamais
  /// révélé). Impossible de pré-filtrer "colonne pleine" côté client
  /// puisque le client ne connaît justement pas la vraie colonne — voir
  /// le retour `bool` de `transport.drop()`.
  Future<void> _onTapPipe(int pipe) async {
    if (_state.finished || _state.isPaused || !_myTurnActionable) return;
    final applied = await widget.transport.drop(pipe);
    if (!applied && mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LocaleScope.t(context, 'connect_four_pipe_full')),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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

  Color _colorFor(String userId) {
    final ids = widget.playerNames.keys.toList()..sort();
    return userId == ids.first ? _kRedColor : _kBlueColor;
  }

  @override
  void dispose() {
    _subscription.cancel();
    _clockTimer?.cancel();
    widget.transport.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    AppRouter.showGlobalNavBar.value = true;
    super.dispose();
  }

  String? get _commentsBoxId {
    final transport = widget.transport;
    return transport is RemoteConnectFourTransport ? transport.boxId : null;
  }

  String get _partnerUserId =>
      widget.playerNames.keys.firstWhere((id) => id != widget.user.id, orElse: () => widget.user.id);

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final commentsBoxId = _commentsBoxId;

    return Stack(
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
                if (confirmed == true) await widget.transport.abandon();
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
                              : (widget.transport.requiresTurnToPlay
                                  ? (_state.isMyTurn
                                      ? LocaleScope.t(context, 'memory_board_your_turn')
                                      : LocaleScope.t(context, 'memory_board_partner_turn', {
                                          'name': widget.playerNames[_state.currentTurnUserId] ??
                                              LocaleScope.t(context, 'memory_board_partner_fallback'),
                                        }))
                                  : LocaleScope.t(context, 'memory_board_partner_turn', {
                                      'name': widget.playerNames[_state.currentTurnUserId] ??
                                          LocaleScope.t(context, 'memory_board_partner_fallback'),
                                    })),
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 16, color: theme.primary),
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
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              LocaleScope.t(context, 'connect_four_pipes_hint'),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                            ),
                            const SizedBox(height: 8),
                            // "Tuyaux" (voir demande utilisateur) — la
                            // colonne réelle où le jeton va tomber est
                            // mélangée aléatoirement, jamais révélée : ces
                            // boutons ne sont PAS alignés avec les
                            // colonnes de la grille en dessous, exprès.
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                for (var pipe = 0; pipe < ConnectFourEngine.cols; pipe++)
                                  _PipeButton(
                                    enabled: !_state.finished && !_state.isPaused && _myTurnActionable,
                                    color: theme.primary,
                                    onTap: () => _onTapPipe(pipe),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            AspectRatio(
                              aspectRatio: ConnectFourEngine.cols / ConnectFourEngine.rows,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: theme.primary.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  children: [
                                    for (var col = 0; col < ConnectFourEngine.cols; col++)
                                      Expanded(
                                        child: Column(
                                          children: [
                                            for (var row = 0; row < ConnectFourEngine.rows; row++)
                                              Expanded(
                                                child: Padding(
                                                  padding: const EdgeInsets.all(3),
                                                  child: _Disc(
                                                    userId: _state.board[row * ConnectFourEngine.cols + col],
                                                    color: _state.board[row * ConnectFourEngine.cols + col] != null
                                                        ? _colorFor(_state.board[row * ConnectFourEngine.cols + col]!)
                                                        : null,
                                                    highlighted:
                                                        _state.winningLine?.contains(row * ConnectFourEngine.cols + col) ?? false,
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
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
              if (_state.isPaused)
                Positioned.fill(
                  child: Container(
                    color: theme.background.withValues(alpha: 0.94),
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
          VoiceCallOverlay(boxId: commentsBoxId, myUserId: widget.user.id, partnerUserId: _partnerUserId, enabled: true),
      ],
    );
  }
}

/// Un "tuyau" — voir demande utilisateur : bouton d'entrée SANS rapport
/// visible avec la colonne réelle où le jeton va tomber, tous identiques
/// pour ne rien laisser deviner de la correspondance (mélangée
/// aléatoirement une fois par partie, voir ConnectFourEngine.drop côté
/// transport).
class _PipeButton extends StatelessWidget {
  final bool enabled;
  final Color color;
  final VoidCallback onTap;

  const _PipeButton({required this.enabled, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Material(
        color: color.withValues(alpha: 0.14),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(Icons.arrow_downward_rounded, size: 20, color: color),
          ),
        ),
      ),
    );
  }
}

class _Disc extends StatelessWidget {
  final String? userId;
  final Color? color;
  final bool highlighted;

  const _Disc({required this.userId, required this.color, required this.highlighted});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color ?? Colors.white.withValues(alpha: 0.25),
        border: highlighted ? Border.all(color: Colors.white, width: 3) : null,
        boxShadow: highlighted ? const [BoxShadow(color: Colors.white70, blurRadius: 8)] : null,
      ),
    );
  }
}
