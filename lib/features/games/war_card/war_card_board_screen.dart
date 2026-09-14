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
import '../../shop/wallet_balance_notifier.dart';
import '../game_service.dart';
import '../nearby/nearby_comms.dart';
import '../widgets/coin_billing_ring.dart';
import '../widgets/game_card_widgets.dart' show partnerReferenceLabel;
import '../widgets/game_comment_overlay.dart';
import '../widgets/game_wallet_guard.dart';
import '../widgets/nearby_voice_overlay.dart';
import '../widgets/voice_call_overlay.dart';
import '../widgets/war_card_match_scoreboard.dart';
import 'war_card_transport.dart';
import 'war_card_transport_local.dart';
import 'war_card_transport_remote.dart';

const _kRedColor = Color(0xFFE5484D);
const _kBlueColor = Color(0xFF2F6FED);

/// Plateau de "Bataille" — UNIQUE écran de jeu partagé par les 3 modes
/// (voir WarCardTransport), copie structurelle conforme des autres jeux
/// (pause/reprise, chrono), SAUF le pattern de tap : en pass-and-play
/// (voir [LocalWarCardTransport]) DEUX boutons "Retourner" distincts sont
/// affichés (un par joueur) ; en distant/présentiel connecté, un seul
/// bouton pour "moi".
class WarCardBoardScreen extends StatefulWidget {
  final Game game;
  final AppUser user;
  final WarCardTransport transport;
  final Map<String, String> playerNames;
  final Map<String, String?> playerAvatars;
  final Future<void> Function(BuildContext context)? onRematch;
  final NearbyComms? nearbyComms;
  final String? nearbyMyName;
  final String? nearbyPartnerName;

  const WarCardBoardScreen({
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
  State<WarCardBoardScreen> createState() => _WarCardBoardScreenState();
}

class _WarCardBoardScreenState extends State<WarCardBoardScreen> {
  late StreamSubscription<WarCardBoardState> _subscription;
  late WarCardBoardState _state;
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
  // Solde du couple AU LANCEMENT de cette partie précise (voir demande
  // utilisateur : "comment on sait combien de pièce déjà consommer ?") —
  // la différence avec le solde ACTUEL (WalletBalanceNotifier) donne le
  // nombre de pièces consommées depuis le début.
  int? _startingBalance;

  // Séquence "duel" (voir demande utilisateur) : chaque carte monte
  // IMMÉDIATEMENT au centre dès qu'elle est retournée (voir _tapFlip) et
  // y attend l'autre ; une fois les deux réunies, elles y restent 2s
  // avant de repartir ensemble vers la pile du VAINQUEUR — voir
  // _runDuelAnimation.
  int _lastAnimatedRoundsCount = 0;
  bool _duelActive = false;
  _DuelPhase _duelPhase = _DuelPhase.atStage;
  String? _duelCreatorCard;
  String? _duelPartnerCard;
  String? _duelWinnerId;
  bool _duelWasBattle = false;
  // Compteurs figés le temps du duel (voir demande utilisateur : chacun
  // affiche n-1 dès son tap, le vainqueur ne remonte à n+1 [-1 puis +2]
  // qu'au moment où les deux cartes rejoignent sa pile, pas avant) — sans
  // ça, `_state.pileCreator/pilePartner` déjà résolus révéleraient le
  // compte final instantanément, avant même que l'animation ne joue.
  int? _duelCreatorDisplayCount;
  int? _duelPartnerDisplayCount;

  bool get _isLocalPassAndPlay => widget.transport is LocalWarCardTransport;

  @override
  void initState() {
    super.initState();
    _state = widget.transport.currentState;
    _subscription = widget.transport.stateStream.listen(_onState);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // Masque la barre de nav système ET celle de l'app le temps de la
    // partie — voir le correctif appliqué à NumberHuntBoardScreen.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppRouter.showGlobalNavBar.value = false;
    });
    if (_commentsBoxId != null) {
      _loadEconomyRate();
      _captureStartingBalance();
    }
  }

  Future<void> _captureStartingBalance() async {
    await WalletBalanceNotifier.instance.refresh();
    if (mounted) setState(() => _startingBalance = WalletBalanceNotifier.instance.balance);
  }

