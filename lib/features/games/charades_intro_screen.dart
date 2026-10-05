import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/locale_scope.dart';
import '../../models/game.dart';
import '../../models/game_box.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import 'charades_categories_screen.dart';
import 'widgets/glass_session_card.dart';

/// Écran de présentation du jeu de mime (voir demande utilisateur, maquette
/// "Écran 1 — Présentation") — premier écran vu en ouvrant le jeu, avant le
/// choix de catégorie (voir CharadesCategoriesScreen), simple rideau
/// d'ouverture plutôt qu'un détail des règles (déjà disponible via
/// Game.rulesFor ailleurs dans l'app).
class CharadesIntroScreen extends StatelessWidget {
  final Game game;
  final List<GameBox> boxes;

  const CharadesIntroScreen({super.key, required this.game, required this.boxes});

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
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: GlassSessionCard(
                theme: theme,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [theme.primary, theme.secondary]),
                      ),
                      alignment: Alignment.center,
                      child: const Text('🎭', style: TextStyle(fontSize: 38)),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      game.nameFor(localeCode).toUpperCase(),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w800, color: theme.textOnBackground),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        description,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.nunito(fontSize: 14, height: 1.5, color: theme.textOnBackgroundMuted),
                      ),
                    ],
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(colors: [theme.primary, theme.secondary]),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (_) => CharadesCategoriesScreen(game: game, boxes: boxes)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                'COMMENCER',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 15, letterSpacing: 0.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
