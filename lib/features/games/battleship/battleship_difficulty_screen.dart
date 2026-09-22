import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:showcaseview/showcaseview.dart';

import '../../../l10n/locale_scope.dart';
import '../../../models/app_user.dart';
import '../../../models/game.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../../../theme/themed_background.dart';
import '../game_guide_storage.dart';
import '../game_guide_notes.dart';
import 'battleship_engine.dart';
import 'battleship_mode_screen.dart';

/// Choix de la taille de grille (voir BattleshipEngine.levels — la flotte
/// en est dérivée, jamais choisie séparément) avant de lancer la partie —
/// copie structurelle conforme de DotSquaresDifficultyScreen ; le mode
/// présentiel connecté choisit son palier APRÈS la connexion, uniquement
/// par l'hôte (voir battleship_nearby_connect_screen.dart, qui réutilise
/// [BattleshipGridSizeList] pour ne pas dupliquer cet écran entier pour une
/// seule différence).
class BattleshipDifficultyScreen extends StatefulWidget {
  final Game game;
  final AppUser user;
  final BattleshipMode mode;

  const BattleshipDifficultyScreen({super.key, required this.game, required this.user, required this.mode});

  @override
  State<BattleshipDifficultyScreen> createState() => _BattleshipDifficultyScreenState();
}

class _BattleshipDifficultyScreenState extends State<BattleshipDifficultyScreen> {
  bool _starting = false;
  final _firstGridSizeGuideKey = GlobalKey();
  static const _guideKey = 'battleship_difficulty';

  @override
  void initState() {
    super.initState();
    _maybeStartGuide();
  }

  Future<void> _maybeStartGuide() async {
    final seen = await GameGuideStorage.instance.hasSeen(widget.user.id, _guideKey);
    if (seen || !mounted) return;
    GameGuideStorage.instance.markSeen(widget.user.id, _guideKey);
    _startGuide();
  }

  void _startGuide() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ShowcaseView.get().startShowCase([_firstGridSizeGuideKey]);
    });
  }

  Future<void> _start(int gridSize) async {
    if (_starting) return;
    setState(() => _starting = true);
    await startBattleshipAndPush(context, game: widget.game, user: widget.user, mode: widget.mode, gridSize: gridSize);
    if (mounted) setState(() => _starting = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(LocaleScope.t(context, 'battleship_difficulty_title')),
        actions: [
          IconButton(icon: const Icon(Icons.help_outline_rounded), tooltip: 'Revoir le guide', onPressed: _startGuide),
        ],
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: _starting
              ? Center(child: CircularProgressIndicator(color: theme.primary))
              : BattleshipGridSizeList(theme: theme, onSelected: _start, firstTileGuideKey: _firstGridSizeGuideKey, guideNote: widget.mode == BattleshipMode.local ? null : kHowToPlayNote),
        ),
      ),
    );
  }
}

/// Liste des paliers, extraite pour être réutilisée telle quelle par
/// l'hôte en présentiel connecté (voir battleship_nearby_connect_screen.dart).
class BattleshipGridSizeList extends StatelessWidget {
  final ThemePalette theme;
  final void Function(int gridSize) onSelected;
  // Guide pas-à-pas (voir demande utilisateur) — non-null uniquement pour
  // faire apparaître une bulle sur le PREMIER palier de la liste.
  final GlobalKey? firstTileGuideKey;
  // N.B. ajouté à la bulle du guide (voir game_guide_notes.dart) — null en mode "un seul téléphone".
  final String? guideNote;

  const BattleshipGridSizeList({super.key, required this.theme, required this.onSelected, this.firstTileGuideKey, this.guideNote});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final (index, gridSize) in BattleshipEngine.levels.indexed) ...[
          _buildTile(context, gridSize, index == 0 ? firstTileGuideKey : null),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildTile(BuildContext context, int gridSize, GlobalKey? guideKey) {
    final tile = Material(
      color: theme.surface.withValues(alpha: theme.isDark ? 0.5 : 0.75),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onSelected(gridSize),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [theme.primary, theme.secondary]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    '$gridSize',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  LocaleScope.t(context, 'battleship_difficulty_option', {
                    'size': '$gridSize',
                    'ships': '${BattleshipEngine.shipSizesFor(gridSize).length}',
                  }),
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: theme.textOnBackground),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.textOnBackgroundMuted, size: 22),
            ],
          ),
        ),
      ),
    );
    if (guideKey == null) return tile;
    return Showcase(
      key: guideKey,
      title: 'Choisis une taille de grille',
      description: withGuideNote('Plus la grille est grande, plus il y a de navires à placer et à couler.', guideNote),
      targetBorderRadius: BorderRadius.circular(20),
      child: tile,
    );
  }
}
