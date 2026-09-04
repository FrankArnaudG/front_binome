import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:google_fonts/google_fonts.dart';

import '../../../core/app_router.dart' show AppRouter;
import '../../../l10n/locale_scope.dart';
import '../../../models/app_user.dart';
import '../../../models/game.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../../../theme/themed_background.dart';
import '../widgets/game_comment_overlay.dart';
import '../widgets/pictionary_match_scoreboard.dart';
import '../widgets/voice_call_overlay.dart';
import 'pictionary_canvas.dart';
import 'pictionary_transport.dart';
import 'pictionary_transport_local.dart';
import 'pictionary_transport_remote.dart';

const _kRedColor = Color(0xFFE5484D);
const _kBlueColor = Color(0xFF2F6FED);

/// Plateau de "Pictionary à deux" — UNIQUE écran partagé par les 3 modes
/// (voir PictionaryTransport). En pass-and-play (voir
/// [LocalPictionaryTransport]), un écran de révélation privée du mot
/// s'affiche AVANT chaque manche — jamais le mot visible ailleurs.
class PictionaryBoardScreen extends StatefulWidget {
  final Game game;
  final AppUser user;
  final PictionaryTransport transport;
  final Map<String, String> playerNames;
  final Map<String, String?> playerAvatars;
  final Future<void> Function(BuildContext context)? onRematch;

  const PictionaryBoardScreen({
    super.key,
    required this.game,
    required this.user,
    required this.transport,
    required this.playerNames,
    required this.playerAvatars,
    this.onRematch,
  });

  @override
  State<PictionaryBoardScreen> createState() => _PictionaryBoardScreenState();
}

class _PictionaryBoardScreenState extends State<PictionaryBoardScreen> {
  late StreamSubscription<PictionaryBoardState> _subscription;
  late PictionaryBoardState _state;
  Timer? _clockTimer;
  bool _scoreboardShown = false;
  bool _skipRequested = false;

  bool get _isLocalPassAndPlay => widget.transport is LocalPictionaryTransport;

  // Pass-and-play uniquement : masque le mot tant que la personne qui
  // dessine n'a pas confirmé l'avoir vu (voir doc de classe).
  int _wordRevealedForRound = 0;

