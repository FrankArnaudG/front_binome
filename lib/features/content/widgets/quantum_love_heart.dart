import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';

/// Portage Dart de "Quantum Love" (script Python `turtle` fourni par
/// l'utilisateur) : un cœur filaire composé de [ringCount] contours
/// concentriques progressivement vrillés (effet éventail/spirographe),
/// tournant en continu en 3D, avec une couleur qui se réchauffe du rouge
/// sombre vers l'orange sur les 8 premières secondes et une pulsation façon
/// battement de cœur. Reprend fidèlement les mêmes formules (courbe
/// paramétrique du cœur, rotation 3D séquentielle X puis Y, projection en
/// perspective, épaisseur de trait dépendante de l'échelle locale) plutôt
/// qu'une simple vidéo pré-enregistrée, pour rester personnalisable et léger.
class QuantumLoveHeart extends StatefulWidget {
  final double size;

  /// Nombre d'anneaux concentriques — 18 par défaut comme l'original.
  /// Réduit automatiquement pour les petites vignettes (voir [size]) afin
  /// de garder l'animation fluide dans les listes.
  final int? ringCount;

  /// Prénom affiché au centre du cœur (ex. le binôme à qui il est dédié).
  /// En overlay fixe plutôt que suivant les anneaux vrillés en mouvement —
  /// reste lisible pendant la rotation/pulsation, contrairement à un texte
  /// qui suivrait la courbe.
  final String? name;

  const QuantumLoveHeart({
    super.key,
    this.size = 260,
    this.ringCount,
    this.name,
  });

  @override
  State<QuantumLoveHeart> createState() => _QuantumLoveHeartState();
}

class _QuantumLoveHeartState extends State<QuantumLoveHeart>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _masterTime = 0;
  double _rotY = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final dtSeconds = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    setState(() {
      _masterTime += dtSeconds;
      // Rotation continue autour de l'axe Y — sens et vitesse repris de
      // l'original (rot_y incrémenté à chaque frame).
      _rotY += dtSeconds * 0.5;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Vignettes (petite taille, ex. tuile de la boutique) : moins d'anneaux
    // pour rester fluide dans une grille où plusieurs instances peuvent
    // tourner en même temps.
    final rings = widget.ringCount ?? (widget.size < 120 ? 10 : 18);
    final heart = RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _QuantumLoveHeartPainter(
          time: _masterTime,
          rotY: _rotY,
          ringCount: rings,
        ),
      ),
    );
    final name = widget.name?.trim();
    if (name == null || name.isEmpty) return heart;

    // Vraie rotation 3D du ruban autour de l'axe Y, pilotée par EXACTEMENT
    // la même valeur que le cœur (_rotY, pas une dérivée/approximation) —
    // garantit un même sens et une même vitesse en permanence, plutôt
    // qu'un simple effet d'aplatissement synchronisé approximativement.
    // Le rétrécissement en largeur en devient une conséquence naturelle de
    // la perspective, pas un calcul séparé à recaler à la main.
    final isBack = cos(_rotY) < 0;

    return Stack(
      alignment: Alignment.center,
      children: [
        heart,
        IgnorePointer(
          child: Transform(
            alignment: Alignment.center,
            // setEntry(3,2,...) ajoute la perspective : sans elle, une
            // rotation Y sur un plan 2D pur se contenterait de dupliquer un
            // effet d'échelle, sans vraie sensation de profondeur/tour.
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0018)
              ..rotateY(_rotY),
            // Le cœur est symétrique gauche-droite : son dos ressemble à
            // sa face. Sans ce miroir, le texte projeté sur la face
            // arrière du plan tournant apparaîtrait inversé (illisible) —
            // avec, il reste lisible des deux côtés, comme le cœur.
            child: Transform.flip(
              flipX: isBack,
              child: _NameRibbon(name: name, maxSize: widget.size),
            ),
          ),
        ),
      ],
    );
  }
}

/// Prénom surmonté d'une rose 🌹. La rotation/aplatissement en profondeur
/// est géré par le `Transform` 3D du parent (voir [QuantumLoveHeart.build])
/// — ce widget ne fait que garantir qu'un prénom long est réduit
/// ("dézoomé") pour tenir en une seule ligne, sans jamais retourner à la
/// ligne, être coupé, ni déborder.
class _NameRibbon extends StatelessWidget {
  final String name;
  final double maxSize;

  const _NameRibbon({required this.name, required this.maxSize});

