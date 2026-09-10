import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/realtime_client.dart';
import '../../l10n/locale_scope.dart';
import '../../models/app_user.dart';
import '../../models/game.dart';
import '../../models/game_box.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/empty_state.dart';
import 'charades_categories_screen.dart';
import 'emoji_story_history_screen.dart';
import 'friend_challenge_screen.dart';
import 'game_boxes_screen.dart';
import 'game_service.dart';
import 'game_session_screen.dart';
import 'memory_game/memory_game_mode_screen.dart';
import 'dot_squares/dot_squares_mode_screen.dart';
import 'number_hunt/number_hunt_mode_screen.dart';
import 'battleship/battleship_mode_screen.dart';
import 'war_card/war_card_mode_screen.dart';
import 'suit_battle/suit_battle_mode_screen.dart';
import 'tic_tac_toe/tic_tac_toe_mode_screen.dart';
import 'timed_challenge_session_screen.dart';
import 'widgets/game_rules_dialog.dart';

bool _isNetworkPath(String? path) =>
    path != null && (path.startsWith('http://') || path.startsWith('https://'));

/// Illustration choisie dans l'admin (hébergée sur le serveur) si elle
/// existe, sinon repli sur l'icône affinée par mot-clé du nom du jeu.
Widget _gameIcon(Game game, Color color) {
  if (_isNetworkPath(game.iconPath)) {
    // BoxFit.cover pour remplir toute la case (pas de bande de couleur
    // teintée qui dépasse autour) — le parent doit rester clipBehavior:
    // Clip.antiAlias pour respecter les coins arrondis.
    return Image.network(
      game.iconPath!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, error, stackTrace) => Icon(_iconForGame(game), color: color),
    );
  }
  return Center(child: Icon(_iconForGame(game), color: color));
}

/// Icône affinée par mot-clé du nom du jeu — repli tant qu'aucune
/// illustration n'a été choisie dans l'admin (voir [_gameIcon]).
IconData _iconForGame(Game game) {
  // Comparé au nom français (clé d'identité stable), jamais à la langue
  // courante — sans ça, le mapping mot-clé -> icône se casserait dès
  // qu'on affiche l'app dans une autre langue que le français.
  final n = game.nameFor('fr').toLowerCase();
  // Contrôles les plus spécifiques d'abord — certains noms partagent un mot
  // avec une catégorie plus générale ci-dessous (ex. "20 Vérités sur Nous"
  // contient "vérité", "Le Sondage Surprise" contient "surprise").
  if (n.contains('20 vérités') || n.contains('20 verites')) {
    return Icons.trending_up_rounded;
  }
  if (n.contains('sondage')) return Icons.poll_rounded;
  if (n.contains('silencieux')) return Icons.volume_off_rounded;
  if (n.contains('portrait')) return Icons.face_rounded;
  if (n.contains('story')) return Icons.camera_alt_rounded;
  if (n.contains('ping-pong') || n.contains('souvenirs')) {
    return Icons.compare_arrows_rounded;
  }
  if (n.contains('cuisine')) return Icons.restaurant_rounded;
  if (n.contains('capsule')) return Icons.inventory_2_rounded;
  if (n.contains('compliment')) return Icons.record_voice_over_rounded;
  if (n.contains('question')) return Icons.quiz_rounded;
  if (n.contains('vérité') ||
      n.contains('verite') ||
      n.contains('défi') ||
      n.contains('defi')) {
    return Icons.casino_rounded;
  }
  if (n.contains('émoji') || n.contains('emoji')) {
    return Icons.emoji_emotions_rounded;
  }
  if (n.contains('charade')) return Icons.theater_comedy_rounded;
  if (n.contains('connaît') || n.contains('connait')) {
    return Icons.fact_check_rounded;
  }
  if (n.contains('surprise')) return Icons.celebration_rounded;
  if (n.contains('mystère') || n.contains('mystere')) {
    return Icons.auto_stories_rounded;
  }
  if (n.contains('chasse') || n.contains('trésor') || n.contains('tresor')) {
    return Icons.explore_rounded;
  }
  return Icons.sports_esports_rounded;
}

