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
import 'war_card_engine.dart';
import 'war_card_mode_screen.dart';

/// Choix de la taille du paquet (voir WarCardEngine.levels — "peut-on
/// mettre différent niveau en fonction du nombre de cartes", voir demande
/// utilisateur) avant de lancer la partie — copie structurelle conforme
/// de DotSquaresDifficultyScreen ; le mode présentiel connecté choisit
/// son palier APRÈS la connexion, uniquement par l'hôte (voir
/// war_card_nearby_connect_screen.dart, qui réutilise [WarCardLevelList]
/// pour ne pas dupliquer cet écran entier pour une seule différence).
class WarCardDifficultyScreen extends StatefulWidget {
  final Game game;
  final AppUser user;
  final WarCardMode mode;

  const WarCardDifficultyScreen({super.key, required this.game, required this.user, required this.mode});

  @override
  State<WarCardDifficultyScreen> createState() => _WarCardDifficultyScreenState();
}

class _WarCardDifficultyScreenState extends State<WarCardDifficultyScreen> {
  bool _starting = false;
  final _firstLevelGuideKey = GlobalKey();
  static const _guideKey = 'war_card_difficulty';

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
    await startWarCardAndPush(context, game: widget.game, user: widget.user, mode: widget.mode, deckSize: deckSize);
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
        title: Text(LocaleScope.t(context, 'war_card_difficulty_title')),
        actions: [
          IconButton(icon: const Icon(Icons.help_outline_rounded), tooltip: 'Revoir le guide', onPressed: _startGuide),
        ],
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: _starting
              ? Center(child: CircularProgressIndicator(color: theme.primary))
              : WarCardLevelList(theme: theme, onSelected: _start, firstTileGuideKey: _firstLevelGuideKey),
        ),
      ),
    );
  }
}

/// Nom court + sous-titre de chaque palier (voir WarCardEngine::LEVELS
/// côté PHP pour le détail des règles de composition).
String _levelTitleKey(int deckSize) => switch (deckSize) {
      24 => 'war_card_difficulty_fast',
      104 => 'war_card_difficulty_marathon',
      _ => 'war_card_difficulty_standard',
    };

String _levelSubtitleKey(int deckSize) => switch (deckSize) {
      24 => 'war_card_difficulty_fast_subtitle',
      104 => 'war_card_difficulty_marathon_subtitle',
      _ => 'war_card_difficulty_standard_subtitle',
    };

/// Liste des paliers, extraite pour être réutilisée telle quelle par
/// l'hôte en présentiel connecté (voir war_card_nearby_connect_screen.dart).
class WarCardLevelList extends StatelessWidget {
  final ThemePalette theme;
  final void Function(int deckSize) onSelected;
  // Guide pas-à-pas (voir demande utilisateur) — non-null uniquement pour
  // faire apparaître une bulle sur le PREMIER palier de la liste.
  final GlobalKey? firstTileGuideKey;

  const WarCardLevelList({super.key, required this.theme, required this.onSelected, this.firstTileGuideKey});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final (index, deckSize) in WarCardEngine.levels.indexed) ...[
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
                      LocaleScope.t(context, _levelTitleKey(deckSize)),
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: theme.textOnBackground),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      LocaleScope.t(context, _levelSubtitleKey(deckSize)),
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
      description: 'Plus le paquet est grand, plus la partie sera longue.',
      targetBorderRadius: BorderRadius.circular(20),
      child: tile,
    );
  }
}
