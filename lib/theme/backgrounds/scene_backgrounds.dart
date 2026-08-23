import 'package:flutter/material.dart';

import 'glow_shapes.dart';
import 'mountain_painter.dart';
import 'starfield_painter.dart';

/// Un visuel de fond candidat — recréé en code (dégradés + formes
/// procédurales), pas une image, pour rester léger. Purement pour
/// prévisualisation dans Paramètres tant qu'il n'est pas intégré au
/// système de thème actif ([ThemePresets]).
class SceneBackground {
  final String id;
  final String name;
  final String description;
  final WidgetBuilder builder;

  const SceneBackground({required this.id, required this.name, required this.description, required this.builder});
}

const List<SceneBackground> sceneBackgrounds = [
  SceneBackground(
    id: 'sunset_mountains',
    name: 'Coucher de Soleil Montagnes',
    description: 'Ciel orangé, soleil qui se couche, montagnes en dégradé et reflet sur l\'eau.',
    builder: _sunsetMountains,
  ),
  SceneBackground(
    id: 'sunset_mountains_pink',
    name: 'Crépuscule Rosé Montagnes',
    description: 'Même structure, en tons rose-mauve au lieu d\'orange.',
    builder: _sunsetMountainsPink,
  ),
  SceneBackground(
    id: 'night_stars_soft',
    name: 'Nuit Étoilée Douce',
    description: 'Noir → indigo → bleu → rose poudré, étoiles simples et discrètes.',
    builder: _nightStarsSoft,
  ),
  SceneBackground(
    id: 'night_stars_dense',
    name: 'Nuit Étoilée Dense',
    description: 'Même dégradé, avec beaucoup plus d\'étoiles, plus petites.',
    builder: _nightStarsDense,
  ),
  SceneBackground(
    id: 'night_sparkle_teal',
    name: 'Nuit Scintillante',
    description: 'Turquoise → violet → magenta, étoiles qui brillent avec un halo.',
    builder: _nightSparkleTeal,
  ),
  SceneBackground(
    id: 'night_sparkle_indigo',
    name: 'Nuit Scintillante Indigo',
    description: 'Même style d\'étoiles scintillantes, dégradé plus bleu-violet.',
    builder: _nightSparkleIndigo,
  ),
  SceneBackground(
    id: 'golden_haze',
    name: 'Brume Dorée',
    description: 'Nuages doux et flous en tons crème et orangé, sans forme nette.',
    builder: _goldenHaze,
  ),
  SceneBackground(
    id: 'golden_haze_pink',
    name: 'Brume Rosée',
    description: 'Même brume douce, en tons rose et lavande.',
    builder: _goldenHazePink,
  ),
  SceneBackground(
    id: 'dusk_mountains_stars',
    name: 'Crépuscule Montagnes Étoilé',
    description: 'Indigo étoilé en haut, qui bascule vers un horizon rose-orangé, montagnes en bas.',
    builder: _duskMountainsStars,
  ),
  SceneBackground(
    id: 'dawn_mountains_stars',
    name: 'Aube Montagnes Étoilée',
    description: 'Même structure, en tons plus froids bleu-lavande façon aube.',
    builder: _dawnMountainsStars,
  ),
];

// ---------------------------------------------------------------------------
// Coucher de Soleil Montagnes
// ---------------------------------------------------------------------------

Widget _sunsetMountains(BuildContext context) => _buildSunsetMountains(
      skyColors: const [Color(0xFFE8722A), Color(0xFFF2954A), Color(0xFFFDDFA0), Color(0xFFE8833A), Color(0xFFC86A32)],
      sunColor: const Color(0xFFFFF3D6),
      mountainColors: const [Color(0xFFC97A3E), Color(0xFFB8642E), Color(0xFF9C4E22), Color(0xFF7A3818)],
    );

Widget _sunsetMountainsPink(BuildContext context) => _buildSunsetMountains(
      skyColors: const [Color(0xFFC2528F), Color(0xFFE17FA0), Color(0xFFFDE4E0), Color(0xFFD97A85), Color(0xFF9C5470)],
      sunColor: const Color(0xFFFFE9EC),
      mountainColors: const [Color(0xFF8C5E7A), Color(0xFF6E4560), Color(0xFF573650), Color(0xFF3E2540)],
    );

