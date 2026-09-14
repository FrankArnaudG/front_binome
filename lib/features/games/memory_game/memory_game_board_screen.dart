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
import '../../shop/wallet_balance_notifier.dart';
import '../widgets/game_card_widgets.dart' show partnerReferenceLabel;
import '../nearby/nearby_comms.dart';
import '../widgets/coin_billing_ring.dart';
import '../widgets/game_comment_overlay.dart';
import '../widgets/memory_game_match_scoreboard.dart';
import '../widgets/game_wallet_guard.dart';
import '../widgets/nearby_voice_overlay.dart';
import '../widgets/voice_call_overlay.dart';
import '../game_service.dart';
import 'memory_emoji_pool.dart';
import 'memory_game_transport.dart';
import 'memory_game_transport_remote.dart';

/// Plateau de "Jeu de Mémoire" — UNIQUE écran de jeu partagé par les 3
/// modes (voir MemoryGameTransport) : ne connaît que l'état abstrait
/// [MemoryGameBoardState], jamais les détails de synchronisation
/// sous-jacents.
///
/// [playerNames]/[playerAvatars] sont indexés par les identifiants qui
/// apparaissent dans `state.matched`/`state.currentTurnUserId` — de vrais
/// identifiants utilisateur pour à distance/pass-and-play, ou les rôles
/// internes 'host'/'guest' pour le présentiel connecté (voir
/// memory_game_transport_nearby.dart).
class MemoryGameBoardScreen extends StatefulWidget {
  final Game game;
  final AppUser user;
  final MemoryGameTransport transport;
  final Map<String, String> playerNames;
  final Map<String, String?> playerAvatars;
  // Non-null uniquement pour les modes qui savent relancer une partie
  // identique (à distance/pass-and-play, voir startMemoryGameAndPush) —
  // reçoit le contexte de CET écran (toujours valide au moment de l'appel,
  // contrairement à celui de l'écran de difficulté d'origine qui a pu être
  // retiré de la pile entre-temps). `null` masque le bouton "Rejouer".
  final Future<void> Function(BuildContext context)? onRematch;
  // Canal de chat texte en présentiel connecté (voir NearbyComms) — non-null
  // uniquement pour ce mode (voir demande utilisateur : communiquer sans
  // serveur ni internet). `null` pour à distance/pass-and-play.
  final NearbyComms? nearbyComms;
  final String? nearbyMyName;
  final String? nearbyPartnerName;

