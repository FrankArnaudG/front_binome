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
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../../../theme/themed_background.dart';
import '../game_guide_storage.dart';
import '../game_service.dart';
import '../nearby/nearby_comms.dart';
import '../widgets/always_on_top_layer.dart';
import '../widgets/coin_billing_ring.dart';
import '../widgets/game_comment_overlay.dart';
import '../widgets/game_guide_voice_demo.dart';
import '../widgets/tic_tac_toe_match_scoreboard.dart';
import '../widgets/game_resume_action.dart';
import '../widgets/game_wallet_depleted_notice.dart';
import '../widgets/game_wallet_guard.dart';
import '../widgets/nearby_voice_overlay.dart';
import '../widgets/voice_call_overlay.dart';
import '../../shop/subscription_status_notifier.dart';
import '../../shop/wallet_balance_notifier.dart';
import 'tic_tac_toe_engine.dart';
import 'tic_tac_toe_transport.dart';
import 'tic_tac_toe_transport_remote.dart';
import 'tic_tac_toe_transport_local.dart';

/// Étapes du guide pas-à-pas du plateau (voir doc de _BoardGuideStep dans
/// memory_game_board_screen.dart pour le principe général). Une seule
/// bulle sur la grille entière plutôt qu'une simulation case par case
/// (voir demande utilisateur : rester proportionné à chaque jeu) — le
/// Morpion a deux phases (pose puis déplacement) déjà expliquées dans le
/// texte de la bulle plutôt que démontrées.
enum _TicTacToeGuideStep {
  turn,
  activeName,
  placementTap,
  selectTap,
  moveTap,
  coins,
  pause,
  chat,
  micJoin,
  micReady,
  cameraReady,
}

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
  // Celui qui a lancé la partie (voir demande utilisateur) : seul lui voit "Rejouer" et le
  // décompte de Tokens (c'est son temps qui est facturé). L'autre joueur ne voit que "Quitter".
  final bool isLauncher;
  // "Quitter" depuis la feuille de score : par défaut referme le jeu ; l'invité·e d'une partie à
  // distance y ouvre le choix de la difficulté (voir game_invite_navigation.dart).
  final Future<void> Function(BuildContext context)? onQuit;
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
    this.isLauncher = true,
    this.onQuit,
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
  bool _resuming = false;
  bool _scoreboardShown = false;
  // Instant de fin de partie vu par CET appareil : fige chrono et tokens.
  // Réglage admin (minutes_per_coin/grace_period_seconds) pour l'anneau de
  // progression coté token (voir CoinBillingRing/demande utilisateur) —
  // chargé une seule fois, uniquement utile en mode à distance.
  Map<String, int>? _economyRate;
  int? _selectedPosition;
  // Non-null pendant la fenêtre de surbrillance qui suit un alignement —
  // remplace TEMPORAIREMENT l'affichage de `_state.board` (déjà dispersé)
  // par le plateau tel qu'il était juste avant la dispersion, pour que
  // l'alignement reste visible quelques secondes (voir doc de
  // TicTacToeBoardState.scoredLine/preScatterBoard).
  List<String?>? _highlightBoard;
  List<int>? _highlightedLine;
  Timer? _highlightTimer;
  // Message « Point pour [prénom] ! » / « Tu as marqué un point ! » affiché AU CENTRE du plateau (voir
  // demande utilisateur : l'ancienne bannière en bas d'écran passait inaperçue).
  ({String text, bool mine})? _scoreBanner;
  int _scoreBannerSeq = 0;
  Timer? _scoreBannerTimer;

  // Guide pas-à-pas (voir doc de classe de _TicTacToeGuideStep et demande
  // utilisateur : "prends le même soin pour les autres jeux") — mêmes
  // principes qu'au Jeu de Mémoire/Bataille : étapes informatives,
  // avancées au tap, mise en pause automatique, rejouable via le "?".
  final _turnGuideKey = GlobalKey();
  final _activeNameGuideKey = GlobalKey();
  final _gridGuideKey = GlobalKey();
  final _coinsGuideKey = GlobalKey();
  final _pauseGuideKey = GlobalKey();
  final _chatGuideKey = GlobalKey();
  final _micGuideKey = GlobalKey();
  final _cameraGuideKey = GlobalKey();
  static const _boardGuideKey = 'tic_tac_toe_board';
  _TicTacToeGuideStep? _guideStep;
  bool _guideMicConnecting = false;
  // Démo pose/déplacement du guide (voir demande utilisateur : "peu tu
  // guider pour que le user connaisse comment se fait la pose et aussi
  // comment se fait le déplacement") — indices/état purement LOCAUX,
  // jamais transmis à widget.transport (mêmes principes que
  // _guideFakeFlipped dans memory_game_board_screen.dart).
  int? _guidePlaceIndex;
  int? _guideMoveIndex;
  bool _guidePlaced = false;
  bool _guideSelected = false;

  @override
  void initState() {
    super.initState();
    _state = widget.transport.currentState;
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
  bool get _guideAvailable => widget.transport is LocalTicTacToeTransport;

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
    _startGuideStep(_TicTacToeGuideStep.turn);
  }

  /// Premier indice vide du plateau RÉEL, différent de [exclude] — voir
  /// demande utilisateur : la démo doit poser/déplacer sur de vraies
  /// cases vides, jamais une case déjà occupée. `null` si le plateau
  /// n'a pas encore été reçu ou n'a plus de case libre.
  int? _pickGuideEmptyIndex({int? exclude}) {
    final board = _highlightBoard ?? _state.board;
    for (var i = 0; i < board.length; i++) {
      if (i == exclude) continue;
      if (board[i] == null) return i;
    }
    return null;
  }

  void _startGuideStep(_TicTacToeGuideStep step) {
    if (!mounted) return;
    if (step == _TicTacToeGuideStep.placementTap) {
      _guidePlaced = false;
      _guideSelected = false;
      _guidePlaceIndex = _pickGuideEmptyIndex();
      if (_guidePlaceIndex == null) {
        _startGuideStep(_TicTacToeGuideStep.coins);
        return;
      }
    }
    if (step == _TicTacToeGuideStep.moveTap) {
      _guideMoveIndex = _pickGuideEmptyIndex(exclude: _guidePlaceIndex);
      if (_guideMoveIndex == null) {
        _startGuideStep(_TicTacToeGuideStep.coins);
        return;
      }
    }
    setState(() {
      _guideStep = step;
      if (step == _TicTacToeGuideStep.micReady) _guideMicConnecting = true;
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

  /// Étape "pose" (voir _TicTacToeGuideStep.placementTap) — tap RÉEL sur
  /// la case désignée, purement local (voir doc de classe des champs
  /// _guidePlaceIndex/_guidePlaced), jamais widget.transport.place().
  void _onGuidePlacementTap() {
    setState(() => _guidePlaced = true);
    _startGuideStep(_TicTacToeGuideStep.selectTap);
  }

  /// Étape "sélection" (phase de déplacement) — tap sur le pion posé par
  /// la démo, purement local.
  void _onGuideSelectTap() {
    setState(() => _guideSelected = true);
    _startGuideStep(_TicTacToeGuideStep.moveTap);
  }

  /// Étape "déplacement" — tap sur la case destination, purement local ;
  /// nettoie tous les artefacts de démo avant de continuer le guide.
  void _onGuideMoveTap() {
    setState(() {
      _guidePlaced = false;
      _guideSelected = false;
      _guidePlaceIndex = null;
      _guideMoveIndex = null;
    });
    _startGuideStep(_TicTacToeGuideStep.coins);
  }

  GlobalKey _guideKeyFor(_TicTacToeGuideStep step) {
    switch (step) {
      case _TicTacToeGuideStep.turn:
        return _turnGuideKey;
      case _TicTacToeGuideStep.activeName:
        return _activeNameGuideKey;
      case _TicTacToeGuideStep.placementTap:
      case _TicTacToeGuideStep.selectTap:
      case _TicTacToeGuideStep.moveTap:
        return _gridGuideKey;
      case _TicTacToeGuideStep.coins:
        return _coinsGuideKey;
      case _TicTacToeGuideStep.pause:
        return _pauseGuideKey;
      case _TicTacToeGuideStep.chat:
        return _chatGuideKey;
      case _TicTacToeGuideStep.micJoin:
      case _TicTacToeGuideStep.micReady:
        return _micGuideKey;
      case _TicTacToeGuideStep.cameraReady:
        return _cameraGuideKey;
    }
  }

  /// Appelé au tap sur la bulle elle-même (voir
  /// ShowcaseView.get().addOnCompleteCallback) — ne fait avancer que les
  /// étapes purement informatives ; placementTap/selectTap/moveTap ont
  /// leurs gestes de cible désactivés (voir disableDefaultTargetGestures
  /// dans build()) et n'avancent QUE via un vrai tap sur la case
  /// désignée (voir _onGuidePlacementTap/_onGuideSelectTap/
  /// _onGuideMoveTap), jamais ici.
  void _onGuideStepTapped(int? index, GlobalKey key) {
    switch (_guideStep) {
      case _TicTacToeGuideStep.turn:
        _startGuideStep(_TicTacToeGuideStep.activeName);
        break;
      case _TicTacToeGuideStep.activeName:
        _startGuideStep(_TicTacToeGuideStep.placementTap);
        break;
      case _TicTacToeGuideStep.placementTap:
      case _TicTacToeGuideStep.selectTap:
      case _TicTacToeGuideStep.moveTap:
        break;
      case _TicTacToeGuideStep.coins:
        _startGuideStep(_TicTacToeGuideStep.pause);
        break;
      case _TicTacToeGuideStep.pause:
        _startGuideStep(_TicTacToeGuideStep.chat);
        break;
      case _TicTacToeGuideStep.chat:
        _startGuideStep(_TicTacToeGuideStep.micJoin);
        break;
      case _TicTacToeGuideStep.micJoin:
        _startGuideStep(_TicTacToeGuideStep.micReady);
        break;
      case _TicTacToeGuideStep.micReady:
        _startGuideStep(_TicTacToeGuideStep.cameraReady);
        break;
      case _TicTacToeGuideStep.cameraReady:
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
      _guidePlaced = false;
      _guideSelected = false;
      _guidePlaceIndex = null;
      _guideMoveIndex = null;
    });
  }

  Widget _buildGuideVoiceDemo() {
    final phase = switch (_guideStep) {
      _TicTacToeGuideStep.micJoin => GameGuideVoicePhase.micJoin,
      _TicTacToeGuideStep.micReady => GameGuideVoicePhase.micReady,
      _TicTacToeGuideStep.cameraReady => GameGuideVoicePhase.cameraReady,
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
    final now = _state.pausedAt ?? ServerClock.instance.now();
    final elapsed = now.difference(started).inSeconds - graceSeconds;
    return elapsed < 0 ? 0 : elapsed.toDouble();
  }

  /// Nombre de tokens consommés depuis le début de CETTE partie — fluide
  /// comme l'anneau (même calcul), voir demande utilisateur.
  double? _coinsConsumed() {
    final elapsed = _elapsedBillableSeconds();
    final cycleSeconds = (_economyRate?['minutes_per_coin'] ?? 8) * 60;
    if (elapsed == null || cycleSeconds <= 0) return 0;
    return elapsed / cycleSeconds;
  }

  /// Fraction (0..1) de progression vers le prochain token déduit —
  /// purement indicatif (voir doc de CoinBillingRing), calculé à partir du
  /// même réglage que le serveur (minutes_per_coin/grace_period_seconds)
  /// mais jamais la source de vérité de la facturation elle-même.
  double _coinProgress() {
    final elapsed = _elapsedBillableSeconds();
    final cycleSeconds = (_economyRate?['minutes_per_coin'] ?? 8) * 60;
    if (elapsed == null || cycleSeconds <= 0) return 0;
    return (elapsed % cycleSeconds) / cycleSeconds;
  }

  void _onState(TicTacToeBoardState state) {
    if (!mounted) return;
    final justScored = state.scoredLine != null && state.preScatterBoard != null;
    // Qui vient de marquer : celui dont le score a augmenté par rapport à l'état affiché jusque-là.
    // Sans hausse (même état reçu deux fois : réponse puis évènement), on ne ré-annonce rien.
    String? scorerId;
    if (justScored) {
      for (final entry in state.scoresByUser.entries) {
        if (entry.value > (_state.scoresByUser[entry.key] ?? 0)) scorerId = entry.key;
      }
    }

    setState(() {
      _state = state;
      _selectedPosition = null;
      if (justScored) {
        _highlightBoard = state.preScatterBoard;
        _highlightedLine = state.scoredLine;
      }
    });

    if (justScored) {
      if (scorerId != null) _showScoreBanner(scorerId, mine: scorerId == state.myUserId);
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
    // Voir demande utilisateur : "ça doit être instantané".
    if (_commentsBoxId != null) unawaited(WalletBalanceNotifier.instance.refresh());
    // Scoreboard systématique, même après un abandon (voir demande
    // utilisateur : "si on abandonne, on a le score en bas pour tous les
    // jeux, il faut proposer de quitter et pour rejouer c'est pour celui
    // qui a lancé le jeu") — _showScoreboard gère déjà "Quitter" pour tous
    // et "Rejouer" réservé à widget.isLauncher.
    WidgetsBinding.instance.addPostFrameCallback((_) => _showScoreboard());
  }

  void _showScoreBanner(String scorerId, {required bool mine}) {
    if (!mounted) return;
    final text = mine
        ? LocaleScope.t(context, 'ttt_you_scored')
        : LocaleScope.t(context, 'ttt_point_for', {
            'name': widget.playerNames[scorerId] ?? LocaleScope.t(context, 'memory_board_partner_fallback'),
          });
    _scoreBannerTimer?.cancel();
    setState(() {
      _scoreBannerSeq++;
      _scoreBanner = (text: text, mine: mine);
    });
    // Un peu moins longtemps que la surbrillance de la ligne (voir _kScoreHighlightDuration).
    _scoreBannerTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _scoreBanner = null);
    });
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
      allowRematch: widget.isLauncher && widget.onRematch != null,
    );
    if (rematch == true && widget.isLauncher && widget.onRematch != null && mounted) {
      // Voir demande utilisateur : le chrono et l'appel continuent sans
      // coupure entre deux manches — pas de closeGameSession ici.
      await widget.onRematch!(context);
    } else if (mounted) {
      // "Quitter", ou tap à côté de la feuille (voir demande utilisateur) : referme le jeu
      // (retour au choix de la difficulté pour l'invité·e, voir onQuit).
      // Voir demande utilisateur : "on peut quitter sans forcément cliquer
      // sur le bouton quitter" — ce branchement couvre déjà les deux cas.
      // Ferme VRAIMENT la session (arrête micro/caméra/chrono/facturation
      // pour les DEUX, voir GameSessionLifecycleController).
      final transport = widget.transport;
      if (transport is RemoteTicTacToeTransport) {
        unawaited(GameService.instance.closeGameSession('tic_tac_toe', transport.sessionId));
      }
      if (widget.onQuit != null) {
        await widget.onQuit!(context);
      } else {
        Navigator.of(context).pop();
      }
    }
  }

  /// Voir demande utilisateur : repousse la coupure automatique
  /// d'inactivité tant que NOTRE PROPRE micro se rouvre après la fin de la
  /// manche (voir VoiceCallOverlay.onMicActiveChanged).
  void _onMicActiveChanged(bool active) {
    if (!active || !_state.finished) return;
    final transport = widget.transport;
    if (transport is RemoteTicTacToeTransport) {
      unawaited(GameService.instance.pingGameSessionMic('tic_tac_toe', transport.sessionId));
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
    // Le chrono attend la même période de grâce que l'anneau de token
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

  @override
  void dispose() {
    _subscription.cancel();
    ShowcaseView.get().removeOnCompleteCallback(_onGuideStepTapped);
    ShowcaseView.get().removeOnDismissCallback(_onGuideDismissed);
    _clockTimer?.cancel();
    _highlightTimer?.cancel();
    _scoreBannerTimer?.cancel();
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

  // Voir memory_game_board_screen.dart (même pattern, phase 4).
  String? get _friendSessionType =>
      (widget.transport is RemoteTicTacToeTransport && _commentsBoxId == null) ? 'tic_tac_toe' : null;

  /// Bouton "Terminer la partie" du popup de solde épuisé (voir
  /// GameWalletGuard) — même geste qu'un abandon volontaire.
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
        // Ne referme plus l'écran soi-même (voir demande utilisateur :
        // scoreboard systématique après un abandon, même geste que le
        // bouton drapeau ci-dessous) — _maybeShowScoreboard détecte
        // `state.finished` et affiche le tableau de score (avec "Rejouer"
        // pour le lanceur, "Quitter" pour tous), qui referme l'écran
        // lui-même.
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
                      icon: _resuming
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_circle_outline),
                      tooltip: (_state.pausedByMe || _state.pausedByUserId == null)
                          ? LocaleScope.t(context, 'memory_board_resume_tooltip')
                          : LocaleScope.t(context, 'memory_board_paused_by_partner_tooltip', {
                              'name': widget.playerNames[_state.pausedByUserId] ??
                                  LocaleScope.t(context, 'memory_board_partner_fallback'),
                            }),
                      onPressed: (!_resuming && (_state.pausedByMe || _state.pausedByUserId == null))
                          ? () => handleResumeTap(context, widget.transport.resume, (busy) => setState(() => _resuming = busy))
                          : null,
                    )
                  : IconButton(
                      icon: const Icon(Icons.pause_circle_outline),
                      tooltip: LocaleScope.t(context, 'memory_board_pause_tooltip'),
                      onPressed: () => widget.transport.pause(),
                    ),
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
                  await widget.transport.abandon();
                }
              },
            ),
          // Une fois la partie finie, le seul moyen de rejouer était la
          // fenêtre de score qui vient de se fermer — bouton permanent une
          // fois qu'elle a disparu (voir demande utilisateur : "comment
          // rejouer ou quitter à partir de là" — quitter reste la flèche
          // retour standard, déjà là).
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
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Showcase(
                        key: _turnGuideKey,
                        title: 'À qui de jouer ?',
                        description: 'Ce texte indique à qui c\'est le tour de jouer.',
                        targetBorderRadius: BorderRadius.circular(8),
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
                          if (commentsBoxId != null && widget.isLauncher && !SubscriptionStatusNotifier.instance.isActive) ...[
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
                        child: Builder(builder: (context) {
                          final chip = _TicTacToePlayerChip(
                            theme: theme,
                            name: widget.playerNames[userId] ?? '',
                            avatar: widget.playerAvatars[userId],
                            mine: _markerFor(userId) == _Marker.heart,
                            active: _state.currentTurnUserId == userId,
                            score: _state.scoreFor(userId),
                            targetScore: _state.targetScore,
                          );
                          if (_state.currentTurnUserId != userId) return chip;
                          return Showcase(
                            key: _activeNameGuideKey,
                            title: 'Le nom en surbrillance',
                            description: 'Le nom coloré indique le joueur dont c\'est le tour en ce moment.',
                            targetBorderRadius: BorderRadius.circular(14),
                            child: chip,
                          );
                        }),
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
                              // Case "posée" par le guide (voir doc de
                              // classe de _TicTacToeGuideStep) — purement
                              // visuelle, jamais transmise à
                              // widget.transport.place() (voir
                              // _onGuidePlacementTap et demande
                              // utilisateur : simulation locale, jamais
                              // dépendante du binôme).
                              final guideOccupant =
                                  (index == _guidePlaceIndex && _guidePlaced) ? widget.user.id : null;
                              final occupant = displayBoard[index] ?? guideOccupant;
                              // Sélection factice active (voir
                              // _onGuideSelectTap) — indépendante de
                              // l'index, contrairement à isThisCellSelected
                              // ci-dessous, pour que TOUTES les cases
                              // vides s'affichent comme destinations
                              // valides pendant l'étape moveTap (même
                              // logique que _selectedPosition != null en
                              // temps réel).
                              final guideSelectionActive =
                                  _guideStep == _TicTacToeGuideStep.moveTap && _guideSelected;
                              final isThisCellSelected = guideSelectionActive && index == _guidePlaceIndex;
                              final tile = _TicTacToeCellTile(
                                theme: theme,
                                marker: occupant == null ? null : _markerFor(occupant),
                                selected: _selectedPosition == index || isThisCellSelected,
                                movableTarget: _highlightBoard == null &&
                                    (_selectedPosition != null || guideSelectionActive) &&
                                    occupant == null,
                                justScored: _highlightedLine?.contains(index) ?? false,
                                onTap: () {
                                  if (_guideStep == _TicTacToeGuideStep.placementTap && index == _guidePlaceIndex) {
                                    _onGuidePlacementTap();
                                    return;
                                  }
                                  if (_guideStep == _TicTacToeGuideStep.selectTap && index == _guidePlaceIndex) {
                                    _onGuideSelectTap();
                                    return;
                                  }
                                  if (_guideStep == _TicTacToeGuideStep.moveTap && index == _guideMoveIndex) {
                                    _onGuideMoveTap();
                                    return;
                                  }
                                  _onTapCell(index);
                                },
                              );
                              if (_guideStep == _TicTacToeGuideStep.placementTap && index == _guidePlaceIndex) {
                                return Showcase(
                                  key: _gridGuideKey,
                                  title: 'Place un pion',
                                  description: 'Tape cette case vide pour y placer un pion.',
                                  targetBorderRadius: BorderRadius.circular(8),
                                  disableDefaultTargetGestures: true,
                                  child: tile,
                                );
                              }
                              if (_guideStep == _TicTacToeGuideStep.selectTap && index == _guidePlaceIndex) {
                                return Showcase(
                                  key: _gridGuideKey,
                                  title: 'Sélectionne ton pion',
                                  description:
                                      "En phase de déplacement, tape d'abord un de tes pions pour le sélectionner.",
                                  targetBorderRadius: BorderRadius.circular(8),
                                  disableDefaultTargetGestures: true,
                                  child: tile,
                                );
                              }
                              if (_guideStep == _TicTacToeGuideStep.moveTap && index == _guideMoveIndex) {
                                return Showcase(
                                  key: _gridGuideKey,
                                  title: 'Déplace-le ici',
                                  description: 'Tape une case vide pour y déplacer le pion sélectionné.',
                                  targetBorderRadius: BorderRadius.circular(8),
                                  disableDefaultTargetGestures: true,
                                  child: tile,
                                );
                              }
                              return tile;
                            },
                          ),
                          if (_state.isPaused && _guideStep == null)
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
                                          onPressed: _resuming
                                              ? null
                                              : () => handleResumeTap(context, widget.transport.resume, (busy) => setState(() => _resuming = busy)),
                                          icon: _resuming
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                )
                                              : const Icon(Icons.play_arrow_rounded),
                                          label: Text(LocaleScope.t(context, 'memory_board_resume_button')),
                                          style: ElevatedButton.styleFrom(backgroundColor: theme.primary, foregroundColor: Colors.white),
                                        ),
                                        if (_state.pausedByUserId == null) GameWalletDepletedNotice(theme: theme),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          // Point marqué : étiquette au CENTRE du plateau, par-dessus la grille, sans
                          // jamais bloquer les touches (IgnorePointer).
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Center(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 260),
                                  switchInCurve: Curves.easeOutBack,
                                  switchOutCurve: Curves.easeIn,
                                  transitionBuilder: (child, animation) => FadeTransition(
                                    opacity: animation,
                                    child: ScaleTransition(scale: Tween<double>(begin: 0.7, end: 1).animate(animation), child: child),
                                  ),
                                  child: _scoreBanner == null
                                      ? const SizedBox.shrink(key: ValueKey('score-banner-none'))
                                      : _TicTacToeScoreBanner(
                                          key: ValueKey(_scoreBannerSeq),
                                          theme: theme,
                                          text: _scoreBanner!.text,
                                          mine: _scoreBanner!.mine,
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
            ],
          ),
        ),
      ),
    ),
        ),
        if (commentsBoxId != null)
          GameCommentOverlay(boxId: commentsBoxId, enabled: true, guideKey: _chatGuideKey)
        else if (_friendSessionType != null)
          GameCommentOverlay(
            sessionType: _friendSessionType,
            sessionId: _sessionId,
            enabled: true,
            guideKey: _chatGuideKey,
          )
        else if (widget.nearbyComms != null)
          GameCommentOverlay(
            nearbyComms: widget.nearbyComms,
            enabled: true,
            myName: widget.nearbyMyName ?? '',
            partnerName: widget.nearbyPartnerName ?? '',
            guideKey: _chatGuideKey,
          ),
        // Voir demande utilisateur : micro/caméra restent actifs après la
        // fin de la manche jusqu'à ce qu'on quitte vraiment (voir
        // _showScoreboard) — la feuille de score, affichée PAR-DESSUS, ne
        // doit ni les cacher ni empêcher d'y toucher (voir AlwaysOnTopLayer).
        AlwaysOnTopLayer(
          child: commentsBoxId != null
              ? VoiceCallOverlay(
                  boxId: commentsBoxId,
                  myUserId: widget.user.id,
                  partnerUserId: _partnerUserId,
                  enabled: true,
                  paused: _state.isPaused,
                  forceEnded: _state.isPaused,
                  onMicActiveChanged: _onMicActiveChanged,
                )
              : _friendSessionType != null
                  ? VoiceCallOverlay(
                      sessionType: _friendSessionType,
                      sessionId: _sessionId,
                      myUserId: widget.user.id,
                      partnerUserId: _partnerUserId,
                      enabled: true,
                      paused: _state.isPaused,
                      forceEnded: _state.isPaused,
                      onMicActiveChanged: _onMicActiveChanged,
                    )
                  : widget.nearbyComms != null
                      ? NearbyVoiceOverlay(comms: widget.nearbyComms, enabled: true, paused: _state.isPaused)
                      : const SizedBox.shrink(),
        ),
        _buildGuideVoiceDemo(),
        GameWalletGuard(
          boxId: commentsBoxId,
          sessionType: 'tic_tac_toe',
          sessionId: _sessionId,
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

/// Étiquette « Point pour [prénom] ! » / « Tu as marqué un point ! » posée au centre du plateau. Celui
/// qui marque la voit en couleur pleine (dégradé de la palette, texte blanc) ; l'adversaire la voit sur
/// fond de carte, avec le nom de celui qui a marqué. Légèrement translucide pour laisser deviner la
/// ligne qui s'illumine dessous.
class _TicTacToeScoreBanner extends StatelessWidget {
  final ThemePalette theme;
  final String text;
  final bool mine;

  const _TicTacToeScoreBanner({super.key, required this.theme, required this.text, required this.mine});

  @override
  Widget build(BuildContext context) {
    final foreground = mine ? Colors.white : theme.textOnBackground;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          gradient: mine ? LinearGradient(colors: [theme.primary, theme.secondary]) : null,
          color: mine ? null : theme.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: mine ? Colors.white.withValues(alpha: 0.55) : theme.primary.withValues(alpha: 0.4), width: 1.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 22, offset: const Offset(0, 8)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events_rounded, size: 22, color: mine ? Colors.white : theme.primary),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: foreground),
              ),
            ),
          ],
        ),
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
