import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/theme_palette.dart';

/// Icône/dégradé d'une catégorie de Poèmes-Slides, par slug — choix produit
/// volontairement fixé côté app (pas de sélecteur d'icône dans l'admin, voir
/// PackCategoryController côté backend). Le nom/l'accroche viennent de
/// l'admin, traduits dans les 12 langues (voir [PackCategory] et
/// ContentService.fetchPackCategories) — [PackCategoryVisual] ne porte plus
/// que l'apparence.
class PackCategoryVisual {
  final String assetName;
  final IconData icon;
  final Color Function(ThemePalette) colorStart;
  final Color Function(ThemePalette) colorEnd;

  const PackCategoryVisual(
    this.assetName,
    this.icon,
    this.colorStart,
    this.colorEnd,
  );

  List<Color> gradient(ThemePalette theme) => [
    colorStart(theme),
    colorEnd(theme),
  ];
}

const Map<String, PackCategoryVisual> packCategoryVisuals = {
  'morning': PackCategoryVisual(
    'category_morning.png',
    Icons.wb_sunny_rounded,
    _accent,
    _primary,
  ),
  'night': PackCategoryVisual(
    'category_night.png',
    Icons.nightlight_round,
    _primaryDeep,
    _secondary,
  ),
  'distance': PackCategoryVisual(
    'category_distance.png',
    Icons.flight_rounded,
    _secondary,
    _primary,
  ),
  'celebration': PackCategoryVisual(
    'category_celebration.png',
    Icons.celebration_rounded,
    _primary,
    _accent,
  ),
  'reconciliation': PackCategoryVisual(
    'category_reconciliation.png',
    Icons.volunteer_activism_rounded,
    _accent,
    _secondary,
  ),
  'humor': PackCategoryVisual(
    'category_humor.png',
    Icons.emoji_emotions_rounded,
    _secondary,
    _accent,
  ),
  'gratitude': PackCategoryVisual(
    'category_gratitude.png',
    Icons.spa_rounded,
    _primaryDeep,
    _accent,
  ),
  'flirt': PackCategoryVisual(
    'category_flirt.png',
    Icons.local_fire_department_rounded,
    _primary,
    _secondary,
  ),
  'future': PackCategoryVisual(
    'category_future.png',
    Icons.auto_awesome_rounded,
    _accent,
    _primaryDeep,
  ),
};

const _defaultVisual = PackCategoryVisual(
  'category_default.png',
  Icons.favorite_rounded,
  _primary,
  _secondary,
);

PackCategoryVisual visualForCategory(String slug) =>
    packCategoryVisuals[slug] ?? _defaultVisual;

/// Suffixe de fichier selon le genre du profil ("Femme" → fille, "Homme" →
/// garcon) ; null pour tout autre genre (pas de variante genrée).
String? _genderSuffix(String? gender) => switch (gender) {
  'Femme' => 'fille',
  'Homme' => 'garcon',
  _ => null,
};

/// Liste des assets réellement packagés, chargée une seule fois — sert à
/// savoir quelle image de catégorie existe sans passer par un errorBuilder
/// (qui ne permet pas de savoir si on doit flouter ou non le repli).
Set<String>? _knownAssets;
final Future<Set<String>> _assetsFuture =
    AssetManifest.loadFromAssetBundle(rootBundle).then((manifest) {
      final assets = manifest.listAssets().toSet();
      _knownAssets = assets;
      return assets;
    });

/// Image par défaut d'une catégorie, packagée dans l'app. Sert de fond aux
/// cartes de pack et de slide qui n'ont pas leur propre image.
///
/// Ordre de recherche : `<slug>_<fille|garcon>.jpg` (variante selon le genre
/// de la personne qui ENVOIE le poème — ex. "Manque de toi" montre la
/// personne en manque), puis `<slug>.jpg`, puis [fallback] tant qu'aucun
/// fichier n'est déposé.
Widget categoryImage(String slug, {String? gender, required Widget fallback}) =>
    _CategoryImage(slug: slug, gender: gender, fallback: fallback);

class _CategoryImage extends StatelessWidget {
  final String slug;
  final String? gender;
  final Widget fallback;

  const _CategoryImage({
    required this.slug,
    required this.gender,
    required this.fallback,
  });

  Widget _resolve(Set<String> assets) {
    final suffix = _genderSuffix(gender);
    final candidates = [
      if (suffix != null) 'assets/categories_poeme_slide/${slug}_$suffix.jpg',
      'assets/categories_poeme_slide/$slug.jpg',
    ];
    for (final path in candidates) {
      if (assets.contains(path)) return _FullImageOnBlur(path: path);
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final known = _knownAssets;
    if (known != null) return _resolve(known);
    return FutureBuilder<Set<String>>(
      future: _assetsFuture,
      builder: (context, snapshot) =>
          snapshot.hasData ? _resolve(snapshot.data!) : const SizedBox.shrink(),
    );
  }
}

/// Affiche l'image en entier (sans zoom ni bords coupés, quelle que soit la
/// forme de la carte) : une version floutée de la même image comble le reste
/// de la carte, l'image nette est posée au centre par-dessus.
class _FullImageOnBlur extends StatelessWidget {
  final String path;

  const _FullImageOnBlur({required this.path});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Image.asset(path, fit: BoxFit.cover),
          ),
        ),
        const ColoredBox(color: Color(0x33000000)),
        Image.asset(path, fit: BoxFit.contain),
      ],
    );
  }
}

Color _accent(ThemePalette t) => t.accent;
Color _primary(ThemePalette t) => t.primary;
Color _primaryDeep(ThemePalette t) => t.primaryDeep;
Color _secondary(ThemePalette t) => t.secondary;
