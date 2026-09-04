import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../models/app_user.dart';
import '../../../models/game.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../../../theme/themed_background.dart';
import 'number_hunt_engine.dart';
import 'number_hunt_mode_screen.dart';

/// Choix de la taille de grille (voir NumberHuntEngine.levels) avant de
/// lancer la partie — copie structurelle conforme de
/// MemoryGameDifficultyScreen ; le mode présentiel connecté choisit son
/// palier APRÈS la connexion, uniquement par l'hôte (voir
/// number_hunt_nearby_connect_screen.dart, qui réutilise [NumberHuntLevelList]
/// pour ne pas dupliquer cet écran entier pour une seule différence).
class NumberHuntDifficultyScreen extends StatefulWidget {
  final Game game;
  final AppUser user;
  final NumberHuntMode mode;

  const NumberHuntDifficultyScreen({super.key, required this.game, required this.user, required this.mode});

  @override
  State<NumberHuntDifficultyScreen> createState() => _NumberHuntDifficultyScreenState();
}

class _NumberHuntDifficultyScreenState extends State<NumberHuntDifficultyScreen> {
  bool _starting = false;

  Future<void> _start(int cellCount) async {
    if (_starting) return;
    setState(() => _starting = true);
    await startNumberHuntAndPush(context, game: widget.game, user: widget.user, mode: widget.mode, cellCount: cellCount);
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
        title: Text(LocaleScope.t(context, 'number_hunt_difficulty_title')),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: _starting
              ? Center(child: CircularProgressIndicator(color: theme.primary))
              : NumberHuntLevelList(theme: theme, onSelected: _start),
        ),
      ),
    );
  }
}

/// Liste des paliers, extraite pour être réutilisée telle quelle par
/// l'hôte en présentiel connecté (voir number_hunt_nearby_connect_screen.dart).
class NumberHuntLevelList extends StatelessWidget {
  final ThemePalette theme;
  final void Function(int cellCount) onSelected;

  const NumberHuntLevelList({super.key, required this.theme, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final cellCount in NumberHuntEngine.levels) ...[
          Material(
            color: theme.surface.withValues(alpha: theme.isDark ? 0.5 : 0.75),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => onSelected(cellCount),
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
                          '$cellCount',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        LocaleScope.t(context, 'number_hunt_difficulty_count', {'count': '$cellCount'}),
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: theme.textOnBackground),
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
