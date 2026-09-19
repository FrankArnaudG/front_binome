import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../models/pack.dart';
import '../../../theme/theme_palette.dart';
import '../../../core/token_storage.dart';
import '../pack_categories.dart';

bool _isNetworkPath(String? path) =>
    path != null && (path.startsWith('http://') || path.startsWith('https://'));

/// Image par défaut de la catégorie du pack ; si elle n'est pas encore
/// packagée dans l'app, repli sur l'illustration générique (hero).
///
/// Sur la grille de packs, la personne qui parcourt est celle qui enverra le
/// poème : on utilise donc son propre genre pour choisir la variante.
Widget _categoryOrHeroImage(String category) => categoryImage(
  category,
  gender: TokenStorage.currentGender,
  fallback: Image.asset('assets/images/hero_couple.jpg', fit: BoxFit.cover),
);

/// Tuile d'un pack dans une grille de packs — extraite de
/// CategoryPacksScreen (voir demande utilisateur : réutilisée telle
/// quelle par FavoritePacksScreen, même mise en page).
class PackTile extends StatelessWidget {
  final Pack pack;
  final ThemePalette theme;
  final VoidCallback onTap;

  const PackTile({
    super.key,
    required this.pack,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final visual = visualForCategory(pack.category);
    final gradient = visual.gradient(theme);

    return Material(
      color: theme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Cover choisie dans l'admin (hébergée sur le serveur)
                      // si elle existe, sinon image par défaut de la
                      // catégorie (packagée dans l'app), sinon l'illustration
                      // générique tant que celle de la catégorie n'est pas
                      // livrée.
                      if (_isNetworkPath(pack.coverPath))
                        Image.network(
                          pack.coverPath!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _categoryOrHeroImage(pack.category),
                        )
                      else
                        _categoryOrHeroImage(pack.category),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              gradient.first.withValues(alpha: 0.55),
                              gradient.last.withValues(alpha: 0.78),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                pack.titleFor(LocaleScope.of(context).current.code),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: theme.textOnBackground,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