  @override
  Widget build(BuildContext context) {
    final fontSize = (maxSize * 0.12).clamp(11.0, 28.0);
    final strokeColor = const Color(0xFFFF9A52);

    return SizedBox(
      width: maxSize * 0.88,
      height: maxSize * 0.42,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🌹', style: TextStyle(fontSize: fontSize * 0.85)),
            const SizedBox(height: 3),
            Text(
              name,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: GoogleFonts.greatVibes(
                color: Colors.white,
                fontSize: fontSize,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: fontSize * 0.35,
                  ),
                  Shadow(
                    color: strokeColor.withValues(alpha: 0.6),
                    blurRadius: fontSize * 0.6,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuantumLoveHeartPainter extends CustomPainter {
  final double time;
  final double rotY;
  final int ringCount;
  final int pointsPerRing;
  final double cameraDistance;

  _QuantumLoveHeartPainter({
    required this.time,
    required this.rotY,
    required this.ringCount,
    this.pointsPerRing = 64,
    this.cameraDistance = 260,
  });

  // Courbe classique du cœur (voir curve_point/manifold_mode=0 côté Python).
  static Offset _heartPoint(double u) {
    final x = 16 * pow(sin(u), 3);
    // Signe inversé : la formule classique place la pointe du cœur en Y
    // négatif (repère mathématique, Y croît vers le haut), alors que le
    // canvas Flutter a Y croissant vers le bas — sans cette inversion la
    // pointe se retrouvait en haut de l'écran au lieu d'en bas.
    final y = -(13 * cos(u) - 5 * cos(2 * u) - 2 * cos(3 * u) - cos(4 * u));
    return Offset(x.toDouble(), y.toDouble());
  }

  // Rotation 3D séquentielle : d'abord (y,z) autour de X, puis (x,z)
  // autour de Y — l'ordre compte, ce ne sont pas deux rotations
  // indépendantes appliquées simultanément (fidèle à rotate3d côté Python).
  static ({double x, double y, double z}) _rotate3d(
    double x,
    double y,
    double z,
    double ax,
    double ay,
  ) {
    final cosAx = cos(ax), sinAx = sin(ax);
    final y1 = y * cosAx - z * sinAx;
    final z1 = y * sinAx + z * cosAx;
    final cosAy = cos(ay), sinAy = sin(ay);
    final x2 = x * cosAy + z1 * sinAy;
    final z2 = -x * sinAy + z1 * cosAy;
    return (x: x2, y: y1, z: z2);
  }

  ({double x, double y, double scale}) _project(double x, double y, double z) {
    final scale = cameraDistance / (cameraDistance + z);
    return (x: x * scale, y: y * scale, scale: scale);
  }

  // HSV de l'anneau i : chaleur (dérive rouge sombre -> orange sur 8s),
  // pulsation façon battement de cœur, léger décalage de teinte par anneau.
  Color _ringColor(int i, double warmProgress, double pulse) {
    const baseHue = 355.0; // rouge/bordeaux
    const warmHue = 28.0; // orange chaud
    final hueDrift = baseHue + (warmHue - baseHue) * warmProgress;
    final ringOffset = ringCount > 1 ? (i / (ringCount - 1)) * 10 : 0.0;
    final hue = (hueDrift + ringOffset) % 360;

    final saturation = (0.55 + 0.35 * pulse - 0.15 * warmProgress).clamp(
      0.0,
      1.0,
    );
    final value = (0.35 + 0.25 * warmProgress + 0.35 * pulse).clamp(0.0, 1.0);

    return HSVColor.fromAHSV(1, hue, saturation, value).toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseScale = size.width / 46;

    // Battement de cœur : légère variation d'échelle globale.
    final pulse = 1.0 + 0.09 * sin(time * 4.2);
    // Ouverture progressive de l'éventail sur les 6 premières secondes,
    // avec une petite respiration résiduelle une fois ouvert.
    final openRamp = (time / 6.0).clamp(0.0, 1.0);
    final openingProgress =
        0.15 + 0.85 * openRamp + (openRamp >= 1.0 ? 0.02 * sin(time * 1.6) : 0);
    // Réchauffement colorimétrique sur les 8 premières secondes.
    final warmProgress = (time / 8.0).clamp(0.0, 1.0);
    // Léger tangage fixe pour donner du volume à la rotation Y continue.
    const tiltX = 0.22;

    for (var i = 0; i < ringCount; i++) {
      // Vrille modeste par anneau : assez pour l'effet "éventail" en
      // couches, sans aller jusqu'à transformer le cœur en spirale/rosace
      // méconnaissable (0.12 rad/anneau, testé en réel, donnait ce défaut).
      final twist = i * 0.025 * openingProgress;
      final depth = (i - ringCount / 2) * 6.0;
      final cosT = cos(twist), sinT = sin(twist);

      Offset? prevProjected;
      double? prevScale;

      for (var s = 0; s <= pointsPerRing; s++) {
        final u = (s / pointsPerRing) * 2 * pi;
        final p = _heartPoint(u);

        // Vrille 2D dans le plan de l'anneau.
        final tx = p.dx * cosT - p.dy * sinT;
        final ty = p.dx * sinT + p.dy * cosT;

        final scaled = Offset(tx, ty) * (baseScale * pulse);
        final rotated = _rotate3d(scaled.dx, scaled.dy, depth, tiltX, rotY);
        final projected = _project(rotated.x, rotated.y, rotated.z);
        final point = center + Offset(projected.x, projected.y);

        if (prevProjected != null) {
          final localScale = (projected.scale + prevScale!) / 2;
          final color = _ringColor(i, warmProgress, pulse);
          final paint = Paint()
            ..color = color
            ..strokeWidth = (localScale * 2.2).clamp(0.6, 4.0)
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke;
          canvas.drawLine(prevProjected, point, paint);
        }
        prevProjected = point;
        prevScale = projected.scale;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QuantumLoveHeartPainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.rotY != rotY;
}