  int? _coinsConsumed() {
    final starting = _startingBalance;
    if (starting == null) return null;
    final consumed = starting - WalletBalanceNotifier.instance.balance;
    return consumed < 0 ? 0 : consumed;
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

  void _onState(WarCardBoardState state) {
    if (!mounted) return;

    // Une NOUVELLE manche vient de se résoudre (roundsCount vient
    // d'augmenter) — voir demande utilisateur : lance la séquence
    // "duel" plutôt que de juste afficher le résultat instantanément.
    // Le vainqueur se déduit de la pile qui vient de GRANDIR (comparaison
    // AVANT/APRÈS, même technique que pour détecter un tap de partage
    // manuel dans l'écran de pré-partie).
    if (state.roundsCount > _lastAnimatedRoundsCount && state.lastRoundResult.isNotEmpty) {
      _lastAnimatedRoundsCount = state.roundsCount;
      final creatorCard = state.lastCardFor(state.creatorId);
      final partnerCard = state.lastCardFor(state.partnerId);
      final winnerId = state.pileCreator.length > _state.pileCreator.length ? state.creatorId : state.partnerId;
      // AVANT la mise à jour de _state (donc AVANT résolution) — les deux
      // piles ont encore leur taille D'ORIGINE ici, voir doc de classe.
      final preCreatorCount = _state.pileCreator.length;
      final prePartnerCount = _state.pilePartner.length;
      if (creatorCard != null && partnerCard != null) {
        unawaited(_runDuelAnimation(
          creatorCard: creatorCard,
          partnerCard: partnerCard,
          winnerId: winnerId,
          wasBattle: state.lastRoundWasBattle,
          preCreatorCount: preCreatorCount,
          prePartnerCount: prePartnerCount,
        ));
      }
    }

    setState(() => _state = state);

    if (state.finished && !_scoreboardShown && !_duelActive) {
      _scoreboardShown = true;
      if (state.abandoned && !_leavingMyself) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showPartnerLeftDialog());
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showScoreboard());
      }
    }
  }

  /// Voir demande utilisateur : chaque carte monte IMMÉDIATEMENT au
  /// centre ("VS") dès qu'elle est retournée (voir _tapFlip), et y
  /// attend que l'autre la rejoigne — cette méthode ne fait donc que
  /// gérer la suite, une fois LES DEUX arrivées : 2 secondes ensemble au
  /// centre, puis repartent ensemble rejoindre la pile du vainqueur.
  Future<void> _runDuelAnimation({
    required String creatorCard,
    required String partnerCard,
    required String winnerId,
    required bool wasBattle,
    required int preCreatorCount,
    required int prePartnerCount,
  }) async {
    if (!mounted) return;
    setState(() {
      _duelActive = true;
      _duelPhase = _DuelPhase.atStage;
      _duelCreatorCard = creatorCard;
      _duelPartnerCard = partnerCard;
      _duelWinnerId = winnerId;
      _duelWasBattle = wasBattle;
      // Voir demande utilisateur : chacun affiche n-1 dès son tap — la
      // pile complète (les deux cartes) ne rejoint le vainqueur qu'à la
      // toute fin, voir le `setState` plus bas.
      _duelCreatorDisplayCount = preCreatorCount - 1;
      _duelPartnerDisplayCount = prePartnerCount - 1;
    });

    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;
    setState(() => _duelPhase = _DuelPhase.atWinner);

    await Future.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    setState(() {
      _duelActive = false;
      _duelCreatorCard = null;
      _duelPartnerCard = null;
      _duelWinnerId = null;
      // Bascule sur le vrai compte (déjà résolu dans `_state`) exactement
      // au moment où les deux cartes "rejoignent" la pile du vainqueur —
      // voir demande utilisateur.
      _duelCreatorDisplayCount = null;
      _duelPartnerDisplayCount = null;
    });

    if (_state.finished && !_scoreboardShown) {
      _scoreboardShown = true;
      if (_state.abandoned && !_leavingMyself) {
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
    final rematch = await showWarCardMatchScoreboard(
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

  String _elapsed() {
    final started = _state.startedAt;
    if (started == null) return '0:00';
    final now = _state.pausedAt ?? ServerClock.instance.now();
    // Le chrono attend la même période de grâce que l'anneau de pièce
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

  bool _pendingFlipFor(String userId) => userId == _state.creatorId ? _state.pendingFlipCreator : _state.pendingFlipPartner;

  List<String> _pileFor(String userId) => userId == _state.creatorId ? _state.pileCreator : _state.pilePartner;

  /// "cliquer sur la carte et elle se retourne" (voir demande
  /// utilisateur) — [userId] : creatorId ou partnerId, jamais "moi" (voir
  /// doc de classe). La révélation "en attente de l'autre" affichée tant
  /// que la manche n'est pas résolue n'est PAS une valeur figée au moment
  /// du tap : elle se lit en LIVE depuis `_state.pileCreator/pilePartner`
  /// (voir _WarCardDuelArea) — aucune copie qui pourrait diverger de la
  /// vérité côté moteur si l'état se met à jour entre-temps.
  Future<void> _tapFlip(String userId) async {
    if (_state.finished || _state.isPaused || _duelActive) return;
    if (_pendingFlipFor(userId)) return;
    if (_pileFor(userId).isEmpty) return;

    await widget.transport.flip(userId);
  }

  /// Affiche SA propre pile en éventail (voir demande utilisateur) — sans
  /// incidence sur l'équité de la partie : la Bataille n'a aucune
  /// décision à prendre, connaître l'ordre de ses propres cartes à
  /// l'avance ne change rien à l'issue.
  void _showFan(BuildContext context, List<String> pile, Color color) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _WarCardFanSheet(pile: pile, color: color),
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
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

  Future<void> _shuffle() => widget.transport.shuffleDeck();

  Future<void> _dealAutomatic() => widget.transport.dealAutomatic();

  Future<void> _dealManualStep() => widget.transport.dealManualStep();

  Future<void> _readyUp() => widget.transport.readyUp();

  /// Bouton "Terminer la partie" du popup de solde épuisé (voir
  /// GameWalletGuard) — même geste qu'un abandon volontaire, sans re-passer
  /// par la confirmation (déjà confirmé en fermant ce popup-là).
  Future<void> _endGameFromWalletDepletion() async {
    _leavingMyself = true;
    await widget.transport.abandon();
    if (mounted) Navigator.of(context).pop();
  }

  String? get _commentsBoxId {
    final transport = widget.transport;
    return transport is RemoteWarCardTransport ? transport.boxId : null;
  }

  String get _sessionId {
    final transport = widget.transport;
    return transport is RemoteWarCardTransport ? transport.sessionId : '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final commentsBoxId = _commentsBoxId;

    if (!_state.dealt) {
      return _WarCardPreDealScreen(
        game: widget.game,
        theme: theme,
        state: _state,
        playerNames: widget.playerNames,
        colorFor: _colorFor,
        onShuffle: _shuffle,
        onDealAutomatic: _dealAutomatic,
        onDealManualStep: _dealManualStep,
      );
    }

    if (!_state.started) {
      return _WarCardReadyScreen(
        game: widget.game,
        theme: theme,
        state: _state,
        playerNames: widget.playerNames,
        colorFor: _colorFor,
        onReadyUp: _readyUp,
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
                              : LocaleScope.t(context, 'war_card_rounds_played', {'count': '${_state.roundsCount}'}),
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
                              if (_coinsConsumed() != null) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '-${_coinsConsumed()}',
                                  style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: theme.primary),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _WarCardDuelArea(
                      theme: theme,
                      state: _state,
                      leftId: _isLocalPassAndPlay ? _state.creatorId : widget.user.id,
                      rightId: _isLocalPassAndPlay ? _state.partnerId : _partnerId(),
                      isLocalMode: _isLocalPassAndPlay,
                      playerNames: widget.playerNames,
                      colorFor: _colorFor,
                      duelActive: _duelActive,
                      duelPhase: _duelPhase,
                      duelCreatorCard: _duelCreatorCard,
                      duelPartnerCard: _duelPartnerCard,
                      duelWinnerId: _duelWinnerId,
                      duelWasBattle: _duelWasBattle,
                      duelCreatorDisplayCount: _duelCreatorDisplayCount,
                      duelPartnerDisplayCount: _duelPartnerDisplayCount,
                      onTapFlip: _tapFlip,
                      onTapPeek: (userId) => _showFan(context, _pileFor(userId), _colorFor(userId)),
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
            partnerUserId: _partnerId(),
            enabled: true,
            paused: _state.isPaused,
            forceEnded: _walletDepleted || _state.isPaused,
          )
        else if (widget.nearbyComms != null)
          NearbyVoiceOverlay(comms: widget.nearbyComms, enabled: true, paused: _state.isPaused),
        GameWalletGuard(
          boxId: commentsBoxId,
          sessionType: 'war_card',
          sessionId: _sessionId,
          onDepletedChanged: (v) => setState(() => _walletDepleted = v),
          onEndGame: _endGameFromWalletDepletion,
        ),
      ],
      ),
    );
  }

  String _partnerId() => widget.playerNames.keys.firstWhere((id) => id != widget.user.id, orElse: () => widget.user.id);
}

/// Phase "avant partie" (voir demande utilisateur) : les 52 cartes sont
/// visibles empilées ENSEMBLE, "Battre" les remélange réellement (pas
/// juste une animation) autant de fois qu'on veut, tant que le partage
/// n'a pas commencé. Le partage manuel n'a PAS de bouton dédié : on tape
/// DIRECTEMENT sur le paquet (voir demande utilisateur), en bas de
/// l'écran — chaque tap envoie une carte du dessus vers la pile de
/// gauche et une carte du dessous vers la pile de droite, visibles en
/// haut à côté du nom de chacun. "Partage automatique" reste un bouton
/// séparé pour distribuer instantanément le reste du paquet.
class _WarCardPreDealScreen extends StatefulWidget {
  final Game game;
  final ThemePalette theme;
  final WarCardBoardState state;
  final Map<String, String> playerNames;
  final Color Function(String userId) colorFor;
  final Future<void> Function() onShuffle;
  final Future<void> Function() onDealAutomatic;
  final Future<void> Function() onDealManualStep;

  const _WarCardPreDealScreen({
    required this.game,
    required this.theme,
    required this.state,
    required this.playerNames,
    required this.colorFor,
    required this.onShuffle,
    required this.onDealAutomatic,
    required this.onDealManualStep,
  });

  @override
  State<_WarCardPreDealScreen> createState() => _WarCardPreDealScreenState();
}

class _WarCardPreDealScreenState extends State<_WarCardPreDealScreen> with TickerProviderStateMixin {
  bool _busy = false;
  late final AnimationController _shuffleController;
  // Voir demande utilisateur : "on doit voir les cartes se déplacer du
  // paquet vers leur destination... deux cartes [l'une après l'autre]" —
  // l'affichage reste figé sur l'état PRÉCÉDENT pendant que ce contrôleur
  // anime le trajet, et ne bascule sur le nouvel état qu'une fois le vol
  // terminé (voir didUpdateWidget/_animateDeal).
  late final AnimationController _flightController;
  late WarCardBoardState _displayState;

  final _overlayKey = GlobalKey();
  final _deckKey = GlobalKey();
  final _creatorSlotKey = GlobalKey();
  final _partnerSlotKey = GlobalKey();
  // Deux points de départ DISTINCTS (voir demande utilisateur : "on a
  // l'impression que les deux cartes partent toutes du dessus" — le
  // départ doit visuellement correspondre à la vraie règle, une carte du
  // DESSUS et une du DESSOUS du paquet, voir WarCardEngine.dealManualStep).
  Offset? _flightFromTop;
  Offset? _flightFromBottom;
  Offset? _flightTo;
  bool _flightToCreator = true;

  @override
  void initState() {
    super.initState();
    _displayState = widget.state;
    _shuffleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _flightController = AnimationController(vsync: this, duration: const Duration(milliseconds: 640));
  }

  @override
  void didUpdateWidget(covariant _WarCardPreDealScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // UN seul tap de partage manuel ajoute EXACTEMENT deux cartes, mais
    // toujours du MÊME côté (voir demande utilisateur : "les deux cartes
    // qui sortent doivent aller pour une [seule] personne") — un partage
    // automatique (ou un battage, qui ne change aucune longueur de pile)
    // n'a pas vocation à être animé carte par carte.
    final creatorGrew = widget.state.pileCreator.length - _displayState.pileCreator.length;
    final partnerGrew = widget.state.pilePartner.length - _displayState.pilePartner.length;
    final isManualStep = (creatorGrew == 2 && partnerGrew == 0) || (partnerGrew == 2 && creatorGrew == 0);
    if (_flightController.isAnimating) return;
    if (isManualStep) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _animateDeal(toCreator: creatorGrew == 2));
    } else {
      _displayState = widget.state;
    }
  }

  @override
  void dispose() {
    _shuffleController.dispose();
    _flightController.dispose();
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

  Offset? _centerOf(GlobalKey key, RenderBox ancestor) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;

    return box.localToGlobal(Offset.zero, ancestor: ancestor) + Offset(box.size.width / 2, box.size.height / 2);
  }

  /// Les positions RÉELLES de la carte du DESSUS (deck[0], la face visible
  /// en bas à gauche du tas — voir _WarCardFullStack) et de la carte du
  /// DESSOUS (le dos le plus enfoui, en haut à droite) — voir demande
  /// utilisateur : le vol doit visiblement partir de deux cartes
  /// DIFFÉRENTES du tas, pas d'un même point arbitraire.
  ({Offset top, Offset bottom})? _deckEdges(GlobalKey key, RenderBox ancestor) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;

    final topLeft = box.localToGlobal(Offset.zero, ancestor: ancestor);
    // Carte du dessus : Positioned(left: 0, bottom: 0) dans _WarCardFullStack.
    final top = topLeft + const Offset(_kCardWidth / 2, 0) + Offset(0, box.size.height - _kCardHeight / 2);
    // Carte du dessous : Positioned(right: 0, top: 0), la toute première
    // dessinée (donc la plus enfouie sous les autres dos).
    final bottom = topLeft + Offset(box.size.width - _kCardWidth / 2, _kCardHeight / 2);

    return (top: top, bottom: bottom);
  }

  /// Anime le trajet des deux cartes du paquet vers LA MÊME pile, L'UNE
  /// APRÈS L'AUTRE (voir demande utilisateur), avant de basculer
  /// l'affichage sur le nouvel état (compte à jour de la pile).
  Future<void> _animateDeal({required bool toCreator}) async {
    final ancestor = _overlayKey.currentContext?.findRenderObject() as RenderBox?;
    final deckEdges = ancestor == null ? null : _deckEdges(_deckKey, ancestor);
    final destCenter = ancestor == null ? null : _centerOf(toCreator ? _creatorSlotKey : _partnerSlotKey, ancestor);

    if (ancestor == null || deckEdges == null || destCenter == null) {
      // Mise en page pas encore prête (première frame) — pas d'animation
      // possible, on répercute directement le nouvel état.
      if (mounted) setState(() => _displayState = widget.state);
      return;
    }

    setState(() {
      _flightFromTop = deckEdges.top;
      _flightFromBottom = deckEdges.bottom;
      _flightTo = destCenter;
      _flightToCreator = toCreator;
    });

    await _flightController.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _displayState = widget.state;
      _flightFromTop = null;
      _flightFromBottom = null;
      _flightTo = null;
    });
    _flightController.reset();
  }

  /// "déplier les cartes et on peut voir" (voir demande utilisateur) —
  /// réutilise la même feuille "éventail" que pour voir sa propre pile en
  /// cours de partie, avec un texte adapté (le paquet n'appartient encore
  /// à personne).
  void _peekDeck(BuildContext context, List<String> deck, Color color) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _WarCardFanSheet(
        pile: deck,
        color: color,
        title: LocaleScope.t(context, 'war_card_predeal_peek_title', {'count': '${deck.length}'}),
        subtitle: LocaleScope.t(context, 'war_card_predeal_peek_subtitle'),
      ),
    );
  }

  /// Voir demande utilisateur : plutôt que de cacher Battre/Partage
  /// automatique/l'œil une fois le partage manuel entamé, ils restent
  /// visibles mais grisés — un tap dessus affiche cette info quelques
  /// secondes au lieu de rien faire silencieusement.
  void _showLockedInfo(BuildContext context) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(LocaleScope.t(context, 'war_card_predeal_locked_hint')),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<Widget> _buildFlyingCards() {
    final fromTop = _flightFromTop;
    final fromBottom = _flightFromBottom;
    final to = _flightTo;
    if (fromTop == null || fromBottom == null || to == null) return const [];

    final color = widget.colorFor(_flightToCreator ? _displayState.creatorId : _displayState.partnerId);
    // Les DEUX cartes vont à LA MÊME pile (voir demande utilisateur), l'une
    // après l'autre — un léger décalage entre les deux points d'arrivée
    // pour qu'on distingue bien qu'il s'agit de deux cartes, pas une seule.
    const jitter = Offset(7, -5);

    return [
      // La carte du DESSUS du paquet — part du HAUT du tas.
      AnimatedBuilder(
        animation: _flightController,
        builder: (context, _) {
          // Sature à 1.0 dès la moitié du trajet total : la première
          // carte arrive et RESTE visible sur la pile pendant que la
          // seconde s'envole — les deux ne disparaissent qu'ensemble, en
          // même temps que l'affichage bascule sur le nouvel état.
          final phase = Curves.easeInOut.transform((_flightController.value.clamp(0.0, 0.5)) / 0.5);
          final pos = Offset.lerp(fromTop, to - jitter, phase)!;

          return Positioned(
            left: pos.dx - _kCardWidth / 2,
            top: pos.dy - _kCardHeight / 2,
            child: _CardBack(color: color),
          );
        },
      ),
      // La carte du DESSOUS du paquet — part du BAS du tas.
      AnimatedBuilder(
        animation: _flightController,
        builder: (context, _) {
          if (_flightController.value <= 0.5) return const SizedBox.shrink();
          final phase = Curves.easeInOut.transform((_flightController.value - 0.5) / 0.5);
          final pos = Offset.lerp(fromBottom, to + jitter, phase)!;

          return Positioned(
            left: pos.dx - _kCardWidth / 2,
            top: pos.dy - _kCardHeight / 2,
            child: _CardBack(color: color),
          );
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final state = _displayState;
    final deck = state.deck;
    final started = state.pileCreator.isNotEmpty || state.pilePartner.isNotEmpty;
    final canTapDeck = !_busy && !_flightController.isAnimating && deck.isNotEmpty;

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
          child: Stack(
            key: _overlayKey,
            fit: StackFit.expand,
            children: [
              // Petit écran (voir demande utilisateur) : le contenu défile
              // au lieu de déborder — `minHeight` garde le rendu "plein
              // écran + Expanded centré" habituel sur un écran normal,
              // tout en autorisant le scroll si ça ne rentre pas.
              LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: _buildBody(theme, state, deck, started, canTapDeck),
                    ),
                  ),
                ),
              ),
              ..._buildFlyingCards(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemePalette theme, WarCardBoardState state, List<String> deck, bool started, bool canTapDeck) {
    return Column(
            children: [
              // Les deux piles en construction, à côté du nom de chacun —
              // voir demande utilisateur : "une carte du bas et une du
              // haut se positionnent en haut à droite ou à gauche à côté
              // du nom".
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // `card: null` en permanence ici (voir demande
                    // utilisateur : "les cartes ne doivent pas se
                    // retourner pour être visibles" pendant le partage) —
                    // seul le compte progresse, jamais l'identité de la
                    // carte reçue tant qu'on est sur cet écran.
                    KeyedSubtree(
                      key: _creatorSlotKey,
                      child: _CardSlot(
                        card: null,
                        color: widget.colorFor(state.creatorId),
                        label: widget.playerNames[state.creatorId] ?? '',
                        pileCount: state.pileCreator.length,
                      ),
                    ),
                    KeyedSubtree(
                      key: _partnerSlotKey,
                      child: _CardSlot(
                        card: null,
                        color: widget.colorFor(state.partnerId),
                        label: widget.playerNames[state.partnerId] ?? '',
                        pileCount: state.pilePartner.length,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          LocaleScope.t(context, 'war_card_predeal_title'),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: theme.textOnBackground),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          started
                              ? LocaleScope.t(context, 'war_card_predeal_manual_progress', {'count': '${deck.length}'})
                              : LocaleScope.t(context, 'war_card_predeal_subtitle'),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Le paquet, EN BAS de l'écran (voir demande utilisateur) —
              // c'est lui qu'on tape directement pour distribuer, pas de
              // bouton "Distribuer" séparé.
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Column(
                  children: [
                    // Battre / partage automatique n'ont plus de sens une
                    // fois le partage MANUEL déjà entamé — plutôt que de
                    // les cacher, ils restent visibles mais GRISÉS, et un
                    // tap dessus affiche une info explicative quelques
                    // secondes (voir demande utilisateur) — idem pour
                    // l'œil (voir plus bas).
                    _LockableAction(
                      locked: started,
                      onLockedTap: () => _showLockedInfo(context),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: (started || _busy) ? null : () => _run(widget.onShuffle, animateShuffle: true),
                          icon: const Icon(Icons.shuffle_rounded),
                          label: Text(LocaleScope.t(context, 'war_card_predeal_shuffle')),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _LockableAction(
                      locked: started,
                      onLockedTap: () => _showLockedInfo(context),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: (started || _busy) ? null : () => _run(widget.onDealAutomatic),
                          icon: const Icon(Icons.flash_on_rounded),
                          label: Text(LocaleScope.t(context, 'war_card_predeal_deal_auto')),
                          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    AnimatedBuilder(
                      animation: _shuffleController,
                      builder: (context, child) {
                        // Petite secousse latérale pendant l'animation de
                        // battage — juste assez pour se lire comme un vrai
                        // battage de cartes, pas une distraction permanente.
                        final shake = math.sin(_shuffleController.value * math.pi * 6) * 6 * (1 - _shuffleController.value);
                        return Transform.translate(offset: Offset(shake, 0), child: child);
                      },
                      child: KeyedSubtree(
                        key: _deckKey,
                        child: GestureDetector(
                          onTap: canTapDeck ? () => _run(widget.onDealManualStep) : null,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              _WarCardFullStack(count: deck.length, color: theme.primary),
                              if (deck.isNotEmpty)
                                Positioned(
                                  top: -8,
                                  right: -8,
                                  child: Opacity(
                                    opacity: started ? 0.4 : 1,
                                    child: _WarCardPeekButton(
                                      color: theme.primary,
                                      onTap: started ? () => _showLockedInfo(context) : () => _peekDeck(context, deck, theme.primary),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      LocaleScope.t(context, 'war_card_predeal_count', {'count': '${deck.length}'}),
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w800, color: theme.primary),
                    ),
                    if (deck.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        LocaleScope.t(context, 'war_card_predeal_tap_hint'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
  }
}

/// Phase "prêt ?" (voir demande utilisateur) : une fois le paquet
/// entièrement distribué, les deux piles se recentrent à l'écran (plus de
/// boutons Battre/Partage auto/œil), et un bouton "Commencer" apparaît.
/// En pass-and-play UN tap suffit (les deux rôles sont sur le même
/// appareil, voir [LocalWarCardTransport.readyUp]) ; à distance/présentiel
/// connecté, LES DEUX doivent taper — copie du principe déjà utilisé pour
/// "Retourner" (voir WarCardEngine.flip), simple attente sans refus
/// explicite tant que l'autre n'a pas confirmé (voir demande utilisateur).
class _WarCardReadyScreen extends StatefulWidget {
  final Game game;
  final ThemePalette theme;
  final WarCardBoardState state;
  final Map<String, String> playerNames;
  final Color Function(String userId) colorFor;
  final Future<void> Function() onReadyUp;

  const _WarCardReadyScreen({
    required this.game,
    required this.theme,
    required this.state,
    required this.playerNames,
    required this.colorFor,
    required this.onReadyUp,
  });

  @override
  State<_WarCardReadyScreen> createState() => _WarCardReadyScreenState();
}

class _WarCardReadyScreenState extends State<_WarCardReadyScreen> with SingleTickerProviderStateMixin {
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
                        _CardSlot(
                          card: null,
                          color: widget.colorFor(state.creatorId),
                          label: widget.playerNames[state.creatorId] ?? '',
                          pileCount: state.pileCreator.length,
                        ),
                        const SizedBox(width: 24),
                        _CardSlot(
                          card: null,
                          color: widget.colorFor(state.partnerId),
                          label: widget.playerNames[state.partnerId] ?? '',
                          pileCount: state.pilePartner.length,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  LocaleScope.t(context, 'war_card_ready_title'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: theme.textOnBackground),
                ),
                const SizedBox(height: 6),
                Text(
                  state.iAmReady
                      ? LocaleScope.t(context, 'war_card_ready_waiting', {'name': partnerName})
                      : (state.partnerIsReady
                          ? LocaleScope.t(context, 'war_card_ready_partner_wants', {'name': partnerName})
                          : LocaleScope.t(context, 'war_card_ready_subtitle')),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: (_busy || state.iAmReady) ? null : _tapReady,
                    icon: state.iAmReady
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.play_circle_fill_rounded),
                    label: Text(LocaleScope.t(context, 'war_card_ready_start_button')),
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

/// Enrobe un bouton pour le griser et intercepter le tap quand [locked]
/// — voir demande utilisateur : "au lieu de les cacher ils peuvent
/// rester et grisé, si j'essaie de cliquer un petit info apparaît". Le
/// bouton enrobé doit lui-même désactiver son `onPressed` (mettre `null`)
/// quand [locked] est vrai, sinon son propre gestionnaire de tap capte le
/// geste avant que celui-ci ne remonte jusqu'ici.
class _LockableAction extends StatelessWidget {
  final bool locked;
  final VoidCallback onLockedTap;
  final Widget child;

  const _LockableAction({required this.locked, required this.onLockedTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: locked ? 0.4 : 1,
      child: GestureDetector(
        onTap: locked ? onLockedTap : null,
        child: child,
      ),
    );
  }
}

/// Icône à l'angle du paquet — voir demande utilisateur : "ajoute une
/// icône à l'angle des cartes... si on clique ça déplie les cartes et on
/// peut voir".
class _WarCardPeekButton extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _WarCardPeekButton({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(Icons.visibility_rounded, size: 18, color: color),
        ),
      ),
    );
  }
}

/// Étape de la carte révélée dans la zone de jeu (voir demande
/// utilisateur) : dès qu'elle est retournée, elle monte IMMÉDIATEMENT
/// au centre et y attend ([atStage], voir _tapFlip) — une fois les DEUX
/// arrivées là-haut, elles y restent 2s ensemble avant de repartir
/// rejoindre la pile du vainqueur ([atWinner]).
enum _DuelPhase { atStage, atWinner }

const _kLeftBottomAlign = Alignment(-0.55, -0.1);
const _kRightBottomAlign = Alignment(0.55, -0.1);
const _kLeftStageAlign = Alignment(-0.32, -0.75);
const _kRightStageAlign = Alignment(0.32, -0.75);

/// Zone de jeu principale de "Bataille" — voir demande utilisateur : plus
/// de boutons "Retourner" séparés, on tape DIRECTEMENT sur sa carte (en
/// bas de l'écran, une par côté) pour la jouer ; un œil à l'angle de
/// chaque carte permet de voir sa pile en éventail.
class _WarCardDuelArea extends StatelessWidget {
  final ThemePalette theme;
  final WarCardBoardState state;
  final String leftId;
  final String rightId;
  final bool isLocalMode;
  final Map<String, String> playerNames;
  final Color Function(String userId) colorFor;
  final bool duelActive;
  final _DuelPhase duelPhase;
  final String? duelCreatorCard;
  final String? duelPartnerCard;
  final String? duelWinnerId;
  final bool duelWasBattle;
  final int? duelCreatorDisplayCount;
  final int? duelPartnerDisplayCount;
  final Future<void> Function(String userId) onTapFlip;
  final void Function(String userId) onTapPeek;

  const _WarCardDuelArea({
    required this.theme,
    required this.state,
    required this.leftId,
    required this.rightId,
    required this.isLocalMode,
    required this.playerNames,
    required this.colorFor,
    required this.duelActive,
    required this.duelPhase,
    required this.duelCreatorCard,
    required this.duelPartnerCard,
    required this.duelWinnerId,
    required this.duelWasBattle,
    required this.duelCreatorDisplayCount,
    required this.duelPartnerDisplayCount,
    required this.onTapFlip,
    required this.onTapPeek,
  });

  @override
  Widget build(BuildContext context) {
    final leftColor = colorFor(leftId);
    final rightColor = colorFor(rightId);
    final leftIsCreator = leftId == state.creatorId;
    final leftPile = leftIsCreator ? state.pileCreator : state.pilePartner;
    final rightPile = leftIsCreator ? state.pilePartner : state.pileCreator;
    final leftTapped = leftIsCreator ? state.pendingFlipCreator : state.pendingFlipPartner;
    final rightTapped = leftIsCreator ? state.pendingFlipPartner : state.pendingFlipCreator;
    // À distance/présentiel connecté, seul MON côté (gauche) est
    // interactif — la pile de droite (partenaire) n'appartient qu'à SON
    // appareil. En pass-and-play, les deux côtés sont sur le même
    // appareil, donc tous les deux interactifs (voir doc de classe).
    final canActLeft = !state.finished && !state.isPaused;
    final canActRight = canActLeft && isLocalMode;

    // "En attente de l'autre" — lu EN LIVE depuis la pile actuelle, jamais
    // une copie figée au moment du tap (voir _tapFlip) : la carte engagée
    // ne bouge pas tant que la manche n'est pas résolue (voir
    // WarCardEngine.flip), donc la relire à chaque rendu ne peut jamais
    // diverger de ce que le moteur va effectivement comparer.
    final leftCard = duelActive
        ? (leftIsCreator ? duelCreatorCard : duelPartnerCard)
        : (leftTapped && leftPile.isNotEmpty ? leftPile.first : null);
    final rightCard = duelActive
        ? (leftIsCreator ? duelPartnerCard : duelCreatorCard)
        : (rightTapped && rightPile.isNotEmpty ? rightPile.first : null);

    // Voir demande utilisateur : le compteur descend à n-1 DÈS le tap
    // (avant résolution), et ne remonte au compte réel (déjà résolu dans
    // `state.pileCreator/pilePartner` pendant toute la durée du duel) que
    // tout à la fin, au moment où les deux cartes rejoignent le vainqueur.
    final leftCount = duelActive
        ? (leftIsCreator ? duelCreatorDisplayCount : duelPartnerDisplayCount) ?? leftPile.length
        : (leftTapped ? leftPile.length - 1 : leftPile.length);
    final rightCount = duelActive
        ? (leftIsCreator ? duelPartnerDisplayCount : duelCreatorDisplayCount) ?? rightPile.length
        : (rightTapped ? rightPile.length - 1 : rightPile.length);

    // Dès qu'une carte est révélée (retournement optimiste OU manche
    // résolue), elle est au centre — voir demande utilisateur : "elle
    // monte immédiatement et patiente là-haut jusqu'à ce que l'autre
    // carte vienne la rejoindre". À la toute dernière étape, LES DEUX
    // convergent vers LE MÊME point : le côté du vainqueur (peu importe
    // de quel côté chaque carte vient à l'origine — voir demande
    // utilisateur : "elles doivent se réunir et descendre pour le
    // gagnant", pas repartir chacune vers son côté d'origine).
    Alignment alignFor({required bool isLeft, required bool revealed}) {
      if (!revealed) return isLeft ? _kLeftBottomAlign : _kRightBottomAlign;
      if (duelActive && duelPhase == _DuelPhase.atWinner) {
        return duelWinnerId == leftId ? _kLeftBottomAlign : _kRightBottomAlign;
      }
      return isLeft ? _kLeftStageAlign : _kRightStageAlign;
    }

    return Stack(
      children: [
        if (duelActive && duelWasBattle)
          Align(
            alignment: const Alignment(0, -0.15),
            child: Text(
              LocaleScope.t(context, 'war_card_battle_label'),
              style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 18, color: _kRedColor),
            ),
          ),
        // Le VS reste centré ENTRE les deux piles (voir demande
        // utilisateur) — remonté avec elles pour réduire le grand vide
        // laissé en haut de l'écran.
        Align(
          alignment: const Alignment(0, -0.1),
          child: Text('VS', style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 16, color: theme.textOnBackgroundMuted)),
        ),
        Align(
          alignment: _kLeftBottomAlign,
          child: _WarCardPileBase(
            label: playerNames[leftId] ?? '',
            color: leftColor,
            count: leftCount,
            canPlay: canActLeft && !leftTapped && leftPile.isNotEmpty,
            canPeek: true,
            onTapFlip: () => onTapFlip(leftId),
            onTapPeek: () => onTapPeek(leftId),
          ),
        ),
        Align(
          alignment: _kRightBottomAlign,
          child: _WarCardPileBase(
            label: playerNames[rightId] ?? '',
            color: rightColor,
            count: rightCount,
            canPlay: canActRight && !rightTapped && rightPile.isNotEmpty,
            canPeek: isLocalMode,
            onTapFlip: () => onTapFlip(rightId),
            onTapPeek: () => onTapPeek(rightId),
          ),
        ),
        // Toujours montés (jamais insérés/retirés de l'arbre) pour que
        // l'alignement puisse s'ANIMER en douceur dès la révélation —
        // voir demande utilisateur : "elle monte immédiatement".
        AnimatedAlign(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeInOut,
          alignment: alignFor(isLeft: true, revealed: leftCard != null),
          child: leftCard == null ? const SizedBox.shrink() : _WarCardFaceCard(card: leftCard, color: leftColor),
        ),
        AnimatedAlign(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeInOut,
          alignment: alignFor(isLeft: false, revealed: rightCard != null),
          child: rightCard == null ? const SizedBox.shrink() : _WarCardFaceCard(card: rightCard, color: rightColor),
        ),
        // "touche ta carte pour la jouer" (voir demande utilisateur) —
        // remontée avec les piles, pas collée au bord de l'écran.
        if (canActLeft && (!leftTapped || (isLocalMode && !rightTapped)))
          Align(
            alignment: const Alignment(0, 0.3),
            child: Text(
              LocaleScope.t(context, 'war_card_tap_hint'),
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
            ),
          ),
      ],
    );
  }
}

/// Une pile, EN BAS de l'écran (voir demande utilisateur) — dos de
/// cartes empilés, tapable pour jouer, avec un œil à l'angle haut-droit
/// (voir sa pile en éventail).
class _WarCardPileBase extends StatelessWidget {
  final String label;
  final Color color;
  final int count;
  final bool canPlay;
  final bool canPeek;
  final VoidCallback onTapFlip;
  final VoidCallback onTapPeek;

  const _WarCardPileBase({
    required this.label,
    required this.color,
    required this.count,
    required this.canPlay,
    required this.canPeek,
    required this.onTapFlip,
    required this.onTapPeek,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: canPlay ? onTapFlip : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _WarCardFullStack(count: count, color: color),
              if (canPeek)
                Positioned(
                  top: -8,
                  right: -8,
                  child: _WarCardPeekButton(color: color, onTap: onTapPeek),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text('$count', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

/// Position d'un pip dans le champ central d'une carte — [dx]/[dy] en
/// coordonnées d'Alignment (-1..1), [rotated] = retourné à 180° (pips de
/// la moitié basse, comme sur une vraie carte).
class _PipSpot {
  final double dx;
  final double dy;
  final bool rotated;

  const _PipSpot(this.dx, this.dy, {this.rotated = false});
}

/// Disposition RÉELLE des pips par rang (voir demande utilisateur : être
/// fidèle à chaque carte, pas juste un chiffre + un symbole) — mise en
/// page classique d'un jeu de 52 cartes françaises/anglaises. Les rangs
/// non listés ('A', 'J', 'Q', 'K') n'ont pas de champ de pips (voir
/// _PlayingCardFace : as = un seul gros pip central, figures = lettre).
const Map<String, List<_PipSpot>> _kPipLayouts = {
  '2': [_PipSpot(0, -0.75), _PipSpot(0, 0.75, rotated: true)],
  '3': [_PipSpot(0, -0.75), _PipSpot(0, 0), _PipSpot(0, 0.75, rotated: true)],
  '4': [
    _PipSpot(-0.6, -0.75),
    _PipSpot(0.6, -0.75),
    _PipSpot(-0.6, 0.75, rotated: true),
    _PipSpot(0.6, 0.75, rotated: true),
  ],
  '5': [
    _PipSpot(-0.6, -0.85),
    _PipSpot(0.6, -0.85),
    _PipSpot(0, 0),
    _PipSpot(-0.6, 0.85, rotated: true),
    _PipSpot(0.6, 0.85, rotated: true),
  ],
  '6': [
    _PipSpot(-0.6, -0.85),
    _PipSpot(0.6, -0.85),
    _PipSpot(-0.6, 0),
    _PipSpot(0.6, 0),
    _PipSpot(-0.6, 0.85, rotated: true),
    _PipSpot(0.6, 0.85, rotated: true),
  ],
  '7': [
    _PipSpot(-0.6, -0.9),
    _PipSpot(0.6, -0.9),
    _PipSpot(0, -0.45),
    _PipSpot(-0.6, 0),
    _PipSpot(0.6, 0),
    _PipSpot(-0.6, 0.9, rotated: true),
    _PipSpot(0.6, 0.9, rotated: true),
  ],
  '8': [
    _PipSpot(-0.6, -0.9),
    _PipSpot(0.6, -0.9),
    _PipSpot(0, -0.45),
    _PipSpot(-0.6, 0),
    _PipSpot(0.6, 0),
    _PipSpot(0, 0.45, rotated: true),
    _PipSpot(-0.6, 0.9, rotated: true),
    _PipSpot(0.6, 0.9, rotated: true),
  ],
  '9': [
    _PipSpot(-0.6, -0.9),
    _PipSpot(0.6, -0.9),
    _PipSpot(-0.6, -0.42),
    _PipSpot(0.6, -0.42),
    _PipSpot(0, 0),
    _PipSpot(-0.6, 0.42, rotated: true),
    _PipSpot(0.6, 0.42, rotated: true),
    _PipSpot(-0.6, 0.9, rotated: true),
    _PipSpot(0.6, 0.9, rotated: true),
  ],
  '10': [
    _PipSpot(-0.6, -0.9),
    _PipSpot(0.6, -0.9),
    _PipSpot(-0.6, -0.42),
    _PipSpot(0.6, -0.42),
    _PipSpot(0, -0.65),
    _PipSpot(0, 0.65, rotated: true),
    _PipSpot(-0.6, 0.42, rotated: true),
    _PipSpot(0.6, 0.42, rotated: true),
    _PipSpot(-0.6, 0.9, rotated: true),
    _PipSpot(0.6, 0.9, rotated: true),
  ],
};

String _suitSymbolFor(String suit) => switch (suit) {
      'S' => '♠',
      'H' => '♥',
      'D' => '♦',
      'C' => '♣',
      _ => '',
    };

/// Le visage complet d'une carte — indices en coin (haut-gauche, et
/// bas-droit retourné à 180°, comme sur une vraie carte) + champ central
/// fidèle au rang (voir demande utilisateur) : un pip pour l'as, la
/// disposition réelle pour 2 à 10 (voir [_kPipLayouts]), une lettre pour
/// les figures (J/Q/K — un vrai portrait illustré serait hors de portée
/// à cette taille, la lettre + les indices en coin restent la convention
/// standard pour identifier la figure sans ambiguïté).
class _PlayingCardFace extends StatelessWidget {
  final String card;
  final Color color;
  final double width;
  final double height;
  final Color? borderColor;
  final double borderWidth;
  final double borderRadius;

  const _PlayingCardFace({
    required this.card,
    required this.color,
    required this.width,
    required this.height,
    this.borderColor,
    this.borderWidth = 2,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final rank = card.substring(0, card.length - 1);
    final suit = card.substring(card.length - 1);
    final suitSymbol = _suitSymbolFor(suit);
    final isRedSuit = suit == 'H' || suit == 'D';
    final pipColor = isRedSuit ? _kRedColor : Colors.black87;
    final cornerFontSize = width * 0.15;
    // Voir demande utilisateur : "les motifs se chevauchent" — pips plus
    // petits, encore réduits pour les rangs à 4 rangées (9/10) qui ont le
    // moins de marge verticale disponible.
    final denseRank = rank == '9' || rank == '10';
    final pipFontSize = width * (denseRank ? 0.09 : 0.105);
    // Boîte réservée à CHAQUE pip (voir centerField) — en la dimensionnant
    // explicitement, deux pips proches ne peuvent jamais se chevaucher
    // visuellement, contrairement à un Align nu sur du texte "brut" dont
    // la boîte suit le glyphe et peut déborder sur sa voisine.
    final pipBoxSize = pipFontSize * 1.15;

    Widget corner({required bool flipped}) {
      final child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rank, style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: cornerFontSize, color: pipColor, height: 1)),
          Text(suitSymbol, style: TextStyle(fontSize: cornerFontSize * 0.8, color: pipColor, height: 1)),
        ],
      );
      return flipped ? Transform.rotate(angle: 3.14159, child: child) : child;
    }

    Widget centerField() {
      if (rank == 'A') {
        return Center(child: Text(suitSymbol, style: TextStyle(fontSize: width * 0.4, color: pipColor)));
      }
      if (rank == 'J' || rank == 'Q' || rank == 'K') {
        return Center(
          child: Text(rank, style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: width * 0.38, color: pipColor)),
        );
      }
      final layout = _kPipLayouts[rank];
      if (layout == null) return const SizedBox.shrink();

      return Stack(
        children: [
          for (final spot in layout)
            Align(
              alignment: Alignment(spot.dx, spot.dy),
              child: SizedBox(
                width: pipBoxSize,
                height: pipBoxSize,
                child: Center(
                  child: Transform.rotate(
                    angle: spot.rotated ? 3.14159 : 0,
                    child: Text(
                      suitSymbol,
                      style: TextStyle(fontSize: pipFontSize, color: pipColor, height: 1, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.all(width * 0.07),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor ?? color.withValues(alpha: 0.5), width: borderWidth),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: Stack(
        children: [
          Positioned(top: 0, left: 0, child: corner(flipped: false)),
          Positioned(bottom: 0, right: 0, child: corner(flipped: true)),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: width * 0.26, vertical: height * 0.13),
              child: centerField(),
            ),
          ),
        ],
      ),
    );
  }
}

/// La face d'une carte révélée — extrait de l'ancien `_CardSlot` pour
/// être positionnée indépendamment (voir `_WarCardDuelArea`, la carte
/// voyage désormais de la pile vers le centre puis vers le vainqueur).
class _WarCardFaceCard extends StatelessWidget {
  final String card;
  final Color color;

  const _WarCardFaceCard({required this.card, required this.color});

  @override
  Widget build(BuildContext context) {
    return _PlayingCardFace(card: card, color: color, width: _kCardWidth, height: _kCardHeight);
  }
}

/// Le paquet complet, empilé — voir demande utilisateur : "on doit voir en
/// premier lieu toutes les cartes empilées ensemble", donc un seul tas
/// visuel bien épais (pas deux piles distinctes comme en cours de partie).
class _WarCardFullStack extends StatelessWidget {
  final int count;
  final Color color;

  const _WarCardFullStack({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    // Jusqu'à 6 dos décalés pour suggérer l'épaisseur des 52 cartes, sans
    // dessiner littéralement 52 widgets superposés.
    final depth = count <= 0 ? 0 : (count >= 52 ? 6 : (1 + (count * 5 / 52)).round());

    return SizedBox(
      width: _kCardWidth + depth * 2.5,
      height: _kCardHeight + depth * 2.5,
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

const _kCardWidth = 90.0;
const _kCardHeight = 126.0;

class _CardSlot extends StatelessWidget {
  final String? card;
  final Color color;
  final String label;
  final int pileCount;

  const _CardSlot({required this.card, required this.color, required this.label, required this.pileCount});

  @override
  Widget build(BuildContext context) {
    final rank = card?.substring(0, card!.length - 1);
    final suit = card?.substring(card!.length - 1);
    final suitSymbol = switch (suit) {
      'S' => '♠',
      'H' => '♥',
      'D' => '♦',
      'C' => '♣',
      _ => '',
    };
    final isRedSuit = suit == 'H' || suit == 'D';

    // Le nombre de cartes réellement encore en jeu (jusqu'à 3) détermine
    // combien de "dos" décalés dessiner derrière la carte du dessus — on
    // voit ainsi tout de suite qu'il s'agit d'une PILE, pas d'une carte
    // unique, même quand elle est presque vide.
    final stackDepth = pileCount <= 0 ? 0 : (pileCount >= 3 ? 3 : pileCount);

    return Column(
      children: [
        Text(label, style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 8),
        SizedBox(
          // Marge pour laisser respirer les dos de cartes décalés en haut
          // à droite de la pile.
          width: _kCardWidth + 10,
          height: _kCardHeight + 10,
          child: Stack(
            children: [
              for (var i = stackDepth; i >= 1; i--)
                Positioned(
                  right: (stackDepth - i) * 3.0,
                  top: (stackDepth - i) * 3.0,
                  child: _CardBack(color: color, dimmed: i > 1),
                ),
              Positioned(
                left: 0,
                bottom: 0,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  transitionBuilder: (child, animation) {
                    final flip = Tween<double>(begin: 1, end: 0).animate(animation);
                    return AnimatedBuilder(
                      animation: flip,
                      child: child,
                      builder: (context, child) {
                        final angle = flip.value * 3.14159 / 2;
                        return Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..setEntry(3, 2, 0.001)..rotateY(angle),
                          child: child,
                        );
                      },
                    );
                  },
                  child: card == null
                      ? _CardBack(key: const ValueKey('back'), color: color)
                      : Container(
                          key: ValueKey(card),
                          width: _kCardWidth,
                          height: _kCardHeight,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
                          ),
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                rank ?? '',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 26,
                                  color: isRedSuit ? _kRedColor : Colors.black87,
                                ),
                              ),
                              Text(suitSymbol, style: TextStyle(fontSize: 26, color: isRedSuit ? _kRedColor : Colors.black87)),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text('$pileCount', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

/// Dos de carte — un motif losange répété plutôt qu'un simple rectangle
/// vide, pour que même la carte du dessus se lise clairement comme une
/// carte à jouer (pas juste un rectangle blanc) tant qu'elle n'est pas
/// retournée.
class _CardBack extends StatelessWidget {
  final Color color;
  final bool dimmed;

  const _CardBack({super.key, required this.color, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    final backColor = dimmed ? color.withValues(alpha: 0.35) : color;
    return Container(
      width: _kCardWidth,
      height: _kCardHeight,
      decoration: BoxDecoration(
        color: backColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
        boxShadow: dimmed ? null : const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
      ),
      alignment: Alignment.center,
      child: dimmed
          ? null
          : Icon(Icons.diamond_outlined, color: Colors.white.withValues(alpha: 0.55), size: 28),
    );
  }
}

/// Feuille "éventail" — voir demande utilisateur : tape sur ta pile pour
/// voir toutes tes cartes restantes étalées, dans l'ORDRE où elles seront
/// jouées (la première de la liste est la prochaine retournée).
class _WarCardFanSheet extends StatelessWidget {
  final List<String> pile;
  final Color color;
  // `null` = titre/sous-titre par défaut ("Tes {count} cartes"...) — voir
  // demande utilisateur : la même feuille sert aussi à "déplier" le
  // paquet ENTIER avant la distribution (war_card_predeal_peek_title),
  // où ce texte n'aurait pas de sens ("tes cartes" alors que rien n'a
  // encore été distribué à personne).
  final String? title;
  final String? subtitle;

  const _WarCardFanSheet({required this.pile, required this.color, this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);

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
            const SizedBox(height: 16),
            Text(
              title ?? LocaleScope.t(context, 'war_card_fan_title', {'count': '${pile.length}'}),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w800, color: theme.textOnBackground),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle ?? LocaleScope.t(context, 'war_card_fan_subtitle'),
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 150,
              child: pile.isEmpty
                  ? Center(
                      child: Text(
                        LocaleScope.t(context, 'war_card_fan_empty'),
                        style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: pile.length,
                      itemBuilder: (context, index) {
                        final angle = (index.isEven ? -1 : 1) * 0.05 * ((index % 5) + 1);
                        return Transform.rotate(
                          angle: angle,
                          child: Padding(
                            padding: EdgeInsets.only(left: index == 0 ? 0 : 40, top: 10),
                            child: _FanCard(card: pile[index], color: color, isNext: index == 0),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FanCard extends StatelessWidget {
  final String card;
  final Color color;
  final bool isNext;

  const _FanCard({required this.card, required this.color, required this.isNext});

  @override
  Widget build(BuildContext context) {
    return _PlayingCardFace(
      card: card,
      color: color,
      width: 62,
      height: 88,
      borderRadius: 10,
      borderColor: isNext ? color : color.withValues(alpha: 0.3),
      borderWidth: isNext ? 2.4 : 1.4,
    );
  }
}
