import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';

/// Cinquième cadeau généré en direct, aux côtés de [QuantumLoveHeart],
/// [SketchedLoveHeart], [EternalRose] et [RealisticBlackRose] : un cœur en
/// vraie 3D composé de mots d'amour tracant le contour ("i love you", "je
/// t'aime", "te amo"...), glissable au doigt — même motif drag/idle-puis-
/// reprise-auto que [RealisticBlackRose], plutôt que les boutons de contrôle
/// externes (rotation auto/réinitialiser/modifier le message) de la version
/// d'origine : le message affiché reste celui composé à l'envoi (voir
/// SlideDetailScreen._mainText), pas un texte réédité dans le widget.
///
/// Le nombre de mots ci-dessous est volontairement réduit par rapport à la
/// version plein écran d'origine (pensée pour un canevas ~900px) : l'espacement
/// anti-chevauchement (voir [_generateParticles]) s'exprime en unités du
/// cœur et se resserre automatiquement à la taille réduite d'une vignette de
/// cadeau (~260px), donc moins de mots tiennent proprement sans se
/// chevaucher.
class WordHeart extends StatefulWidget {
  final double size;

  /// false pour une vignette (boutique) : pas de GestureDetector — sinon le
  /// glissement entrerait en conflit avec le défilement de la grille. La
  /// rotation reste automatique et continue dans ce cas (voir
  /// [RealisticBlackRose], même convention).
  final bool interactive;

  /// Les couleurs des mots (rose/rouge clair) ont été pensées pour un fond
  /// sombre (voir les captures d'origine) — sur un thème clair, ce même
  /// rose sur un fond rose pâle devient illisible (constaté en réel).
  /// `true` par défaut plutôt que de forcer l'appelant à toujours le
  /// préciser.
  final bool isDark;

  const WordHeart({super.key, this.size = 260, this.interactive = true, this.isDark = true});

  @override
  State<WordHeart> createState() => _WordHeartState();
}

class _HeartParticle {
  final double x, y, z;
  final double rScale; // 0 = centre, 1 = bord extérieur — pilote couleur/opacité
  final String word;
  final double fontSize;
  _HeartParticle({
    required this.x,
    required this.y,
    required this.z,
    required this.rScale,
    required this.word,
    required this.fontSize,
  });
}

class _WordHeartState extends State<WordHeart> with SingleTickerProviderStateMixin {
  static const List<String> _words = [
    "i love you", "je t'aime", "te amo", "ich liebe dich", "forever",
    "always", "sweetheart", "love you", "me & you", "for you",
  ];

  static final String _fontFamily = GoogleFonts.playfairDisplay().fontFamily!;

  late final Ticker _ticker;
  double _rotY = 0;
  double _rotX = -0.1;
  double _time = 0;
  double _idleSince = 0;

  List<_HeartParticle>? _particles;
  double _centerX = 0, _centerY = 0;
  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ticker.start();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = elapsed.inMicroseconds / 1e6 - _time;
    setState(() {
      _time += dt;
      if (!widget.interactive || _time - _idleSince > 1.2) {
        _rotY += dt * 0.28;
      }
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() {
      _rotY += d.delta.dx * 0.008;
      _rotX = (_rotX + d.delta.dy * 0.008).clamp(-1.1, 1.1);
      _idleSince = _time;
    });
  }

