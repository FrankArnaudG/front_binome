import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/locale_scope.dart';
import '../../models/app_user.dart';
import '../../models/emoji_story_stats.dart';
import '../../models/game.dart';
import '../../models/game_box.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/empty_state.dart';
import 'game_box_session_screen.dart';
import 'game_service.dart';
import 'truth_or_dare_session_screen.dart';
import 'widgets/game_box_icon.dart';
import 'widgets/quiz_match_scoreboard.dart';

/// Liste des boîtes d'un jeu (voir GameBox côté backend) — des catégories
/// thématiques façon coffres, TOUTES ouvertes d'entrée (voir
/// GameBoxController::index, `unlocked` toujours vrai) : chaque partenaire
/// choisit librement celle qui lui convient, jamais forcé de traverser des
/// thèmes plus intimes avant d'être prêt.
class GameBoxesScreen extends StatefulWidget {
  final Game game;
  final AppUser user;

  const GameBoxesScreen({super.key, required this.game, required this.user});

  @override
  State<GameBoxesScreen> createState() => _GameBoxesScreenState();
}

class _GameBoxesScreenState extends State<GameBoxesScreen> {
  List<GameBox>? _boxes;
  bool _loading = true;
  bool _error = false;

  // Score "façon match" — uniquement pour les jeux `session_type = 'quiz'`
  // (voir Game.isQuiz), affiché en badge dans l'AppBar comme
  // EmojiStorySessionScreen._matchStats.
  EmojiStoryMatchStats? _matchStats;

  @override
  void initState() {
    super.initState();
    _loadCachedThenRefresh();
    if (widget.game.isQuiz) _loadStats();
  }

  Future<void> _loadStats() async {
    final cached = await GameService.instance.cachedQuizStats(widget.game.id);
    if (cached != null && mounted) setState(() => _matchStats = cached);
    try {
      final stats = await GameService.instance.fetchQuizStats(widget.game.id);
      if (mounted) setState(() => _matchStats = stats);
    } catch (_) {
      // best effort — le badge reste juste absent/périmé si le réseau échoue.
    }
  }

  /// Affiche la dernière liste connue tout de suite (voir
  /// GameService.cachedBoxes), avant même la réponse réseau, comme le
  /// Carnet de bord (TimelineScreen) ou GameBoxHistoryScreen — la mise à
  /// jour se fait ensuite silencieusement en arrière-plan si la connexion
  /// est là.
  Future<void> _loadCachedThenRefresh() async {
    final cached = await GameService.instance.cachedBoxes(widget.game.id);
    if (cached != null && mounted) {
      setState(() {
        _boxes = cached;
        _loading = false;
      });
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    try {
      final boxes = await GameService.instance.fetchBoxes(widget.game.id);
      if (!mounted) return;
      setState(() {
        _boxes = boxes;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Ne bascule en erreur que si on n'a vraiment rien à montrer (ni
        // cache, ni fetch précédent) — sinon la liste déjà affichée reste,
        // le prochain tirer-pour-rafraîchir réessaiera.
        if (_boxes == null) _error = true;
      });
    }
  }

  Future<void> _openBox(GameBox box, List<GameBox> allBoxes) async {
    if (!box.unlocked) {
      final previous = allBoxes[allBoxes.indexOf(box) - 1];
      final localeCode = LocaleScope.of(context).current.code;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LocaleScope.of(context).t(
          'games_box_finish_first',
          {'title': previous.titleFor(localeCode)},
        ))),
      );
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => widget.game.isTruthOrDare
            ? TruthOrDareSessionScreen(game: widget.game, box: box, user: widget.user)
            : GameBoxSessionScreen(game: widget.game, box: box, user: widget.user),
      ),
    );
    if (changed == true) {
      _refresh();
      if (widget.game.isQuiz) _loadStats();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final localeCode = LocaleScope.of(context).current.code;
    final t = LocaleScope.of(context).t;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(
          widget.game.nameFor(localeCode),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
        actions: [
          if (_matchStats != null && _matchStats!.totalResolved > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => showQuizMatchScoreboard(
                    context,
                    theme: theme,
                    stats: _matchStats!,
                    myUserId: widget.user.id,
                    gameName: widget.game.nameFor(localeCode),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: theme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🏆', style: TextStyle(fontSize: 12)),
                        const SizedBox(width: 5),
                        Text(
                          '${_matchStats!.totalFirstTry}/${_matchStats!.totalResolved}',
                          style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: theme.textOnBackground),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.chevron_right_rounded, size: 14, color: theme.textOnBackgroundMuted),
                      ],
                    ),
                  ),
                ),
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
            child: Builder(
              builder: (context) {
                if (_loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (_error) {
                  return ListView(
                    children: [
                      EmptyState(icon: Icons.wifi_off_rounded, message: t('games_boxes_load_error')),
                    ],
                  );
                }
                final boxes = _boxes ?? [];
                final description = widget.game.descriptionFor(localeCode);
                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (description != null) ...[
                      Text(
                        description,
                        style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                      ),
                      const SizedBox(height: 20),
                    ],
                    for (final box in boxes) ...[
                      _GameBoxTile(box: box, theme: theme, onTap: () => _openBox(box, boxes)),
                      const SizedBox(height: 14),
                    ],
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

class _GameBoxTile extends StatelessWidget {
  final GameBox box;
  final ThemePalette theme;
  final VoidCallback onTap;

  const _GameBoxTile({required this.box, required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final locked = !box.unlocked;
    final localeCode = LocaleScope.of(context).current.code;

    return Opacity(
      opacity: locked ? 0.5 : 1,
      child: Material(
        color: theme.surface.withValues(alpha: theme.isDark ? 0.5 : 0.75),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: box.completed
                    ? theme.primary.withValues(alpha: 0.5)
                    : theme.primary.withValues(alpha: locked ? 0.12 : 0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [theme.primary, theme.secondary]),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: (!locked && box.imagePath != null)
                      ? Image.network(
                          box.imagePath!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Icon(iconForGameBox(box.iconKey), color: Colors.white, size: 24),
                        )
                      : Icon(
                          locked ? Icons.lock_rounded : iconForGameBox(box.iconKey),
                          color: Colors.white,
                          size: 24,
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        box.titleFor(localeCode),
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: theme.textOnBackground),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        box.themeFor(localeCode),
                        style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                      ),
                    ],
                  ),
                ),
                if (box.completed)
                  Icon(Icons.check_circle_rounded, color: theme.primary, size: 22)
                else if (!locked)
                  Icon(Icons.chevron_right_rounded, color: theme.textOnBackgroundMuted, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