  @override
  void initState() {
    super.initState();
    _state = widget.transport.currentState;
    _subscription = widget.transport.stateStream.listen(_onState);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
        _maybeAutoSkip();
      }
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppRouter.showGlobalNavBar.value = false;
    });
  }

  void _onState(PictionaryBoardState state) {
    if (!mounted) return;
    if (state.roundNumber != _state.roundNumber) _skipRequested = false;
    setState(() => _state = state);

    if (state.finished && !_scoreboardShown) {
      _scoreboardShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showScoreboard());
    }
  }

  int _remainingSeconds() {
    final started = _state.roundStartedAt;
    if (started == null) return _state.roundSeconds;
    final elapsed = DateTime.now().difference(started).inSeconds;
    return (_state.roundSeconds - elapsed).clamp(0, _state.roundSeconds);
  }

  void _maybeAutoSkip() {
    if (_state.finished || _state.isPaused || _skipRequested) return;
    if (_isLocalPassAndPlay && _wordRevealedForRound != _state.roundNumber) return;
    if (_remainingSeconds() > 0) return;
    _skipRequested = true;
    widget.transport.skipRound();
  }

  Future<void> _showScoreboard() async {
    if (!mounted) return;
    final rematch = await showPictionaryMatchScoreboard(
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
    return transport is RemotePictionaryTransport ? transport.boxId : null;
  }

  String get _partnerUserId =>
      widget.playerNames.keys.firstWhere((id) => id != widget.user.id, orElse: () => widget.user.id);

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final drawerName = widget.playerNames[_state.currentDrawerUserId] ?? LocaleScope.t(context, 'memory_score_player_fallback');

    // Pass-and-play : révélation privée du mot avant chaque manche.
    if (_isLocalPassAndPlay && !_state.finished && _wordRevealedForRound != _state.roundNumber) {
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
                    Icon(Icons.brush_rounded, size: 48, color: theme.primary),
                    const SizedBox(height: 16),
                    Text(
                      LocaleScope.t(context, 'pictionary_turn_to_draw', {'name': drawerName}),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: theme.textOnBackground),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      LocaleScope.t(context, 'pictionary_reveal_word_subtitle'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () async {
                        final round = _state.roundNumber;
                        final revealed = await showDialog<bool>(
                          context: context,
                          barrierDismissible: false,
                          builder: (ctx) => AlertDialog(
                            title: Text(LocaleScope.t(ctx, 'pictionary_word_to_draw')),
                            content: Text(
                              _state.word ?? '',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w800),
                            ),
                            actions: [
                              FilledButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: Text(LocaleScope.t(ctx, 'pictionary_word_seen')),
                              ),
                            ],
                          ),
                        );
                        if (revealed == true && mounted) setState(() => _wordRevealedForRound = round);
                      },
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14)),
                      child: Text(LocaleScope.t(context, 'pictionary_reveal_word_button')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final remaining = _remainingSeconds();
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
                        Expanded(
                          child: Text(
                            _state.finished
                                ? LocaleScope.t(context, 'game_board_finished_label')
                                : (_state.isDrawer && _state.word != null
                                    ? LocaleScope.t(context, 'pictionary_your_word', {'word': _state.word!})
                                    : LocaleScope.t(context, 'pictionary_someone_drawing', {'name': drawerName})),
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 16, color: theme.primary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Row(
                          children: [
                            Icon(Icons.timer_outlined, size: 16, color: remaining <= 10 ? Colors.redAccent : theme.textOnBackgroundMuted),
                            const SizedBox(width: 4),
                            Text(
                              '0:${remaining.toString().padLeft(2, '0')}',
                              style: GoogleFonts.nunito(
                                fontSize: 13,
                                fontWeight: remaining <= 10 ? FontWeight.w800 : FontWeight.normal,
                                color: remaining <= 10 ? Colors.redAccent : theme.textOnBackgroundMuted,
                              ),
                            ),
                          ],
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
                            child: _PlayerChip(
                              theme: theme,
                              name: widget.playerNames[userId] ?? '',
                              avatar: widget.playerAvatars[userId],
                              color: _colorFor(userId),
                              score: _state.scoreFor(userId),
                              isDrawing: userId == _state.currentDrawerUserId,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: theme.primary.withValues(alpha: 0.2)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: PictionaryCanvas(
                          strokes: _state.strokes,
                          interactive: !_state.finished && !_state.isPaused && _state.isDrawer,
                          onStrokeComplete: (stroke) => widget.transport.addStroke(stroke),
                        ),
                      ),
                    ),
                  ),
                  if (!_state.finished)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                _skipRequested = true;
                                widget.transport.skipRound();
                              },
                              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                              child: Text(LocaleScope.t(context, 'pictionary_skip_button')),
                            ),
                          ),
                          if (_state.isDrawer) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: FilledButton.icon(
                                onPressed: () => widget.transport.markFound(),
                                icon: const Icon(Icons.check_circle_rounded),
                                label: Text(LocaleScope.t(context, 'pictionary_found_button')),
                                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
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

class _PlayerChip extends StatelessWidget {
  final ThemePalette theme;
  final String name;
  final String? avatar;
  final Color color;
  final int score;
  final bool isDrawing;

  const _PlayerChip({
    required this.theme,
    required this.name,
    required this.avatar,
    required this.color,
    required this.score,
    required this.isDrawing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.surface.withValues(alpha: theme.isDark ? 0.5 : 0.75),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDrawing ? color.withValues(alpha: 0.6) : color.withValues(alpha: 0.2), width: isDrawing ? 1.6 : 1),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: color.withValues(alpha: 0.16),
            backgroundImage: (avatar != null && avatar!.isNotEmpty) ? NetworkImage(avatar!) : null,
            child: (avatar == null || avatar!.isEmpty)
                ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: color, fontSize: 12))
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
          if (isDrawing) Icon(Icons.brush_rounded, size: 14, color: color),
          const SizedBox(width: 4),
          Text('$score', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}
