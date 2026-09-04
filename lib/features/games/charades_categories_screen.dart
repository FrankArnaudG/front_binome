import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/locale_scope.dart';
import '../../models/game.dart';
import '../../models/game_box.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import 'charades_mime_session_screen.dart';
import 'widgets/game_box_icon.dart';

/// Liste des catégories de mots à mimer (voir GameBox côté backend) — à la
/// différence des boîtes de "A Nous deux", aucune n'est verrouillée : on
/// mime en présentiel, sans notion de progression à débloquer, donc toutes
/// les catégories sont accessibles librement dès l'ouverture.
class CharadesCategoriesScreen extends StatelessWidget {
  final Game game;
  final List<GameBox> boxes;

  const CharadesCategoriesScreen({super.key, required this.game, required this.boxes});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final localeCode = LocaleScope.of(context).current.code;
    final description = game.descriptionFor(localeCode);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(
          game.nameFor(localeCode),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (description != null) ...[
                Text(description, style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted)),
                const SizedBox(height: 20),
              ],
              for (final box in boxes) ...[
                _CategoryTile(
                  box: box,
                  theme: theme,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => CharadesMimeSessionScreen(game: game, box: box)),
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final GameBox box;
  final ThemePalette theme;
  final VoidCallback onTap;

  const _CategoryTile({required this.box, required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final localeCode = LocaleScope.of(context).current.code;
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
            border: Border.all(color: theme.primary.withValues(alpha: 0.3)),
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
                child: box.imagePath != null
                    ? Image.network(
                        box.imagePath!,
                        fit: BoxFit.cover,
                        alignment: box.imageAlignment,
                        errorBuilder: (context, error, stackTrace) =>
                            Icon(iconForGameBox(box.iconKey), color: Colors.white, size: 24),
                      )
                    : Icon(iconForGameBox(box.iconKey), color: Colors.white, size: 24),
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
                    Text(box.themeFor(localeCode), style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted)),
                    const SizedBox(height: 2),
                    Text(
                      LocaleScope.of(context).t(
                        box.questions.length > 1 ? 'charades_words_count_other' : 'charades_words_count_one',
                        {'count': '${box.questions.length}'},
                      ),
                      style: GoogleFonts.nunito(fontSize: 11, color: theme.primary),
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
  }
}
