import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../models/app_user.dart';
import '../../../models/game.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../../../theme/themed_background.dart';
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
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: _starting
              ? Center(child: CircularProgressIndicator(color: theme.primary))
              : WarCardLevelList(theme: theme, onSelected: _start),
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

  const WarCardLevelList({super.key, required this.theme, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final deckSize in WarCardEngine.levels) ...[
          Material(
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
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
