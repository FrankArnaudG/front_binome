import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:google_fonts/google_fonts.dart';

import '../../../core/app_router.dart' show AppRouter;
import '../../../core/server_clock.dart';
import '../../../l10n/locale_scope.dart';
import '../../../models/app_user.dart';
import '../../../models/game.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../../../theme/themed_background.dart';
import '../../box/box_scope.dart';
import '../game_service.dart';
import '../nearby/nearby_comms.dart';
import '../widgets/coin_billing_ring.dart';
import '../widgets/game_card_widgets.dart' show partnerReferenceLabel;
import '../widgets/game_comment_overlay.dart';
import '../widgets/game_wallet_guard.dart';
import '../widgets/nearby_voice_overlay.dart';
import '../widgets/voice_call_overlay.dart';
import 'suit_battle_engine.dart';
import 'suit_battle_transport.dart';
import 'suit_battle_transport_remote.dart';

const _kRedColor = Color(0xFFE5484D);
const _kBlueColor = Color(0xFF2F6FED);
const _kJokerColor = Color(0xFF7C4DFF);

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
    this.nearbyComms,
    this.nearbyMyName,
    this.nearbyPartnerName,
  });

  @override
  State<SuitBattleBoardScreen> createState() => _SuitBattleBoardScreenState();
}

class _SuitBattleBoardScreenState extends State<SuitBattleBoardScreen> with SingleTickerProviderStateMixin {
  late StreamSubscription<SuitBattleBoardState> _subscription;
  late SuitBattleBoardState _state;
  Timer? _clockTimer;
  bool _scoreboardShown = false;
  // Distingue "c'est moi qui viens d'abandonner" (déjà géré par le pop
  // immédiat) de "le binôme vient d'abandonner à distance" — voir
  // WarCardBoardScreen._leavingMyself, même principe.
  bool _leavingMyself = false;
  // Solde de pièces du couple épuisé en cours de partie (voir
  // GameWalletGuard/demande utilisateur) — coupe le micro/vidéo en cours.
  bool _walletDepleted = false;
  // Réglage admin (minutes_per_coin/grace_period_seconds) pour l'anneau de
  // progression coté pièce (voir CoinBillingRing/demande utilisateur) —
  // chargé une seule fois, uniquement utile en mode à distance.
  Map<String, int>? _economyRate;

  // Secousse locale d'une carte tapée hors couleur en phase "response" —
  // voir demande utilisateur : rejetée SANS jamais appeler le transport
  // (validation cliente identique à SuitBattleEngine.respondCard).
  late final AnimationController _rejectController;
  int? _rejectingIndex;

