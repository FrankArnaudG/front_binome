import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:showcaseview/showcaseview.dart';

import '../../../models/app_user.dart';
import '../../../models/game.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../../../theme/themed_background.dart';
import '../game_guide_storage.dart';
import '../game_guide_notes.dart';
import 'suit_battle_engine.dart';
import 'suit_battle_mode_screen.dart';

/// Choix de la taille du paquet (voir SuitBattleEngine.levels — "on peut
/// jouer plusieurs niveaux de difficulté comme dans Bataille. pas
/// seulement 52 cartes", voir demande utilisateur) avant de lancer la
/// partie — copie structurelle conforme de WarCardDifficultyScreen ; le
/// mode présentiel connecté choisit son palier APRÈS la connexion,
/// uniquement par l'hôte (voir suit_battle_nearby_connect_screen.dart,
/// qui réutilise [SuitBattleLevelList] pour ne pas dupliquer cet écran
/// entier pour une seule différence).
class SuitBattleDifficultyScreen extends StatefulWidget {
  final Game game;
  final AppUser user;

  const SuitBattleDifficultyScreen({super.key, required this.game, required this.user});

  @override
  State<SuitBattleDifficultyScreen> createState() => _SuitBattleDifficultyScreenState();
}

class _SuitBattleDifficultyScreenState extends State<SuitBattleDifficultyScreen> {
  bool _starting = false;
  final _firstLevelGuideKey = GlobalKey();
  static const _guideKey = 'suit_battle_difficulty';

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
      ShowcaseView.get().startShowCase([_firstLevelGuideKey]);
    });
  }

  Future<void> _start(int deckSize) async {
    if (_starting) return;
    setState(() => _starting = true);
    await startSuitBattleAndPush(context, game: widget.game, user: widget.user, deckSize: deckSize);
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
        title: const Text('Choisis un format'),
        actions: [
          IconButton(icon: const Icon(Icons.help_outline_rounded), tooltip: 'Revoir le guide', onPressed: _startGuide),
        ],
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: _starting
              ? Center(child: CircularProgressIndicator(color: theme.primary))
              : SuitBattleLevelList(theme: theme, onSelected: _start, firstTileGuideKey: _firstLevelGuideKey, guideNote: kHowToPlayNote),
        ),
      ),
    );
  }
}

/// Nom court + sous-titre de chaque palier.
String _levelTitle(int deckSize) => switch (deckSize) {
      26 => 'Rapide',
      108 => 'Marathon',
      _ => 'Standard',
    };

String _levelSubtitle(int deckSize) => switch (deckSize) {
      26 => '9 à As, une main plus courte — 26 cartes',
      108 => 'Deux paquets combinés, la plus longue — 108 cartes',
      _ => '2 à As, format classique — 54 cartes',
    };

/// Liste des paliers, extraite pour être réutilisée telle quelle par
/// l'hôte en présentiel connecté (voir suit_battle_nearby_connect_screen.dart).
class SuitBattleLevelList extends StatelessWidget {
  final ThemePalette theme;
  final void Function(int deckSize) onSelected;
  // Guide pas-à-pas (voir demande utilisateur) — non-null uniquement pour
  // faire apparaître une bulle sur le PREMIER palier de la liste.
  final GlobalKey? firstTileGuideKey;
  final String? guideNote;

  const SuitBattleLevelList({super.key, required this.theme, required this.onSelected, this.firstTileGuideKey, this.guideNote});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final (index, deckSize) in SuitBattleEngine.levels.indexed) ...[
          _buildTile(context, deckSize, index == 0 ? firstTileGuideKey : null),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildTile(BuildContext context, int deckSize, GlobalKey? guideKey) {
    final tile = Material(
      color: theme.surface.withValues(alpha: theme.isDark ? 0.5 : 0.75),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onSelected(deckSize),
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
                    '$deckSize',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _levelTitle(deckSize),
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: theme.textOnBackground),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _levelSubtitle(deckSize),
                      style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                    ),
                  ],
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
      title: 'Choisis un format',
      description: withGuideNote('Plus le paquet est grand, plus la partie sera longue.', guideNote),
      targetBorderRadius: BorderRadius.circular(20),
      child: tile,
    );
  }
}
