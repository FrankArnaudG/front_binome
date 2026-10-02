import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/locale_scope.dart';
import '../../models/app_user.dart';
import '../../models/game.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/empty_state.dart';
import 'game_card_inbox_service.dart';
import 'game_conversations_screen.dart';
import 'game_service.dart';
import 'games_menu_screen.dart';

/// Onglet "Discussions" — voir demande utilisateur : "une icône dans la
/// barre de navigation à côté de Jeux qui permet de voir rapidement et
/// directement les discussions liées aux jeux". Liste les JEUX ("Cœur à
/// Cœur", "Vérité ou Défi"...), pas les conversations elles-mêmes (voir
/// demande utilisateur : "je propose de lister tous les jeux, et pour voir
/// une conversation il faut cliquer sur le jeu") — un jeu très actif
/// pourrait sinon compter des centaines de conversations à afficher d'un
/// coup ("si A Nous deux a 1000 conversations"). Cette liste-ci reste donc
/// toujours bornée au nombre de jeux du catalogue (une quinzaine), jamais
/// au nombre de conversations — voir GameConversationsScreen pour le détail
/// PAGINÉ d'un seul jeu, ouvert au tap sur une tuile.
class GameDiscussionsScreen extends StatefulWidget {
  final AppUser user;

  const GameDiscussionsScreen({super.key, required this.user});

  @override
  State<GameDiscussionsScreen> createState() => _GameDiscussionsScreenState();
}

class _GameDiscussionsScreenState extends State<GameDiscussionsScreen> {
  List<Game>? _games;
  bool _loading = true;
  bool _error = false;