class GamesMenuScreen extends StatefulWidget {
  final AppUser user;

  const GamesMenuScreen({super.key, required this.user});

  @override
  State<GamesMenuScreen> createState() => _GamesMenuScreenState();
}

class _GamesMenuScreenState extends State<GamesMenuScreen> {
  late Future<List<Game>> _future;

  // Onglet actif (voir demande utilisateur : deux boutons façon navigation
  // pour switcher entre les deux catégories, plutôt que deux sections
  // empilées) — "interactive" en premier par défaut, voir _gameSection.
  String _selectedCategory = 'interactive';

  static const _catalogChannel = 'games-catalog';

  @override
  void initState() {
    super.initState();
    _future = GameService.instance.fetchGames();
    // Canal PUBLIC (pas scopé à une Box, voir RealtimeClient.subscribePublic)
    // : diffusé par l'admin à chaque modification du catalogue (voir
    // GameCatalogUpdated côté backend) — permet à cet écran de se
    // rafraîchir tout seul, même s'il reste ouvert en arrière-plan dans
    // l'IndexedStack de MainTabScreen pendant la modification.
    RealtimeClient.instance.subscribePublic(_catalogChannel, onEvent: _onRealtimeEvent);
  }

  @override
  void dispose() {
    RealtimeClient.instance.unsubscribePublic(_catalogChannel, onEvent: _onRealtimeEvent);
    super.dispose();
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.event != 'GameCatalogUpdated') return;
    _refresh();
  }

  // L'onglet Jeux reste en mémoire (IndexedStack de MainTabScreen) : sans
  // ce rafraîchissement manuel, le catalogue ne serait plus jamais refetché
  // après le premier chargement de la session.
  Future<void> _refresh() async {
    final future = GameService.instance.fetchGames();
    if (mounted) setState(() { _future = future; });
    await future;
  }

  /// "Devine mon émoji" n'a pas de boîtes (contenu libre, composé par le
  /// couple) — écran dédié direct. Un jeu avec des boîtes (voir GameBox
  /// côté backend) ouvre la liste de coffres thématiques ; sans ça, retombe
  /// sur le gabarit à prompt unique.
  Future<void> _playGame(Game game) async {
    if (game.isEmojiStory) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EmojiStoryHistoryScreen(game: game, user: widget.user)),
      );
      return;
    }

    if (game.isMemoryGame) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MemoryGameModeScreen(game: game, user: widget.user)),
      );
      return;
    }

    if (game.isTicTacToe) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TicTacToeModeScreen(game: game, user: widget.user)),
      );
      return;
    }

    if (game.isDotSquares) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DotSquaresModeScreen(game: game, user: widget.user)),
      );
      return;
    }

    if (game.isNumberHunt) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => NumberHuntModeScreen(game: game, user: widget.user)),
      );
      return;
    }

    if (game.isWarCard) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => WarCardModeScreen(game: game, user: widget.user)),
      );
      return;
    }

    if (game.isSuitBattle) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SuitBattleModeScreen(game: game, user: widget.user)),
      );
      return;
    }


    if (game.isBattleship) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BattleshipModeScreen(game: game, user: widget.user)),
      );
      return;
    }

    List<GameBox> boxes = const [];
    Object? lastError;
    // Un jeu à boîtes (voir Game.usesBoxes) ne doit JAMAIS retomber sur le
    // gabarit générique GameSessionScreen à cause d'un simple raté réseau —
    // deux tentatives avant d'abandonner et de le signaler clairement,
    // plutôt que de rediriger silencieusement vers cet écran obsolète pour
    // ces jeux (voir le SnackBar plus bas).
    final attempts = game.usesBoxes ? 2 : 1;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        boxes = await GameService.instance.fetchBoxes(game.id);
        lastError = null;
        break;
      } catch (e) {
        lastError = e;
        debugPrint('GamesMenuScreen: fetchBoxes(${game.id}) a échoué (tentative $attempt/$attempts) ($e)');
      }
    }
    if (!mounted) return;

    if (lastError != null && boxes.isEmpty && game.usesBoxes) {
      // N'ouvre plus JAMAIS le gabarit à prompt unique pour un jeu à
      // boîtes — mieux vaut un message d'erreur explicite, qu'on peut
      // corriger en réessayant, qu'un écran silencieusement faux.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LocaleScope.of(context).t('games_menu_categories_load_error'))),
      );
      return;
    }

    // Les catégories de charades ne sont pas verrouillées/progressives
    // (voir CharadesCategoriesScreen) — écran dédié plutôt que GameBoxesScreen.
    if (game.isCharades && boxes.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CharadesCategoriesScreen(game: game, boxes: boxes)),
      );
      return;
    }

    // Un seul pool de prompts admin, pas de choix de catégorie : ces
    // gabarits n'ont besoin que d'un dé à relancer (prompt_reveal) ou d'un
    // thème avant un chrono (timed_challenge/blind_poll).
    final prompts = boxes.expand((b) => b.questions).toList();

    if (game.isPromptReveal) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GameSessionScreen(game: game, prompts: prompts)),
      );
      return;
    }
    if (game.isTimedChallenge) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TimedChallengeSessionScreen(game: game, prompts: prompts)),
      );
      return;
    }
    if (boxes.isEmpty && game.usesBoxes) {
      // Chargement réussi mais réellement aucune boîte configurée pour ce
      // jeu — cas qui ne devrait jamais arriver en pratique pour un jeu
      // usesBoxes (voir le seeder de contenu), donc traité comme une
      // anomalie plutôt qu'un simple repli silencieux vers l'écran générique.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LocaleScope.of(context).t('games_menu_no_categories'))),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => boxes.isNotEmpty
            ? GameBoxesScreen(game: game, user: widget.user, initialBoxes: boxes)
            : GameSessionScreen(game: game),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(
          t('games_menu_title'),
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: theme.textOnBackground,
          ),
        ),
        // Défier quelqu'un hors de sa propre Box, via son code ami — voir
        // demande utilisateur (principe "TikTok", jamais un forum public).
        actions: [
          IconButton(
            tooltip: 'Défier un ami',
            icon: const Icon(Icons.person_add_alt_1_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => FriendChallengeScreen(user: widget.user)),
            ),
          ),
        ],
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: RefreshIndicator(
            color: theme.primary,
            backgroundColor: theme.surface,
            onRefresh: _refresh,
            child: FutureBuilder<List<Game>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return ListView(
                    children: [
                      EmptyState(
                        icon: Icons.wifi_off_rounded,
                        message: t('games_menu_load_error'),
                      ),
                    ],
                  );
                }
                final games = snapshot.data ?? [];
                final filtered = games.where((g) => g.isInteractiveCategory == (_selectedCategory == 'interactive')).toList();
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  children: [
                    // Deux boutons façon navigation pour switcher entre les
                    // catégories (voir demande utilisateur) — "Jeu
                    // interactif" (les 8 mini-jeux temps réel, voir
                    // Game.isInteractiveCategory) en premier, puisque c'est
                    // le groupe qui demande une vraie présence simultanée
                    // des deux partenaires ; "Jeu classique" ensuite (boîtes
                    // à cartes/prompts, échange asynchrone).
                    Row(
                      children: [
                        Expanded(
                          child: _CategoryTab(
                            label: t('games_menu_category_interactive'),
                            selected: _selectedCategory == 'interactive',
                            theme: theme,
                            onTap: () => setState(() => _selectedCategory = 'interactive'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CategoryTab(
                            label: t('games_menu_category_classic'),
                            selected: _selectedCategory == 'classic',
                            theme: theme,
                            onTap: () => setState(() => _selectedCategory = 'classic'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Sous-titre propre à la catégorie active (voir demande
                    // utilisateur) — remplace l'ancien titre/sous-titre fixe
                    // "Moments de Complicité".
                    Text(
                      _selectedCategory == 'interactive'
                          ? t('games_menu_category_interactive_subtitle')
                          : t('games_menu_category_classic_subtitle'),
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        color: theme.textOnBackgroundMuted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (filtered.isEmpty)
                      EmptyState(
                        icon: Icons.sports_esports_rounded,
                        message: t('games_menu_empty'),
                      )
                    else
                      ...filtered.map(
                        (game) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _GameFlipCard(
                            game: game,
                            theme: theme,
                            onPlay: () => _playGame(game),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton façon navigation pour switcher entre "Jeu interactif"/"Jeu
/// classique" (voir GamesMenuScreen._selectedCategory) — pleine largeur,
/// même esprit que _FilterChip (TimelineScreen) mais côte à côte plutôt
/// qu'en Wrap, pour lire comme deux onglets plutôt qu'une liste de filtres.
class _CategoryTab extends StatelessWidget {
  final String label;
  final bool selected;
  final ThemePalette theme;
  final VoidCallback onTap;

  const _CategoryTab({
    required this.label,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? theme.primary : theme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : (theme.isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : theme.textOnBackgroundMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeMeta {
  final String label;
  final IconData icon;
  final Color color;

  const _ModeMeta(this.label, this.icon, this.color);
}

Map<String, _ModeMeta> _modesFor(ThemePalette theme, String Function(String) t) => {
  'remote': _ModeMeta(t('games_mode_remote'), Icons.smartphone_rounded, theme.secondary),
  'in_person': _ModeMeta(
    t('games_mode_in_person'),
    Icons.diversity_1_rounded,
    theme.accent,
  ),
  'both': _ModeMeta(
    t('games_mode_both'),
    Icons.favorite_rounded,
    theme.primary,
  ),
};

/// Carte de jeu façon carte à jouer : glassmorphism + icône propre au jeu au
/// repos, se retourne au tap pour révéler "Jouer maintenant" dans la
/// couleur dominante du thème choisi (Dynamic Glow).
class _GameFlipCard extends StatefulWidget {
  final Game game;
  final ThemePalette theme;
  final Future<void> Function() onPlay;

  const _GameFlipCard({
    required this.game,
    required this.theme,
    required this.onPlay,
  });

  @override
  State<_GameFlipCard> createState() => _GameFlipCardState();
}

class _GameFlipCardState extends State<_GameFlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  bool _pressed = false;
  // Le chargement des boîtes (voir GamesMenuScreen._playGame) peut prendre
  // quelques secondes sur un réseau lent — sans ce spinner, le bouton
  // "Jouer maintenant" semblait figé/mort pendant l'attente.
  bool _loadingPlay = false;

  void _toggleFlip() {
    if (_flip.value < 0.5) {
      _flip.forward();
    } else {
      _flip.reverse();
    }
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  Future<void> _handlePlay() async {
    if (_loadingPlay) return;
    setState(() => _loadingPlay = true);
    try {
      await widget.onPlay();
    } finally {
      if (mounted) setState(() => _loadingPlay = false);
    }
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final t = LocaleScope.of(context).t;
    final mode =
        _modesFor(theme, t)[widget.game.mode] ??
        _ModeMeta('', Icons.sports_esports_rounded, theme.secondary);

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: _toggleFlip,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: SizedBox(
          height: 138,
          child: AnimatedBuilder(
            animation: _flip,
            builder: (context, _) {
              final angle = _flip.value * math.pi;
              final showingBack = _flip.value > 0.5;
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0011)
                  ..rotateY(angle),
                child: showingBack
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()..rotateY(math.pi),
                        child: _CardBack(
                          game: widget.game,
                          theme: theme,
                          onPlay: _handlePlay,
                          isLoading: _loadingPlay,
                        ),
                      )
                    : _CardFront(game: widget.game, theme: theme, mode: mode),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CardFront extends StatelessWidget {
  final Game game;
  final ThemePalette theme;
  final _ModeMeta mode;

  const _CardFront({
    required this.game,
    required this.theme,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    final localeCode = LocaleScope.of(context).current.code;
    final description = game.descriptionFor(localeCode);

    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: (theme.isDark ? Colors.white : Colors.black).withValues(
                alpha: 0.07,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: mode.color.withValues(alpha: 0.16),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: mode.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: _gameIcon(game, mode.color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.nameFor(localeCode),
                      // Sans borne, un titre traduit plus long (voir capture
                      // utilisateur, version japonaise) passait sur 2 lignes
                      // et faisait déborder la carte (hauteur fixe, voir
                      // SizedBox(height: 138) plus haut) — bandes
                      // jaune/noir d'avertissement Flutter.
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: theme.textOnBackground,
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          color: theme.textOnBackgroundMuted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Tag doux (pilule translucide) plutôt qu'un logo Wi-Fi brut.
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: mode.color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(mode.icon, size: 12, color: mode.color),
                          const SizedBox(width: 4),
                          Text(
                            mode.label,
                            style: GoogleFonts.nunito(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: mode.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Même bouton "Comment jouer" que sur le verso (_CardBack) — pour
        // qu'il soit consultable des deux côtés de la carte, pas seulement
        // une fois retournée sur "Jouer maintenant".
        _RulesButton(game: game, theme: theme),
      ],
    );
  }
}

/// Icône "Comment jouer" en médaillon, coin haut-droit — partagée par le
/// recto (_CardFront) et le verso (_CardBack) de la carte-jeu.
class _RulesButton extends StatelessWidget {
  final Game game;
  final ThemePalette theme;
  // Le verso (_CardBack) centre son contenu verticalement — un même top
  // que le recto y ferait paraître le badge trop bas par rapport au titre.
  final double top;
  final double right;

  const _RulesButton({required this.game, required this.theme, this.top = 8, this.right = 8});

  @override
  Widget build(BuildContext context) {
    final rulesText = game.rulesFor(LocaleScope.of(context).current.code);
    final hasRules = rulesText != null && rulesText.trim().isNotEmpty;
    if (!hasRules) return const SizedBox.shrink();

    return Positioned(
      top: top,
      right: right,
      child: GestureDetector(
        onTap: () => showGameRulesDialog(context, game),
        child: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.lightbulb_rounded, size: 14, color: theme.primary),
        ),
      ),
    );
  }
}

class _CardBack extends StatelessWidget {
  final Game game;
  final ThemePalette theme;
  final VoidCallback onPlay;
  final bool isLoading;

  const _CardBack({
    required this.game,
    required this.theme,
    required this.onPlay,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = LocaleScope.of(context).t;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.primary.withValues(alpha: 0.3)),
      ),
      // clipBehavior: none — le badge "Comment jouer" déborde légèrement du
      // haut de la carte (top négatif), Stack le rognerait sinon (clip par
      // défaut : Clip.hardEdge).
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                game.nameFor(LocaleScope.of(context).current.code),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: theme.textOnBackground,
                ),
              ),
              const SizedBox(height: 14),
              // Bouton "Jouer" dans la couleur dominante du thème choisi — lie
              // le jeu au monde du thème (doré, rose, émeraude...).
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: isLoading ? null : onPlay,
                      child: Ink(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [theme.primary, theme.primaryDeep],
                          ),
                        ),
                        child: isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(Colors.white),
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    t('games_play_now'),
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
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
          // Même bouton "Comment jouer" que sur le recto (_CardFront) —
          // consultable des deux côtés de la carte. Contenu centré ici (pas
          // en haut comme sur le recto) : remonté pour rester aligné au
          // coin de la carte plutôt qu'au niveau du titre.
          _RulesButton(game: game, theme: theme, top: -8, right: 2),
        ],
      ),
    );
  }
}
