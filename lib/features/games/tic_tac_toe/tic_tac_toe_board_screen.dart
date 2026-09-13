import 'dart:async';

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
import '../nearby/nearby_comms.dart';
import '../widgets/game_card_widgets.dart' show partnerReferenceLabel;
import '../widgets/game_comment_overlay.dart';
import '../widgets/tic_tac_toe_match_scoreboard.dart';
import '../widgets/game_wallet_guard.dart';
import '../widgets/voice_call_overlay.dart';
import 'tic_tac_toe_engine.dart';
import 'tic_tac_toe_transport.dart';
import 'tic_tac_toe_transport_remote.dart';

/// Plateau de "Morpion à Deux" — UNIQUE écran de jeu partagé par les 3
/// modes (voir TicTacToeTransport), copie structurelle conforme de
/// MemoryGameBoardScreen (pause/reprise, abandon, chrono).
///
/// Grille 5×5, jeu à SCORE (voir TicTacToeEngine) : chaque case n'appartient
/// qu'à UN joueur — l'affichage distingue "mes" cases des cases du binôme
/// par icône/couleur (cœur/étoile) plutôt que par un symbole X/O dont
/// l'assignation ne serait pas forcément la même des deux côtés (voir
/// _isMine). En phase de déplacement, on touche d'abord un de ses pions
/// (sélection) puis n'importe quelle case vide du plateau (destination) —
/// pas de contrainte d'adjacence.
class TicTacToeBoardScreen extends StatefulWidget {
  final Game game;
  final AppUser user;
  final TicTacToeTransport transport;
  final Map<String, String> playerNames;
  final Map<String, String?> playerAvatars;
  final Future<void> Function(BuildContext context)? onRematch;
  final NearbyComms? nearbyComms;
  final String? nearbyMyName;
  final String? nearbyPartnerName;

