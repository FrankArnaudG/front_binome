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
import '../game_service.dart';
import '../nearby/nearby_comms.dart';
import '../widgets/coin_billing_ring.dart';
import '../widgets/game_card_widgets.dart' show partnerReferenceLabel;
import '../widgets/game_comment_overlay.dart';
import '../widgets/number_hunt_match_scoreboard.dart';
import '../widgets/game_wallet_guard.dart';
import '../widgets/nearby_voice_overlay.dart';
import '../widgets/voice_call_overlay.dart';
import 'number_hunt_transport.dart';
import 'number_hunt_transport_remote.dart';

const _kRedColor = Color(0xFFE5484D);
const _kBlueColor = Color(0xFF2F6FED);

/// Plateau de "Chasse aux Chiffres" — UNIQUE écran de jeu partagé par les
/// 3 modes (voir NumberHuntTransport), copie structurelle conforme des 3
/// autres jeux (pause/reprise, chrono), SAUF qu'il n'y a pas de tour par
/// tour : n'importe lequel des deux peut taper à tout moment sur le
/// nombre-cible annoncé en haut de l'écran.
class NumberHuntBoardScreen extends StatefulWidget {
  final Game game;
  final AppUser user;
  final NumberHuntTransport transport;
  final Map<String, String> playerNames;
  final Map<String, String?> playerAvatars;
  final Future<void> Function(BuildContext context)? onRematch;
  final NearbyComms? nearbyComms;
  final String? nearbyMyName;
  final String? nearbyPartnerName;

  const NumberHuntBoardScreen({
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

  /// Pop-up "qui a trouvé ?" pour le mode pass-and-play — voir
  /// LocalNumberHuntTransport.askWhoFound. Appelé AVANT que l'écran de
  /// plateau n'existe forcément encore (construit dès startNumberHuntAndPush,
  /// voir number_hunt_mode_screen.dart), d'où l'usage du Navigator global
  /// plutôt que le contexte de CETTE instance.
  static Future<String> askWhoFoundFor(String creatorId, String partnerId) async {
    final ctx = AppRouter.navigatorKey.currentContext;
    if (ctx == null) return creatorId;

    final box = BoxScope.of(ctx).currentBox;
    final creatorName = box?.creatorId == creatorId ? (box?.creator?.prenom ?? 'Joueur 1') : (box?.partner?.prenom ?? 'Joueur 1');
    final partnerName = box?.creatorId == partnerId ? (box?.creator?.prenom ?? 'Joueur 2') : (box?.partner?.prenom ?? 'Joueur 2');
    final theme = ThemeScope.paletteOf(ctx);

    final result = await showDialog<String>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: Text(LocaleScope.t(dialogCtx, 'number_hunt_who_found_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _WhoFoundButton(color: _kRedColor, name: creatorName, onTap: () => Navigator.of(dialogCtx).pop(creatorId)),
            const SizedBox(height: 10),
            _WhoFoundButton(color: _kBlueColor, name: partnerName, onTap: () => Navigator.of(dialogCtx).pop(partnerId)),
          ],
        ),
        backgroundColor: theme.background,
      ),
    );
    return result ?? creatorId;
  }

  @override
  State<NumberHuntBoardScreen> createState() => _NumberHuntBoardScreenState();
}

class _NumberHuntBoardScreenState extends State<NumberHuntBoardScreen> {
  late StreamSubscription<NumberHuntBoardState> _subscription;
  late NumberHuntBoardState _state;
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
  double? _startingBalance;
  int? _lastFoundNumber;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    _state = widget.transport.currentState;
    _subscription = widget.transport.stateStream.listen(_onState);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // Masque la barre de navigation Android le temps de la partie — la
    // grille de 100 cases profite de tout l'espace vertical disponible.
    // Restaurée dans dispose() pour ne pas affecter le reste de l'app.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Masque aussi la barre de navigation DE L'APP (Carnet de bord/Duo/
    // Jeux/Profil) — voir AppShell, montée au-dessus de tout écran poussé
    // et donc visible par défaut même ici. Même principe que
    // TimelineScreen/EmojiStorySessionScreen. Différé à la fin de la frame
    // en cours (plutôt qu'un appel synchrone en plein milieu du montage de
    // CET écran) pour ne jamais déclencher la reconstruction d'AppShell
    // pendant qu'une autre partie de l'arbre est encore en cours de
    // construction.
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

