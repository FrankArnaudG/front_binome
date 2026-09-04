import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../models/app_user.dart';
import '../../../models/game.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../../../theme/themed_background.dart';
import 'dot_squares_engine.dart';
import 'dot_squares_mode_screen.dart';

/// Choix de la largeur de la feuille (voir DotSquaresEngine.levels — la
/// hauteur ne change JAMAIS, voir demande utilisateur) avant de lancer la
/// partie — copie structurelle conforme de NumberHuntDifficultyScreen ;
/// le mode présentiel connecté choisit son palier APRÈS la connexion,
/// uniquement par l'hôte (voir dot_squares_nearby_connect_screen.dart,
/// qui réutilise [DotSquaresWidthList] pour ne pas dupliquer cet écran
/// entier pour une seule différence).
class DotSquaresDifficultyScreen extends StatefulWidget {
  final Game game;
  final AppUser user;
  final DotSquaresMode mode;

  const DotSquaresDifficultyScreen({super.key, required this.game, required this.user, required this.mode});

  @override
  State<DotSquaresDifficultyScreen> createState() => _DotSquaresDifficultyScreenState();
}

class _DotSquaresDifficultyScreenState extends State<DotSquaresDifficultyScreen> {
  bool _starting = false;

  Future<void> _start(int cols) async {
    if (_starting) return;
    setState(() => _starting = true);
    await startDotSquaresAndPush(context, game: widget.game, user: widget.user, mode: widget.mode, cols: cols);
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
        title: Text(LocaleScope.t(context, 'dot_squares_difficulty_title')),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: _starting
              ? Center(child: CircularProgressIndicator(color: theme.primary))
              : DotSquaresWidthList(theme: theme, onSelected: _start),
        ),
      ),
    );
  }
}

/// Liste des paliers, extraite pour être réutilisée telle quelle par
/// l'hôte en présentiel connecté (voir dot_squares_nearby_connect_screen.dart).
class DotSquaresWidthList extends StatelessWidget {
  final ThemePalette theme;
  final void Function(int cols) onSelected;

  const DotSquaresWidthList({super.key, required this.theme, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final cols in DotSquaresEngine.levels) ...[
          Material(
            color: theme.surface.withValues(alpha: theme.isDark ? 0.5 : 0.75),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => onSelected(cols),
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
                          '$cols',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        LocaleScope.t(context, 'dot_squares_difficulty_cols', {'count': '$cols'}),
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