  const TicTacToeBoardScreen({
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
  State<TicTacToeBoardScreen> createState() => _TicTacToeBoardScreenState();
}

// Durée d'affichage de l'alignement en surbrillance avant que les pions ne
// se dispersent (voir demande utilisateur : "on doit signaler une victoire
// en marquant les case quelque seconde pour permettre a chacun de voir
// clairement" — 3 secondes confirmées).
const _kScoreHighlightDuration = Duration(seconds: 3);

class _TicTacToeBoardScreenState extends State<TicTacToeBoardScreen> {
  late StreamSubscription<TicTacToeBoardState> _subscription;
  late TicTacToeBoardState _state;
  Timer? _clockTimer;
  bool _scoreboardShown = false;
  // Distingue "c'est moi qui viens d'abandonner" (voir _confirmAbandon,
  // déjà géré par le pop immédiat) de "le binôme vient d'abandonner à
  // distance" (voir _maybeShowScoreboard) — seul ce second cas doit
  // afficher la pop-up dédiée plutôt que de rester silencieux.
  bool _leavingMyself = false;
  // Solde de pièces du couple épuisé en cours de partie (voir
  // GameWalletGuard/demande utilisateur) — coupe le micro/vidéo en cours.
  bool _walletDepleted = false;
  int? _selectedPosition;
  // Non-null pendant la fenêtre de surbrillance qui suit un alignement —
  // remplace TEMPORAIREMENT l'affichage de `_state.board` (déjà dispersé)
  // par le plateau tel qu'il était juste avant la dispersion, pour que
  // l'alignement reste visible quelques secondes (voir doc de
  // TicTacToeBoardState.scoredLine/preScatterBoard).
  List<String?>? _highlightBoard;
  List<int>? _highlightedLine;
  Timer? _highlightTimer;

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

  void _onState(TicTacToeBoardState state) {
    if (!mounted) return;
    final justScored = state.scoredLine != null && state.preScatterBoard != null;

    setState(() {
      _state = state;
      _selectedPosition = null;
      if (justScored) {
        _highlightBoard = state.preScatterBoard;
        _highlightedLine = state.scoredLine;
      }
    });

    if (justScored) {
      _showScoreToast();
      _highlightTimer?.cancel();
      _highlightTimer = Timer(_kScoreHighlightDuration, () {
        if (!mounted) return;
        setState(() {
          _highlightBoard = null;
          _highlightedLine = null;
        });
        if (state.finished) _maybeShowScoreboard(state);
      });
      return;
    }

    if (state.finished) _maybeShowScoreboard(state);
  }

  void _maybeShowScoreboard(TicTacToeBoardState state) {
    if (_scoreboardShown) return;
    _scoreboardShown = true;
    if (state.abandoned && !_leavingMyself) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showPartnerLeftDialog());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showScoreboard());
    }
  }

  /// Affichée UNIQUEMENT quand le binôme vient d'abandonner à distance
  /// (voir _maybeShowScoreboard) — jamais quand c'est nous qui venons de le
  /// faire (voir _confirmAbandon, qui referme déjà l'écran tout seul). "OK"
  /// laisse consulter le plateau tel qu'il était ; "Sortir" referme l'écran
  /// tout de suite (voir demande utilisateur).
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

  void _showScoreToast() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(LocaleScope.t(context, 'ttt_point_scored')),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
    final rematch = await showTicTacToeMatchScoreboard(
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

  bool get _myTurnActionable => !widget.transport.requiresTurnToPlay || _state.isMyTurn;

  Future<void> _onTapCell(int index) async {
    if (_state.finished || _state.isPaused) return;
    // Plateau figé pendant la fenêtre de surbrillance d'un alignement — le
    // plateau affiché (`_highlightBoard`) n'est de toute façon pas l'état
    // réel courant (voir doc de champ).
    if (_highlightBoard != null) return;
    if (!_myTurnActionable) return;

    final activePlayer = widget.transport.requiresTurnToPlay ? _state.myUserId : (_state.currentTurnUserId ?? _state.myUserId);
    final inPlacementPhase = _state.isPlacementPhaseFor(activePlayer);

    if (inPlacementPhase) {
      if (_state.board[index] != null) return;
      await widget.transport.place(index);
      return;
    }

    // Phase de déplacement : sélectionner d'abord un de ses pions, puis
    // n'importe quelle case vide du plateau comme destination (pas de
    // contrainte d'adjacence, voir demande utilisateur).
    final occupant = _state.board[index];
    if (_selectedPosition == null) {
      if (occupant == activePlayer) {
        setState(() => _selectedPosition = index);
      }
      return;
    }

    if (index == _selectedPosition) {
      setState(() => _selectedPosition = null);
      return;
    }
    if (occupant == activePlayer) {
      setState(() => _selectedPosition = index);
      return;
    }
    if (occupant != null) return;

    final from = _selectedPosition!;
    setState(() => _selectedPosition = null);
    await widget.transport.move(from, index);
  }

  String _elapsed() {
    final started = _state.startedAt;
    if (started == null) return '0:00';
    final now = _state.pausedAt ?? ServerClock.instance.now();
    // max(0, ...) : horloge du téléphone en retard sur celle du serveur
    // (courant sur un appareil de test) -> différence négative, un chrono
    // négatif n'a aucun sens à l'écran (même correctif que MemoryGameBoardScreen).
    final seconds = now.difference(started).inSeconds.clamp(0, 1 << 31);
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _subscription.cancel();
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
    return transport is RemoteTicTacToeTransport ? transport.boxId : null;
  }

  String get _sessionId {
    final transport = widget.transport;
    return transport is RemoteTicTacToeTransport ? transport.sessionId : '';
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
    final turnName = _state.currentTurnUserId != null ? widget.playerNames[_state.currentTurnUserId] : null;
    final activePlayer = widget.transport.requiresTurnToPlay ? _state.myUserId : (_state.currentTurnUserId ?? _state.myUserId);
    final phaseLabel = _state.finished
        ? null
        : (_state.isPlacementPhaseFor(activePlayer)
            ? LocaleScope.t(context, 'ttt_phase_placement')
            : LocaleScope.t(context, 'ttt_phase_movement'));

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
          // Masqué une fois la partie terminée (victoire) — sinon un retap
          // n'a plus aucun effet visible (la partie est déjà `finished`,
          // voir _onTapCell) et donne l'impression que le bouton "ne
          // fonctionne pas" (voir demande utilisateur).
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
          // Une fois la partie finie, le seul moyen de rejouer était la
          // fenêtre de score qui vient de se fermer — bouton permanent une
          // fois qu'elle a disparu (voir demande utilisateur : "comment
          // rejouer ou quitter à partir de là" — quitter reste la flèche
          // retour standard, déjà là).
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
                        // Une fois la partie finie, "Au tour de..." n'a
                        // plus de sens (voir demande utilisateur, capture :
                        // le tour restait affiché alors que la partie était
                        // déjà gagnée).
                        _state.finished
                            ? LocaleScope.t(context, 'game_board_finished_label')
                            : (widget.transport.requiresTurnToPlay
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
              if (phaseLabel != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      phaseLabel,
                      style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w600, color: theme.textOnBackgroundMuted),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                child: Row(
                  children: [
                    for (final userId in widget.playerNames.keys) ...[
                      if (userId != widget.playerNames.keys.first) const SizedBox(width: 10),
                      Expanded(
                        child: _TicTacToePlayerChip(
                          theme: theme,
                          name: widget.playerNames[userId] ?? '',
                          avatar: widget.playerAvatars[userId],
                          mine: _markerFor(userId) == _Marker.heart,
                          active: _state.currentTurnUserId == userId,
                          score: _state.scoreFor(userId),
                          targetScore: _state.targetScore,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Stack(
                        children: [
                          GridView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: TicTacToeEngine.gridSize,
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 6,
                            ),
                            itemCount: TicTacToeEngine.cellCount,
                            itemBuilder: (context, index) {
                              final displayBoard = _highlightBoard ?? _state.board;
                              final occupant = displayBoard[index];
                              return _TicTacToeCellTile(
                                theme: theme,
                                marker: occupant == null ? null : _markerFor(occupant),
                                selected: _selectedPosition == index,
                                movableTarget: _highlightBoard == null && _selectedPosition != null && occupant == null,
                                justScored: _highlightedLine?.contains(index) ?? false,
                                onTap: () => _onTapCell(index),
                              );
                            },
                          ),
                          if (_state.isPaused)
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
          ),
        GameWalletGuard(
          boxId: commentsBoxId,
          sessionType: 'tic_tac_toe',
          sessionId: _sessionId,
          onDepletedChanged: (v) => setState(() => _walletDepleted = v),
          onEndGame: _endGameFromWalletDepletion,
        ),
      ],
      ),
    );
  }

  /// Cœur pour la première des deux id (par ordre lexicographique) et
  /// étoile pour l'autre — déterministe des deux côtés SANS dépendre de
  /// qui a créé la partie ni de l'ordre d'insertion de [playerNames]
  /// (différent sur chaque appareil, voir doc de classe) : les deux
  /// identifiants (réels ou rôles Nearby 'host'/'guest') sont toujours les
  /// mêmes deux valeurs, quel que soit l'appareil qui les compare.
  _Marker _markerFor(String userId) {
    final ids = widget.playerNames.keys.toList()..sort();
    return userId == ids.first ? _Marker.heart : _Marker.star;
  }
}

enum _Marker { heart, star }

class _TicTacToePlayerChip extends StatelessWidget {
  final ThemePalette theme;
  final String name;
  final String? avatar;
  final bool mine;
  final bool active;
  final int score;
  final int targetScore;

  const _TicTacToePlayerChip({
    required this.theme,
    required this.name,
    required this.avatar,
    required this.mine,
    required this.active,
    required this.score,
    required this.targetScore,
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
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: theme.textOnBackground),
            ),
          ),
          const SizedBox(width: 4),
          Icon(mine ? Icons.favorite_rounded : Icons.star_rounded, size: 15, color: theme.primary),
          const SizedBox(width: 4),
          Text(
            '$score/$targetScore',
            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w800, color: theme.primary),
          ),
        ],
      ),
    );
  }
}