  const MemoryGameBoardScreen({
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
  State<MemoryGameBoardScreen> createState() => _MemoryGameBoardScreenState();
}

class _MemoryGameBoardScreenState extends State<MemoryGameBoardScreen> {
  late StreamSubscription<MemoryGameBoardState> _subscription;
  late MemoryGameBoardState _state;
  List<int>? _displayMismatch;
  Timer? _mismatchTimer;
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
  // la différence avec le solde ACTUEL (WalletBalanceNotifier, mis à jour
  // en direct par GameWalletGuard à chaque GameWalletTicked) donne le
  // nombre de pièces consommées depuis le début, sans dépendre d'un champ
  // dédié côté backend.
  double? _startingBalance;

  @override
  void initState() {
    super.initState();
    _state = widget.transport.currentState;
    _subscription = widget.transport.stateStream.listen(_onState);
    // Rejoue juste le rendu du chrono chaque seconde — aucun appel réseau,
    // même principe que TimelineScreen._tickTimer.
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
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
    // Rafraîchit depuis le serveur plutôt que de faire confiance à une
    // valeur en cache potentiellement périmée (voir doc de classe de
    // WalletBalanceNotifier : "un solde de pièces n'a pas le droit d'être
    // périmé silencieusement").
    await WalletBalanceNotifier.instance.refresh();
    if (mounted) setState(() => _startingBalance = WalletBalanceNotifier.instance.balance);
  }

  /// Nombre de pièces consommées depuis le début de CETTE partie —
  /// `null` tant que le solde de départ n'est pas encore connu (voir
  /// _captureStartingBalance).
  double? _coinsConsumed() {
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

  void _onState(MemoryGameBoardState state) {
    if (!mounted) return;
    setState(() {
      _state = state;
      if (state.mismatch != null) {
        _displayMismatch = state.mismatch;
        _mismatchTimer?.cancel();
        _mismatchTimer = Timer(const Duration(milliseconds: 900), () {
          if (mounted) setState(() => _displayMismatch = null);
        });
      }
    });

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
  /// (voir _onState) — jamais quand c'est nous qui venons de le faire
  /// (voir _confirmAbandon, qui referme déjà l'écran tout seul). "OK"
  /// laisse consulter le plateau tel qu'il était ; "Sortir" referme
  /// l'écran tout de suite (voir demande utilisateur).
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

  /// Même dialogue de confirmation pour les deux façons de quitter une
  /// partie en cours : le bouton drapeau explicite ET la flèche retour
  /// (voir PopScope dans build()) — sans cette seconde interception, la
  /// flèche retour laissait la partie "en l'air" sans jamais prévenir le
  /// binôme ni le serveur (voir demande utilisateur : après être revenu en
  /// arrière puis avoir relancé une invitation, le binôme ne recevait
  /// plus rien — les deux appareils n'étaient jamais repartis d'un état
  /// propre).
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
    final rematch = await showMemoryGameMatchScoreboard(
      context,
      state: _state,
      playerNames: widget.playerNames,
      playerAvatars: widget.playerAvatars,
      allowRematch: widget.onRematch != null,
    );
    if (rematch == true && widget.onRematch != null && mounted) {
      await widget.onRematch!(context);
    }
  }

  Future<void> _onTapCard(int index) async {
    if (_state.finished) return;
    if (_state.isPaused) return;
    if (_state.matchedIndices.contains(index)) return;
    if (_state.flipped.contains(index)) return;
    if (_displayMismatch != null) return; // laisse le temps de voir la paire ratée
    if (widget.transport.requiresTurnToFlip && !_state.isMyTurn) return;

    await widget.transport.flip(index);
  }

  // Réactions en direct (voir GameCommentOverlay) : uniquement en mode "à
  // distance", seul mode où un canal de Box existe déjà côté client — le
  // présentiel connecté (Nearby) reste du pur P2P sans notion de Box.
  String? get _commentsBoxId {
    final transport = widget.transport;
    return transport is RemoteMemoryGameTransport ? transport.boxId : null;
  }

  String get _sessionId {
    final transport = widget.transport;
    return transport is RemoteMemoryGameTransport ? transport.sessionId : '';
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

  int _pairsFoundBy(String userId) => _state.matched.where((pair) => pair.userId == userId).length;

  String _elapsed() {
    final started = _state.startedAt;
    if (started == null) return '0:00';
    // Figé au moment où la pause a commencé (voir MemoryGameBoardState.
    // pausedAt) — sinon le chrono continuerait de tourner à l'écran pendant
    // la pause, alors que startedAt n'est décalé qu'à la reprise.
    final now = _state.pausedAt ?? ServerClock.instance.now();
    // Le chrono attend la même période de grâce que l'anneau de pièce
    // (voir CoinBillingRing/demande utilisateur : "les 10 secondes
    // doivent représenter le temps que doit patienter le chrono avant de
    // se mettre en marche officiellement") — reste à 0:00 tant que la
    // grâce n'est pas écoulée, nul en dehors du mode à distance
    // (_economyRate jamais chargé ailleurs).
    final graceSeconds = _economyRate?['grace_period_seconds'] ?? 0;
    // max(0, ...) : si l'horloge du téléphone est en retard sur celle du
    // serveur (courant sur un appareil de test dont la date n'est pas
    // synchronisée), la différence peut devenir négative — un chrono
    // négatif n'a aucun sens à l'écran (voir demande utilisateur, capture
    // "-27:59").
    final seconds = (now.difference(started).inSeconds - graceSeconds).clamp(0, 1 << 31);
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _subscription.cancel();
    _mismatchTimer?.cancel();
    _clockTimer?.cancel();
    widget.transport.dispose();
    widget.nearbyComms?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Différé au frame suivant — assigné en direct, cette mise à jour
    // pouvait planter silencieusement pendant le démontage (arbre de
    // widgets verrouillé, voir demande utilisateur : après avoir quitté une
    // partie, plus aucune invitation ne s'affichait jusqu'à relancer l'app
    // entière — la coquille globale entière restait coincée masquée).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppRouter.showGlobalNavBar.value = true;
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final board = _state.board;

    if (board.isEmpty) {
      // Invité en présentiel connecté, en attente du plateau envoyé par
      // l'hôte (voir NearbyMemoryGameTransport.guest).
      return Scaffold(
        backgroundColor: theme.background,
        body: ThemedBackground(
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: theme.primary),
                  const SizedBox(height: 16),
                  Text(
                    LocaleScope.t(context, 'memory_board_waiting'),
                    style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final difficulty = MemoryGameDifficulty.all.firstWhere((d) => d.cardCount == board.length);
    final turnName = _state.currentTurnUserId != null ? widget.playerNames[_state.currentTurnUserId] : null;

    final commentsBoxId = _commentsBoxId;
    return PopScope(
      // Bloqué tant que la partie n'est pas finie — voir _confirmAbandon,
      // rejoué manuellement ci-dessous après confirmation (voir demande
      // utilisateur).
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
              // En pause : bouton "Reprendre" UNIQUEMENT pour qui l'a posée
              // (voir demande utilisateur) — désactivé (grisé, pas caché)
              // côté binôme, pour que ça reste visible que le jeu est en
              // pause sans laisser croire qu'iel peut la lever.
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
          // Masqué une fois la partie terminée — sinon un retap n'a plus
          // aucun effet visible (la partie est déjà `finished`) et donne
          // l'impression que le bouton "ne fonctionne pas" (même bug
          // trouvé et corrigé sur Morpion à Deux, voir demande utilisateur).
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
          // fois qu'elle a disparu (même correctif que Morpion à Deux, voir
          // demande utilisateur).
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
                // Entête resserrée (voir demande utilisateur : "remonter
                // l'entête et réduire un peu l'espace, mais toujours bien
                // lisible") — plus de hauteur libre pour la grille elle-même,
                // sans rien couper à la taille du texte.
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        // Une fois la partie finie, "Au tour de..." n'a
                        // plus de sens (même correctif que Morpion à Deux,
                        // voir demande utilisateur).
                        _state.finished
                            ? LocaleScope.t(context, 'game_board_finished_label')
                            : (widget.transport.requiresTurnToFlip
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
                        if (commentsBoxId != null) ...[
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
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Row(
                  children: [
                    for (final userId in widget.playerNames.keys) ...[
                      if (userId != widget.playerNames.keys.first) const SizedBox(width: 10),
                      Expanded(
                        child: _PlayerStatChip(
                          theme: theme,
                          name: widget.playerNames[userId] ?? '',
                          avatar: widget.playerAvatars[userId],
                          pairsFound: _pairsFoundBy(userId),
                          moves: _state.movesByUser[userId] ?? 0,
                          active: _state.currentTurnUserId == userId,
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
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Ratio calculé pour que la grille remplisse
                      // exactement l'espace disponible (ni débordement, ni
                      // espace mort), quel que soit le palier de difficulté
                      // (3×4 à 8×14) ou la taille d'écran — au lieu d'un
                      // ratio fixe qui ne convenait qu'à une seule grille.
                      // clamp() large (pas 0.55–1.3) : cette fourchette
                      // resserrait le ratio dès qu'une grille avait peu de
                      // colonnes pour beaucoup de lignes (ex. 16 paires,
                      // 4×8) — le ratio RESSERRÉ (pas le naturel) servait
                      // alors à calculer la hauteur de chaque carte, et
                      // gonflait la grille entière au-delà de l'espace
                      // disponible (voir demande utilisateur : "le 16
                      // paires déborde"). Le calcul ci-dessus garantit déjà
                      // un ajustement exact par construction ; ce clamp()
                      // élargi ne sert plus que de filet de sécurité contre
                      // un cas dégénéré (fenêtre quasi nulle), jamais à
                      // resserrer un ratio par ailleurs valide.
                      const spacing = 8.0;
                      final cardWidth = (constraints.maxWidth - (difficulty.columns - 1) * spacing) / difficulty.columns;
                      final cardHeight = (constraints.maxHeight - (difficulty.rows - 1) * spacing) / difficulty.rows;
                      final aspectRatio = (cardWidth / cardHeight).clamp(0.35, 2.2);

                      return GridView.builder(
                        // Le ratio ci-dessus fait déjà tenir la grille dans
                        // l'espace disponible dans le cas normal — le
                        // scroll reste actif uniquement comme filet de
                        // sécurité si le clamp() a dû resserrer le ratio
                        // (fenêtre quasi nulle uniquement, voir plus haut).
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: difficulty.columns,
                          mainAxisSpacing: spacing,
                          crossAxisSpacing: spacing,
                          childAspectRatio: aspectRatio,
                        ),
                        itemCount: board.length,
                        itemBuilder: (context, index) {
                          final isMatched = _state.matchedIndices.contains(index);
                          final isFlipped = _state.flipped.contains(index) || (_displayMismatch?.contains(index) ?? false);
                          return _MemoryCardTile(
                            emoji: board[index],
                            faceUp: isMatched || isFlipped,
                            dimmed: isMatched,
                            onTap: () => _onTapCard(index),
                          );
                        },
                      );
                    },
                  ),
                    ),
                    if (_state.isPaused)
                      // Empêche tout tap sur la grille en dessous tant que
                      // la pause est active (en plus du garde-fou dans
                      // _onTapCard) — Positioned.fill capte tous les gestes
                      // de cette zone.
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
            // Coupe l'appel en cours dès la mise en pause (voir demande
            // utilisateur : "couper tout les procecusse lour comme
            // l'audio, la video" à la pause), même mécanisme que pour un
            // solde épuisé.
            forceEnded: _walletDepleted || _state.isPaused,
          )
        else if (widget.nearbyComms != null)
          NearbyVoiceOverlay(comms: widget.nearbyComms, enabled: true, paused: _state.isPaused),
        GameWalletGuard(
          boxId: commentsBoxId,
          sessionType: 'memory_game',
          sessionId: _sessionId,
          onDepletedChanged: (v) => setState(() => _walletDepleted = v),
          onEndGame: _endGameFromWalletDepletion,
        ),
      ],
      ),
    );
  }
}

/// Score + coups d'UN joueur, affichés en direct pendant la partie (voir
/// demande utilisateur : le compteur de coups était partagé/global, il
/// doit être séparé par joueur, comme le score) — [active] met en
/// évidence le joueur dont c'est le tour.
class _PlayerStatChip extends StatelessWidget {
  final ThemePalette theme;
  final String name;
  final String? avatar;
  final int pairsFound;
  final int moves;
  final bool active;

  const _PlayerStatChip({
    required this.theme,
    required this.name,
    required this.avatar,
    required this.pairsFound,
    required this.moves,
    required this.active,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: theme.textOnBackground),
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Icon(Icons.favorite_rounded, size: 12, color: theme.primary),
                    const SizedBox(width: 3),
                    Text('$pairsFound', style: GoogleFonts.nunito(fontSize: 11, color: theme.textOnBackgroundMuted)),
                    const SizedBox(width: 8),
                    Icon(Icons.touch_app_outlined, size: 12, color: theme.textOnBackgroundMuted),
                    const SizedBox(width: 3),
                    Text('$moves', style: GoogleFonts.nunito(fontSize: 11, color: theme.textOnBackgroundMuted)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryCardTile extends StatelessWidget {
  final String emoji;
  final bool faceUp;
  final bool dimmed;
  final VoidCallback onTap;

  const _MemoryCardTile({required this.emoji, required this.faceUp, required this.dimmed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);

    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: faceUp ? 1 : 0),
        duration: const Duration(milliseconds: 260),
        builder: (context, t, child) {
          final showFront = t > 0.5;
          final angle = t * 3.14159265;
          return Opacity(
            opacity: dimmed ? 0.45 : 1,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..setEntry(3, 2, 0.001)..rotateY(angle),
              child: showFront
                  ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(3.14159265),
                      child: _CardFace(
                        color: theme.surface,
                        border: theme.primary.withValues(alpha: 0.4),
                        child: Text(emoji, style: const TextStyle(fontSize: 26)),
                      ),
                    )
                  : _CardFace(
                      color: theme.primary.withValues(alpha: 0.85),
                      border: Colors.transparent,
                      child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 20),
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _CardFace extends StatelessWidget {
  final Color color;
  final Color border;
  final Widget child;

  const _CardFace({required this.color, required this.border, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Center(child: child),
    );
  }
}