  // ---- Courbe de cœur 2D classique, recentrée sur sa propre boîte englobante ----
  Offset _heartOutlineRaw(double t) {
    final x = 16 * math.pow(math.sin(t), 3);
    final y = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t));
    return Offset(x.toDouble(), y.toDouble());
  }

  Offset _heartOutline(double t) {
    final o = _heartOutlineRaw(t);
    return Offset(o.dx - _centerX, o.dy - _centerY);
  }

  void _computeCenter() {
    double xMin = double.infinity, xMax = -double.infinity;
    double yMin = double.infinity, yMax = -double.infinity;
    for (double a = 0; a < math.pi * 2; a += 0.01) {
      final o = _heartOutlineRaw(a);
      if (o.dx < xMin) xMin = o.dx;
      if (o.dx > xMax) xMax = o.dx;
      if (o.dy < yMin) yMin = o.dy;
      if (o.dy > yMax) yMax = o.dy;
    }
    _centerX = (xMin + xMax) / 2;
    _centerY = (yMin + yMax) / 2;
  }

  static const double _unitScale = 16;
  static const double _zAmplitude = 85;

  Map<String, double> _surfacePoint() {
    final t = _rng.nextDouble() * math.pi * 2;
    final rScale = 0.62 + _rng.nextDouble() * 0.38;
    final o = _heartOutline(t);
    final z = (_rng.nextDouble() * 2 - 1) * _zAmplitude * (1.15 - rScale);
    return {'x': o.dx * rScale * _unitScale, 'y': o.dy * rScale * _unitScale, 'z': z, 'r': rScale};
  }

  Map<String, double> _interiorPoint() {
    final t = _rng.nextDouble() * math.pi * 2;
    final rScale = 0.15 + _rng.nextDouble() * 0.4;
    final o = _heartOutline(t);
    final zMax = _zAmplitude * 0.85 * math.sqrt(math.max(0, 1 - rScale * rScale));
    final z = (_rng.nextDouble() * 2 - 1) * zMax;
    return {'x': o.dx * rScale * _unitScale, 'y': o.dy * rScale * _unitScale, 'z': z, 'r': rScale};
  }

  Size _measure(String text, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: fontSize, fontFamily: _fontFamily)),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.size;
  }

  void _generateParticles(double size) {
    _computeCenter();
    final baseScale = size / 620;

    final particles = <_HeartParticle>[];
    final centers = <Offset>[];
    final halfSizes = <Offset>[];

    bool farEnough(double x, double y, double hw, double hh) {
      for (var i = 0; i < centers.length; i++) {
        final dx = (x - centers[i].dx).abs();
        final dy = (y - centers[i].dy).abs();
        if (dx < (hw + halfSizes[i].dx) && dy < (hh + halfSizes[i].dy)) return false;
      }
      return true;
    }

    var wordIndex = 0;

    // 1) Mots sur le contour — la majorité, tracant densément la silhouette
    const surfaceTarget = 42;
    for (var i = 0; i < surfaceTarget; i++) {
      final word = _words[wordIndex % _words.length];
      const fontPx = 10.5;
      final measured = _measure(word, fontPx);
      final hw = (measured.width / 2 + 4) / baseScale;
      final hh = (measured.height / 2 + 3) / baseScale;
      Map<String, double>? pt;
      for (var tries = 0; tries < 200; tries++) {
        final cand = _surfacePoint();
        if (farEnough(cand['x']!, cand['y']!, hw, hh)) {
          pt = cand;
          break;
        }
      }
      if (pt == null) continue;
      wordIndex++;
      final edgeCloseness = 1 - (pt['z']!.abs() / _zAmplitude);
      particles.add(_HeartParticle(
        x: pt['x']!, y: pt['y']!, z: pt['z']!, rScale: pt['r']!,
        word: word, fontSize: fontPx * (0.85 + edgeCloseness * 0.3),
      ));
      centers.add(Offset(pt['x']!, pt['y']!));
      halfSizes.add(Offset(hw, hh));
    }

    // 2) Deux mots vedettes, bien en avant au centre
    for (final word in const ["i love you", "forever"]) {
      const fontPx = 20.0;
      final t = _rng.nextDouble() * math.pi * 2;
      final rScale = 0.04 + _rng.nextDouble() * 0.06;
      final o = _heartOutline(t);
      final x = o.dx * rScale * _unitScale;
      final y = o.dy * rScale * _unitScale;
      final z = (_rng.nextDouble() * 2 - 1) * 6;
      particles.add(_HeartParticle(x: x, y: y, z: z, rScale: rScale, word: word, fontSize: fontPx));
      final measured = _measure(word, fontPx);
      centers.add(Offset(x, y));
      halfSizes.add(Offset((measured.width / 2 + 4) / baseScale, (measured.height / 2 + 3) / baseScale));
    }

    // 3) Mots d'intérieur épars, pour le volume/texture
    const interiorTarget = 12;
    for (var i = 0; i < interiorTarget; i++) {
      final word = _words[wordIndex % _words.length];
      const fontPx = 9.0;
      final measured = _measure(word, fontPx);
      final hw = (measured.width / 2 + 4) / baseScale * 1.15;
      final hh = (measured.height / 2 + 3) / baseScale * 1.15;
      Map<String, double>? pt;
      for (var tries = 0; tries < 200; tries++) {
        final cand = _interiorPoint();
        if (farEnough(cand['x']!, cand['y']!, hw, hh)) {
          pt = cand;
          break;
        }
      }
      if (pt == null) continue;
      wordIndex++;
      particles.add(_HeartParticle(x: pt['x']!, y: pt['y']!, z: pt['z']!, rScale: pt['r']!, word: word, fontSize: fontPx));
      centers.add(Offset(pt['x']!, pt['y']!));
      halfSizes.add(Offset(hw, hh));
    }

    // 4) Quelques petits cœurs sur le contour, pour la texture
    for (var i = 0; i < 8; i++) {
      const fontPx = 10.0;
      final measured = _measure("♥", fontPx);
      final hw = (measured.width / 2 + 4) / baseScale;
      final hh = (measured.height / 2 + 3) / baseScale;
      Map<String, double>? pt;
      for (var tries = 0; tries < 200; tries++) {
        final cand = _surfacePoint();
        if (farEnough(cand['x']!, cand['y']!, hw, hh)) {
          pt = cand;
          break;
        }
      }
      if (pt == null) continue;
      particles.add(_HeartParticle(x: pt['x']!, y: pt['y']!, z: pt['z']!, rScale: pt['r']!, word: "♥", fontSize: fontPx));
      centers.add(Offset(pt['x']!, pt['y']!));
      halfSizes.add(Offset(hw, hh));
    }

    _particles = particles;
  }

  @override
  Widget build(BuildContext context) {
    if (_particles == null) _generateParticles(widget.size);

    final painter = RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _HeartPainter(particles: _particles!, rotY: _rotY, rotX: _rotX, fontFamily: _fontFamily, isDark: widget.isDark),
      ),
    );
    if (!widget.interactive) return painter;
    return GestureDetector(
      onPanUpdate: _onPanUpdate,
      child: painter,
    );
  }
}