class _TicTacToeCellTile extends StatelessWidget {
  final ThemePalette theme;
  final _Marker? marker;
  final bool selected;
  final bool movableTarget;
  // Fait partie de l'alignement qui vient de rapporter un point — mis en
  // avant en doré pendant la fenêtre de surbrillance (voir
  // _kScoreHighlightDuration) pour que l'alignement soit très visible
  // avant la dispersion (voir demande utilisateur).
  final bool justScored;
  final VoidCallback onTap;

  const _TicTacToeCellTile({
    required this.theme,
    required this.marker,
    required this.selected,
    required this.movableTarget,
    required this.justScored,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFFFC940);
    return Material(
      color: justScored
          ? gold.withValues(alpha: 0.3)
          : selected
              ? theme.primary.withValues(alpha: 0.28)
              : movableTarget
                  ? theme.primary.withValues(alpha: 0.14)
                  : theme.surface.withValues(alpha: theme.isDark ? 0.5 : 0.85),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: justScored ? gold : theme.primary.withValues(alpha: selected ? 0.6 : (movableTarget ? 0.4 : 0.18)),
              width: justScored ? 2 : 1,
            ),
          ),
          child: Center(
            child: marker == null
                ? null
                : Icon(
                    marker == _Marker.heart ? Icons.favorite_rounded : Icons.star_rounded,
                    size: 22,
                    color: justScored ? gold : theme.primary,
                  ),
          ),
        ),
      ),
    );
  }
}