  // Voir demande utilisateur : "la transition de passage entre discussion
  // et jeu classique se fassent comme dans jeux" — un simple index (même
  // principe que GamesMenuScreen._selectedCategory) plutôt qu'un
  // TabController : bascule immédiate, sans animation de glissement.
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadCachedThenRefresh();
    // Voir demande utilisateur : "marquer sur le badge de la liste du jeu
    // concerné" — réutilise la même source que la bulle de notification/le
    // badge de l'onglet (voir GameCardInboxService), déjà tenue à jour en
    // temps réel ailleurs dans l'app ; aucun nouvel appel réseau ici.
    GameCardInboxService.instance.refresh();
  }

  /// Voir demande utilisateur : "y a-t-il un cache pour les plus
  /// récentes" — affiche le dernier catalogue connu tout de suite (voir
  /// GameService.cachedGames), avant même la réponse réseau, comme les
  /// autres listes de jeux de l'app (GameBoxesScreen...).
  Future<void> _loadCachedThenRefresh() async {
    final cached = await GameService.instance.cachedGames();
    if (cached != null && mounted) {
      setState(() {
        _games = cached.where((g) => g.usesBoxes).toList();
        _loading = false;
      });
    }
    await _load();
  }

  Future<void> _load() async {
    try {
      final games = await GameService.instance.fetchGames();
      if (!mounted) return;
      setState(() {
        // Voir Game.usesBoxes : seuls les jeux "à boîtes" (cartes-questions)
        // produisent des envois `game_card` — les 7 jeux interactifs en
        // temps réel (Mémoire, Morpion...) n'ont jamais de discussion ici.
        _games = games.where((g) => g.usesBoxes).toList();
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_games == null) _error = true;
      });
    }
  }

  /// Nombre de cartes-questions de CE jeu reçues, pas encore traitées (voir
  /// GameCardInboxService) — même source que le badge de l'onglet
  /// "Discussions" dans la barre de navigation.
  int _unreadFor(Game game) => GameCardInboxService.instance.pending
      .where((s) => s.isGameCard && s.gameCard?.gameId == game.id)
      .length;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(
          t('game_chats_title'),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: theme.textOnBackground),
        ),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Même design que le sélecteur "Jeu interactif / Jeu
              // classique" de GamesMenuScreen (voir demande utilisateur :
              // "je veux ce design") — pastilles pleine largeur, pas une
              // TabBar Material classique.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: CategoryTab(
                        label: 'Discussions',
                        selected: _tabIndex == 0,
                        theme: theme,
                        onTap: () => setState(() => _tabIndex = 0),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CategoryTab(
                        label: 'Jeu classique',
                        selected: _tabIndex == 1,
                        theme: theme,
                        onTap: () => setState(() => _tabIndex = 1),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _tabIndex,
                  children: [
                    _buildBody(theme, t),
                    GamesMenuScreen(user: widget.user, initialCategory: 'classic', showAppBar: false),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemePalette theme, String Function(String, [Map<String, String>?]) t) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error) {
      return Center(child: EmptyState(icon: Icons.wifi_off_rounded, message: t('game_history_load_error')));
    }
    final games = List<Game>.of(_games ?? []);
    if (games.isEmpty) {
      return Center(child: EmptyState(icon: Icons.forum_rounded, message: t('game_chats_empty')));
    }

    final localeCode = LocaleScope.of(context).current.code;
    // Les jeux avec des cartes non lues remontent en tête (voir demande
    // utilisateur : le badge doit se voir tout de suite) — tri STABLE,
    // l'ordre du catalogue est conservé entre jeux à égalité.
    final withUnread = <Game>[];
    final rest = <Game>[];
    for (final game in games) {
      (_unreadFor(game) > 0 ? withUnread : rest).add(game);
    }
    final ordered = [...withUnread, ...rest];

    return AnimatedBuilder(
      // Voir doc de _unreadFor : les badges suivent GameCardInboxService en
      // direct (déjà tenu à jour par le reste de l'app), sans code temps
      // réel dédié à cet écran.
      animation: GameCardInboxService.instance,
      builder: (context, _) => RefreshIndicator(
        onRefresh: () async {
          await Future.wait([_load(), GameCardInboxService.instance.refresh()]);
        },
        child: ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: ordered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final game = ordered[index];
            // Même icône/couleur que la liste "Jeu classique" (voir demande
            // utilisateur : "remplacer par les icônes utilisées dans jeu
            // classique") — illustration choisie dans l'admin si elle
            // existe, sinon repli par mot-clé (voir gameIcon/iconForGame),
            // teintée selon le mode du jeu (voir modesFor/GameModeMeta,
            // même mapping que _CardFront).
            final mode = modesFor(theme, t)[game.mode] ?? GameModeMeta('', Icons.sports_esports_rounded, theme.secondary);
            return _GameDiscussionTile(
              theme: theme,
              game: game,
              mode: mode,
              name: game.nameFor(localeCode),
              unreadCount: _unreadFor(game),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => GameConversationsScreen(game: game, user: widget.user)),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Tuile "un jeu" — voir demande utilisateur : "il y a des designs déjà
/// dans l'app réutilisables pour lister" — copie structurelle de
/// _GameBoxTile (game_boxes_screen.dart) pour la forme, et de _CardFront
/// (games_menu_screen.dart) pour l'icône (voir demande utilisateur :
/// "remplacer par les icônes utilisées dans jeu classique") — même
/// illustration admin ou repli par mot-clé, teintée selon le mode du jeu
/// (voir gameIcon/GameModeMeta), plutôt qu'un dégradé générique. ADAPTÉE
/// d'une catégorie à un jeu entier (pas de "verrou" ici, tous les jeux sont
/// accessibles) et dotée d'un badge de non-lu (voir demande utilisateur :
/// "si y a des conversations non lues... marquer sur le badge de la liste
/// du jeu concerné").
class _GameDiscussionTile extends StatelessWidget {
  final ThemePalette theme;
  final Game game;
  final GameModeMeta mode;
  final String name;
  final int unreadCount;
  final VoidCallback onTap;

  const _GameDiscussionTile({
    required this.theme,
    required this.game,
    required this.mode,
    required this.name,
    required this.unreadCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.surface.withValues(alpha: theme.isDark ? 0.5 : 0.75),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.primary.withValues(alpha: unreadCount > 0 ? 0.45 : 0.15)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: mode.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: gameIcon(game, mode.color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: theme.textOnBackground),
                ),
              ),
              if (unreadCount > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: theme.primary, borderRadius: BorderRadius.circular(999)),
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Icon(Icons.chevron_right_rounded, color: theme.textOnBackgroundMuted, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