class _Proj {
  final double x, y, scale, rz;
  _Proj(this.x, this.y, this.scale, this.rz);
}

class _HeartPainter extends CustomPainter {
  final List<_HeartParticle> particles;
  final double rotY, rotX;
  final String fontFamily;
  final bool isDark;

  _HeartPainter({
    required this.particles,
    required this.rotY,
    required this.rotX,
    required this.fontFamily,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 - math.min(size.width, size.height) * 0.02;
    final baseScale = math.min(size.width, size.height) / 620;

    // Le halo façon "lueur sur fond noir" de la version d'origine ajoute
    // juste une teinte rose superflue sur un fond déjà clair — seule la
    // version sombre en a besoin pour se détacher du noir.
    if (isDark) {
      final glowR = math.min(size.width, size.height) * 0.34;
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: const [Color(0x33FF2D55), Color(0x11780A28), Color(0x00000000)],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: glowR));
      canvas.drawCircle(Offset(cx, cy), glowR, glowPaint);
    }

    final cosY = math.cos(rotY), sinY = math.sin(rotY);
    final cosX = math.cos(rotX), sinX = math.sin(rotX);

    final projected = <MapEntry<_HeartParticle, _Proj>>[];
    for (final p in particles) {
      final rx = p.x * cosY - p.z * sinY;
      var rz = p.x * sinY + p.z * cosY;
      final ry = p.y * cosX - rz * sinX;
      rz = p.y * sinX + rz * cosX;
      final perspective = 480 / (480 + rz);
      final sx = cx + rx * baseScale * perspective;
      final sy = cy + ry * baseScale * perspective;
      projected.add(MapEntry(p, _Proj(sx, sy, perspective, rz)));
    }
    projected.sort((a, b) => a.value.rz.compareTo(b.value.rz));

    for (final entry in projected) {
      final p = entry.key;
      final proj = entry.value;
      final onEdge = p.rScale.clamp(0.0, 1.0);
      final nearBoost = math.max(0, proj.scale - 0.8) * 0.8;
      final alpha = (0.28 + onEdge * 0.55 + nearBoost).clamp(0.0, 1.0);
      final hue = 344 + (1 - onEdge) * 8;
      // Clair et rosé (60-70%) pour se détacher d'un fond sombre ; sur un
      // fond clair la même teinte s'y fond, donc nettement plus sombre et
      // saturé ici (25-33%) pour rester lisible (constaté en réel).
      final lightness = isDark ? (60 + (1 - onEdge) * 10) / 100 : (33 - (1 - onEdge) * 8) / 100;
      final alphaFloor = isDark ? alpha : alpha.clamp(0.55, 1.0);

      final color = p.word == '♥'
          ? HSLColor.fromAHSL(alphaFloor, 348, 0.88, isDark ? 0.66 : 0.42).toColor()
          : HSLColor.fromAHSL(alphaFloor, hue, 0.82, lightness).toColor();

      final tp = TextPainter(
        text: TextSpan(
          text: p.word,
          style: TextStyle(fontSize: p.fontSize * proj.scale, fontFamily: fontFamily, color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(proj.x - tp.width / 2, proj.y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _HeartPainter oldDelegate) =>
      oldDelegate.rotY != rotY || oldDelegate.rotX != rotX || oldDelegate.particles != particles;
}