Widget _buildSunsetMountains({
  required List<Color> skyColors,
  required Color sunColor,
  required List<Color> mountainColors,
}) {
  return Container(
    decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: skyColors)),
    child: Stack(
      children: [
        Align(alignment: const Alignment(0, -0.05), child: SoftGlow(size: 260, color: sunColor)),
        Positioned.fill(
          child: CustomPaint(
            painter: MountainSilhouettePainter(layers: [
              MountainLayer(color: mountainColors[0].withValues(alpha: 0.55), heightFraction: 0.34, seed: 1, peakCount: 5),
              MountainLayer(color: mountainColors[1].withValues(alpha: 0.75), heightFraction: 0.26, seed: 2, peakCount: 6),
              MountainLayer(color: mountainColors[2], heightFraction: 0.19, seed: 3, peakCount: 5),
              MountainLayer(color: mountainColors[3], heightFraction: 0.12, seed: 4, peakCount: 7),
            ]),
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Nuit Étoilée (simple)
// ---------------------------------------------------------------------------

Widget _nightStarsSoft(BuildContext context) => _buildNightStars(dotCount: 90, sparkleCount: 0);

Widget _nightStarsDense(BuildContext context) => _buildNightStars(dotCount: 170, sparkleCount: 0);

Widget _buildNightStars({required int dotCount, required int sparkleCount}) {
  return Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [0.0, 0.15, 0.4, 0.62, 1.0],
        colors: [Color(0xFF000000), Color(0xFF0C0E2E), Color(0xFF1B2456), Color(0xFF2C5E96), Color(0xFFB98CA0)],
      ),
    ),
    child: SizedBox.expand(
      child: CustomPaint(
        painter: StarfieldPainter(seed: 7, dotCount: dotCount, sparkleCount: sparkleCount, topFraction: 0, bottomFraction: 0.62),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Nuit Scintillante
// ---------------------------------------------------------------------------

Widget _nightSparkleTeal(BuildContext context) => _buildNightSparkle(
      colors: const [Color(0xFF05171A), Color(0xFF0C3B3E), Color(0xFF16535A), Color(0xFF3A3568), Color(0xFF5A2F6E), Color(0xFF7A2F5E)],
      sparkleColor: const Color(0xFFFFF6E0),
    );

Widget _nightSparkleIndigo(BuildContext context) => _buildNightSparkle(
      colors: const [Color(0xFF050818), Color(0xFF10123A), Color(0xFF241856), Color(0xFF3A1E6E), Color(0xFF4E2378), Color(0xFF5A2A80)],
      sparkleColor: const Color(0xFFF0EBFF),
    );

Widget _buildNightSparkle({required List<Color> colors, required Color sparkleColor}) {
  return Container(
    decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors)),
    child: SizedBox.expand(
      child: CustomPaint(
        painter: StarfieldPainter(
          seed: 13,
          dotCount: 150,
          sparkleCount: 14,
          sparkleColor: sparkleColor,
          topFraction: 0,
          bottomFraction: 1,
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Brume Dorée
// ---------------------------------------------------------------------------

Widget _goldenHaze(BuildContext context) => _buildHaze(
      base: const [Color(0xFFF5A85A), Color(0xFFFCEBD0), Color(0xFFFDEDC9), Color(0xFFF7B96E)],
      blobColor: const Color(0xFFFFFCF3),
    );

Widget _goldenHazePink(BuildContext context) => _buildHaze(
      base: const [Color(0xFFE58FA8), Color(0xFFFBEAF0), Color(0xFFF3C9DE), Color(0xFFD98CAE)],
      blobColor: const Color(0xFFFFF7FB),
    );

Widget _buildHaze({required List<Color> base, required Color blobColor}) {
  return Container(
    decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: base)),
    child: Stack(
      children: [
        Positioned(bottom: -60, left: -40, child: CloudBlob(width: 260, height: 220, color: blobColor)),
        Positioned(bottom: -20, right: -60, child: CloudBlob(width: 300, height: 240, color: blobColor)),
        Positioned(bottom: 40, left: 60, child: CloudBlob(width: 220, height: 180, color: blobColor.withValues(alpha: 0.8))),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Crépuscule / Aube Montagnes Étoilé
// ---------------------------------------------------------------------------

Widget _duskMountainsStars(BuildContext context) => _buildMountainsWithStars(
      colors: const [
        Color(0xFF0A0F2E),
        Color(0xFF1B1F52),
        Color(0xFF3A2168),
        Color(0xFF6B2F72),
        Color(0xFFB84F6E),
        Color(0xFFE8875A),
        Color(0xFFF4A85E),
      ],
      mountainColor: const Color(0xFF131832),
    );

Widget _dawnMountainsStars(BuildContext context) => _buildMountainsWithStars(
      colors: const [
        Color(0xFF0A1030),
        Color(0xFF1C2258),
        Color(0xFF2E3A78),
        Color(0xFF4E5FA0),
        Color(0xFF7C8FC0),
        Color(0xFFC7B8D8),
        Color(0xFFEDE0E8),
      ],
      mountainColor: const Color(0xFF232849),
    );

Widget _buildMountainsWithStars({required List<Color> colors, required Color mountainColor}) {
  return Container(
    decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors)),
    child: Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: StarfieldPainter(seed: 21, dotCount: 80, sparkleCount: 6, topFraction: 0, bottomFraction: 0.45),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: MountainSilhouettePainter(layers: [
              MountainLayer(color: mountainColor, heightFraction: 0.12, seed: 5, peakCount: 6),
            ]),
          ),
        ),
      ],
    ),
  );
}