  void _onState(NumberHuntBoardState state) {
    if (!mounted) return;
    final previouslyFound = _state.found;
    // Repère le nombre qui vient d'être trouvé (présent dans le nouvel état
    // mais pas dans l'ancien) pour un bref surlignage — `null` si rien de
    // nouveau (ex. simple resynchronisation, pas une vraie trouvaille).
    String? newlyFoundKey;
    for (final key in state.found.keys) {
      if (!previouslyFound.containsKey(key)) {
        newlyFoundKey = key;
        break;
      }
    }

    setState(() => _state = state);

    if (newlyFoundKey != null) {
      _lastFoundNumber = int.tryParse(newlyFoundKey);
      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _lastFoundNumber = null);
      });
    }

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
    final rematch = await showNumberHuntMatchScoreboard(
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

  Future<void> _onTapNumber(int number) async {
    if (_state.finished || _state.isPaused) return;
    if (_state.found.containsKey('$number')) return;
    await widget.transport.attempt(number);
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
  /// Le Jeu des Carrés.
  Color _colorFor(String userId) {
    final ids = widget.playerNames.keys.toList()..sort();
    return userId == ids.first ? _kRedColor : _kBlueColor;
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
    return transport is RemoteNumberHuntTransport ? transport.boxId : null;
  }

  String get _sessionId {
    final transport = widget.transport;
    return transport is RemoteNumberHuntTransport ? transport.sessionId : '';
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
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _state.finished
                          ? LocaleScope.t(context, 'game_board_finished_label')
                          : LocaleScope.t(context, 'number_hunt_find_target', {'number': '${_state.currentTarget ?? '-'}'}),
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 20, color: theme.primary),
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
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: Row(
                  children: [
                    for (final userId in widget.playerNames.keys) ...[
                      if (userId != widget.playerNames.keys.first) const SizedBox(width: 10),
                      Expanded(
                        child: _NumberHuntPlayerChip(
                          theme: theme,
                          name: widget.playerNames[userId] ?? '',
                          avatar: widget.playerAvatars[userId],
                          color: _colorFor(userId),
                          score: _state.scoreFor(userId),
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
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: GridView.builder(
                        physics: const BouncingScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 8,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                          childAspectRatio: 1,
                        ),
                        itemCount: _state.board.length,
                        itemBuilder: (context, index) {
                          final number = _state.board[index];
                          final foundBy = _state.found['$number'];
                          return _NumberHuntTile(
                            theme: theme,
                            number: number,
                            color: foundBy != null ? _colorFor(foundBy) : null,
                            justFound: _lastFoundNumber == number,
                            onTap: () => _onTapNumber(number),
                          );
                        },
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
            forceEnded: _walletDepleted || _state.isPaused,
          )
        else if (widget.nearbyComms != null)
          NearbyVoiceOverlay(comms: widget.nearbyComms, enabled: true, paused: _state.isPaused),
        GameWalletGuard(
          boxId: commentsBoxId,
          sessionType: 'number_hunt',
          sessionId: _sessionId,
          onDepletedChanged: (v) => setState(() => _walletDepleted = v),
          onEndGame: _endGameFromWalletDepletion,
        ),
      ],
      ),
    );
  }
}

class _WhoFoundButton extends StatelessWidget {
  final Color color;
  final String name;
  final VoidCallback onTap;

  const _WhoFoundButton({required this.color, required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(backgroundColor: color, padding: const EdgeInsets.symmetric(vertical: 14)),
        child: Text(name, style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _NumberHuntPlayerChip extends StatelessWidget {
  final ThemePalette theme;
  final String name;
  final String? avatar;
  final Color color;
  final int score;

  const _NumberHuntPlayerChip({
    required this.theme,
    required this.name,
    required this.avatar,
    required this.color,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.surface.withValues(alpha: theme.isDark ? 0.5 : 0.75),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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
          Text('$score', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

class _NumberHuntTile extends StatelessWidget {
  final ThemePalette theme;
  final int number;
  final Color? color;
  final bool justFound;
  final VoidCallback onTap;

  const _NumberHuntTile({
    required this.theme,
    required this.number,
    required this.color,
    required this.justFound,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final found = color != null;
    return Material(
      color: justFound
          ? (color ?? theme.primary).withValues(alpha: 0.85)
          : found
              ? (color ?? theme.primary).withValues(alpha: 0.12)
              : theme.surface.withValues(alpha: theme.isDark ? 0.5 : 0.85),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: found ? null : onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: found ? (color ?? theme.primary).withValues(alpha: 0.4) : theme.primary.withValues(alpha: 0.15)),
          ),
          child: Center(
            child: Text(
              '$number',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: justFound
                    ? Colors.white
                    : found
                        ? (color ?? theme.primary)
                        : theme.textOnBackground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