  @override
  void initState() {
    super.initState();
    _state = widget.transport.currentState;
    _subscription = widget.transport.stateStream.listen(_onState);
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

  void _onState(SuitBattleBoardState state) {
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
        allowRematch: widget.onRematch != null,
      ),
    );
    if (rematch == true && widget.onRematch != null && mounted) {
      await widget.onRematch!(context);
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  String _elapsed() {
    final started = _state.startedAt;
    if (started == null) return '0:00';
    final now = _state.pausedAt ?? ServerClock.instance.now();
    final seconds = now.difference(started).inSeconds.clamp(0, 1 << 31);
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
    if (_state.finished || _state.isPaused || !_state.isMyTurn) return;

    if (_state.phase == 'lead') {
      await widget.transport.playLead(widget.user.id, card);
      return;
    }

    if (_state.phase == 'response') {
      final tableCard = _state.tableCard;
      if (tableCard == null) return;
      final valid = SuitBattleEngine.isJoker(card) || SuitBattleEngine.suitOf(card) == SuitBattleEngine.suitOf(tableCard);
      if (!valid) {
        setState(() => _rejectingIndex = index);
        unawaited(_rejectController.forward(from: 0));
        return;
      }
      await widget.transport.respondCard(widget.user.id, card);
    }
  }

  Future<void> _tapCapture() async {
    if (_state.finished || _state.isPaused) return;
    if (!_state.isMyTurn || _state.phase != 'response') return;
    await widget.transport.captureLead(widget.user.id);
  }

  @override
  void dispose() {
    _subscription.cancel();
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

  /// Bouton "Terminer la partie" du popup de solde épuisé (voir
  /// GameWalletGuard) — même geste qu'un abandon volontaire.
  Future<void> _endGameFromWalletDepletion() async {
    _leavingMyself = true;
    await widget.transport.abandon();
    if (mounted) Navigator.of(context).pop();
  }

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
                                      : 'Manche ${_state.roundsCount}',
                                  style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 16, color: theme.primary),
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
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: _TurnBanner(
                              theme: theme,
                              state: _state,
                              partnerName: widget.playerNames[partnerId] ?? LocaleScope.t(context, 'memory_score_player_fallback'),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                            child: _HandFan(
                              cards: _state.partnerSpread,
                              color: partnerColor,
                              interactive: false,
                              rejectingIndex: null,
                              onTapCard: null,
                            ),
                          ),
                          Expanded(
                            child: Center(
                              child: _TableArea(
                                theme: theme,
                                tableCard: _state.tableCard,
                                canCapture: canRespond,
                                onCapture: _tapCapture,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                            child: AnimatedBuilder(
                              animation: _rejectController,
                              builder: (context, _) => _HandFan(
                                cards: _state.mySpread,
                                color: myColor,
                                interactive: canLead || canRespond,
                                rejectingIndex: _rejectingIndex,
                                rejectProgress: _rejectController.value,
                                onTapCard: _tapMyCard,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: _WonPileBadge(color: myColor, count: _state.myWonPile.length),
                      ),
                      Positioned(
                        top: 4,
                        left: 4,
                        child: _WonPileBadge(color: partnerColor, count: _state.partnerWonPile.length),
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
              partnerUserId: partnerId,
              enabled: true,
              paused: _state.isPaused,
              forceEnded: _walletDepleted,
            )
          else if (widget.nearbyComms != null)
            NearbyVoiceOverlay(comms: widget.nearbyComms, enabled: true, paused: _state.isPaused),
          GameWalletGuard(
            boxId: commentsBoxId,
            sessionType: 'suit_battle',
            sessionId: _sessionId,
            onDepletedChanged: (v) => setState(() => _walletDepleted = v),
            onEndGame: _endGameFromWalletDepletion,
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
    if (state.isMyTurn) {
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
  final bool canCapture;
  final VoidCallback onCapture;

  const _TableArea({required this.theme, required this.tableCard, required this.canCapture, required this.onCapture});

  @override
  Widget build(BuildContext context) {
    final card = tableCard;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: _kTableCardWidth,
          height: _kTableCardHeight,
          child: card == null
              ? DottedTablePlaceholder(theme: theme)
              : _PlayingCardFace(card: card, width: _kTableCardWidth, height: _kTableCardHeight),
        ),
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
/// [interactive] = false), toujours face visible dans les deux cas.
class _HandFan extends StatelessWidget {
  final List<String> cards;
  final Color color;
  final bool interactive;
  final int? rejectingIndex;
  final double rejectProgress;
  final void Function(int index, String card)? onTapCard;

  const _HandFan({
    required this.cards,
    required this.color,
    required this.interactive,
    required this.rejectingIndex,
    this.rejectProgress = 0,
    required this.onTapCard,
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
          final card = cards[index];
          final shaking = rejectingIndex == index;
          final shakeOffset = shaking ? math.sin(rejectProgress * math.pi * 6) * 6 * (1 - rejectProgress) : 0.0;

          return Padding(
            padding: EdgeInsets.only(left: index == 0 ? 0 : 22, top: 6),
            child: Transform.translate(
              offset: Offset(shakeOffset, 0),
              child: GestureDetector(
                onTap: interactive ? () => onTapCard?.call(index, card) : null,
                child: Opacity(
                  opacity: interactive ? 1 : 0.92,
                  child: _PlayingCardFace(card: card, width: _kHandCardWidth, height: _kHandCardHeight),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

String _suitSymbolFor(String suit) => switch (suit) {
      'S' => '♠',
      'H' => '♥',
      'D' => '♦',
      'C' => '♣',
      _ => '',
    };

/// Le visage d'une carte — rang + symbole centrés, coloré rouge/noir selon
/// la couleur (même approche que _CardSlot dans war_card_board_screen.dart,
/// voir demande utilisateur : "reprendre l'approche existante"), plus un
/// visage dédié pour les Jokers (absents de "Bataille").
class _PlayingCardFace extends StatelessWidget {
  final String card;
  final double width;
  final double height;

  const _PlayingCardFace({required this.card, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    final isJoker = SuitBattleEngine.isJoker(card);
    final rank = isJoker ? null : card.substring(0, card.length - 1);
    final suit = isJoker ? null : card.substring(card.length - 1);
    final suitSymbol = suit == null ? '' : _suitSymbolFor(suit);
    final isRedSuit = suit == 'H' || suit == 'D';
    final textColor = isJoker ? _kJokerColor : (isRedSuit ? _kRedColor : Colors.black87);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: textColor.withValues(alpha: 0.5), width: 2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 5, offset: Offset(0, 2))],
      ),
      alignment: Alignment.center,
      child: isJoker
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded, color: textColor, size: width * 0.34),
                Text('JOKER', style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: width * 0.14, color: textColor)),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(rank ?? '', style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: width * 0.32, color: textColor)),
                Text(suitSymbol, style: TextStyle(fontSize: width * 0.32, color: textColor)),
              ],
            ),
    );
  }
}

/// Score de fin de partie — copie structurelle de
/// _WarCardScoreboardSheet, mais le "score" affiché est le nombre de
/// cartes CAPTURÉES (pile de gains), pas la taille d'une pile de guerre.
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

  int _wonFor(String userId) => userId == state.creatorId ? state.wonCreator.length : state.wonPartner.length;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final players = playerNames.keys.toList();

    final minutes = state.startedAt != null ? ServerClock.instance.now().difference(state.startedAt!).inSeconds ~/ 60 : 0;
    final seconds = state.startedAt != null ? ServerClock.instance.now().difference(state.startedAt!).inSeconds % 60 : 0;

    // Un abandon ne déclare jamais de gagnant — `winnerUserId` reste `null`
    // sans que `isTie` soit posé pour autant (voir WarCardScoreboardSheet,
    // même principe). Si les deux piles de gains sont malgré tout à égalité
    // à ce moment-là, l'écran doit lire "Nul" plutôt que "Perdu" pour les
    // deux à la fois.
    final effectiveTie = state.isTie || (state.winnerUserId == null && _wonFor(state.creatorId) == _wonFor(state.partnerId));

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
                  : '${playerNames[state.winnerUserId] ?? LocaleScope.t(context, 'memory_score_player_fallback')} a gagné !',
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
                        cardCount: _wonFor(players[i]),
                        isWinner: players[i] == state.winnerUserId,
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
            'cartes',
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

  const _CardBack({required this.color, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    final backColor = dimmed ? color.withValues(alpha: 0.35) : color;
    return Container(
      width: _kTableCardWidth,
      height: _kTableCardHeight,
      decoration: BoxDecoration(
        color: backColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
        boxShadow: dimmed ? null : const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
      ),
      alignment: Alignment.center,
      child: dimmed ? null : Icon(Icons.style_rounded, color: Colors.white.withValues(alpha: 0.55), size: 28),
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
