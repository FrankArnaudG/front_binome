import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../models/app_user.dart';
import '../../../models/game.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../../../theme/themed_background.dart';
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
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: _starting
              ? Center(child: CircularProgressIndicator(color: theme.primary))
              : BattleshipGridSizeList(theme: theme, onSelected: _start),
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

  const BattleshipGridSizeList({super.key, required this.theme, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final gridSize in BattleshipEngine.levels) ...[
          Material(
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
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
