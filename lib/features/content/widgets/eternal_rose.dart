import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Troisième cadeau généré en direct, aux côtés de [QuantumLoveHeart] et
/// [SketchedLoveHeart] : une rose vectorielle qui éclot une seule fois puis
/// reste ouverte pour toujours ("Éternelle") avec un léger balancement
/// continu — pas de cycle de fanaison/reprise comme les cœurs, une rose ne
/// devrait pas se refermer.
class EternalRose extends StatefulWidget {
  final double size;

  const EternalRose({super.key, this.size = 260});

  @override
  State<EternalRose> createState() => _EternalRoseState();
}

class _EternalRoseState extends State<EternalRose> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _elapsed = 0;

  static const double _bloomSeconds = 2.6;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    // Même correctif que SketchedLoveHeart : ne démarrer le chrono
    // qu'après la première image réellement affichée, pour ne jamais
    // montrer l'éclosion déjà en cours à l'ouverture du cadeau.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ticker.start();
    });
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    setState(() => _elapsed += dt);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bloomProgress = Curves.easeOutCubic.transform(
      (_elapsed / _bloomSeconds).clamp(0.0, 1.0),
    );
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _RosePainter(bloomProgress: bloomProgress, time: _elapsed),
      ),
    );
  }
}

class _RoseLayer {
  final int petalCount;
  final double radiusFraction;
  final double lengthFraction;
  final double widthFraction;
  final double angleOffset;
  final double hueShift;
  final double valueBoost;
  final double bloomStart;

  const _RoseLayer({
    required this.petalCount,
    required this.radiusFraction,
    required this.lengthFraction,
    required this.widthFraction,
    required this.angleOffset,
    required this.hueShift,
    required this.valueBoost,
    required this.bloomStart,
  });
}

class _RosePainter extends CustomPainter {
  final double bloomProgress;
  final double time;

  _RosePainter({required this.bloomProgress, required this.time});

  // Du bouton central (serré, sombre, en spirale) vers l'extérieur (large,
  // ouvert, plus clair) — 6 couches à rayon très resserré par rapport à la
  // longueur des pétales, pour un recouvrement dense façon vraie rose
  // plutôt que des pointes espacées façon étoile/fleur des champs.
  static const _layers = [
    _RoseLayer(
      petalCount: 5,
      radiusFraction: 0.008,
      lengthFraction: 0.10,
      widthFraction: 0.075,
      angleOffset: 0,
      hueShift: -10,
      valueBoost: 0.0,
      bloomStart: 0.0,
    ),
    _RoseLayer(
      petalCount: 6,
      radiusFraction: 0.03,
      lengthFraction: 0.15,
      widthFraction: 0.11,
      angleOffset: 0.5,
      hueShift: -6,
      valueBoost: 0.04,
      bloomStart: 0.12,
    ),
    _RoseLayer(
      petalCount: 7,
      radiusFraction: 0.055,
      lengthFraction: 0.205,
      widthFraction: 0.15,
      angleOffset: 1.0,
      hueShift: -2,
      valueBoost: 0.08,
      bloomStart: 0.26,
    ),
    _RoseLayer(
      petalCount: 8,
      radiusFraction: 0.085,
      lengthFraction: 0.26,
      widthFraction: 0.185,
      angleOffset: 1.5,
      hueShift: 3,
      valueBoost: 0.12,
      bloomStart: 0.42,
    ),
    _RoseLayer(
      petalCount: 9,
      radiusFraction: 0.115,
      lengthFraction: 0.315,
      widthFraction: 0.22,
      angleOffset: 2.0,
      hueShift: 7,
      valueBoost: 0.16,
      bloomStart: 0.58,
    ),
    _RoseLayer(
      petalCount: 10,
      radiusFraction: 0.145,
      lengthFraction: 0.365,
      widthFraction: 0.25,
      angleOffset: 2.5,
      hueShift: 11,
      valueBoost: 0.2,
      bloomStart: 0.74,
    ),
  ];

  static const double _layerBloomSpan = 0.4;

  // Compression verticale du placement des pétales — vue "de face"/légère
  // plongée plutôt que strictement de dessus (voir usage plus bas).
  static const double _verticalSquash = 0.7;

  // Pétale arrondi (pas de pointe franche) : deux courbes cubiques qui se
  // rejoignent tangentiellement en haut plutôt qu'un angle vif — un cœur
  // qui pointe est voulu, une rose qui pointe ressemble à une étoile.
  Path _petalPath(double length, double width) {
    final path = Path();
    path.moveTo(0, 0);
    path.cubicTo(width * 0.95, -length * 0.08, width, -length * 0.72, 0, -length);
    path.cubicTo(-width, -length * 0.72, -width * 0.95, -length * 0.08, 0, 0);
    path.close();
    return path;
  }

  void _paintStem(Canvas canvas, Size size, double flowerBaseY) {
    final stemPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.014
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF3E7A3F);
    final stemPath = Path()
      ..moveTo(size.width / 2, flowerBaseY)
      ..cubicTo(
        size.width * 0.46,
        size.height * 0.72,
        size.width * 0.54,
        size.height * 0.85,
        size.width * 0.5,
        size.height * 0.97,
      );
    canvas.drawPath(stemPath, stemPaint);

    final leafPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF4E9350);
    for (final side in [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(size.width * 0.5, size.height * 0.82);
      canvas.rotate(side * 0.6);
      canvas.drawPath(_petalPath(size.width * 0.16, size.width * 0.07), leafPaint);
      canvas.restore();
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.42);

    if (bloomProgress > 0.05) {
      final stemOpacity = ((bloomProgress - 0.05) / 0.2).clamp(0.0, 1.0);
      canvas.saveLayer(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.white.withValues(alpha: stemOpacity),
      );
      _paintStem(canvas, size, center.dy + size.width * 0.05);
      canvas.restore();
    }

    // Léger balancement continu une fois éclose — une rose vivante, pas une
    // image figée.
    final sway = bloomProgress >= 1.0 ? sin(time * 0.7) * 0.045 : 0.0;

    // Les couches extérieures (grandes, ouvertes) sont peintes D'ABORD,
    // les couches intérieures (petit bouton en spirale) EN DERNIER —
    // sinon les grands pétales du dessus recouvriraient et cacheraient le
    // cœur en spirale qui fait justement reconnaître une rose.
    for (final layer in _layers.reversed) {
      final layerLocal = ((bloomProgress - layer.bloomStart) / _layerBloomSpan).clamp(0.0, 1.0);
      if (layerLocal <= 0) continue;

      for (var p = 0; p < layer.petalCount; p++) {
        // Petit décalage par pétale pour une ouverture en spirale plutôt
        // qu'une couche entière qui surgit d'un coup.
        final petalDelay = (p / layer.petalCount) * 0.15;
        final petalLocal = ((layerLocal - petalDelay) / (1 - petalDelay)).clamp(0.0, 1.0);
        if (petalLocal <= 0) continue;
        final petalScale = Curves.easeOutBack.transform(petalLocal);

        final angle = (2 * pi * p / layer.petalCount) + layer.angleOffset + sway;
        final radius = size.width * layer.radiusFraction;
        final length = size.width * layer.lengthFraction;
        final width = size.width * layer.widthFraction;

        canvas.save();
        // Placement écrasé verticalement (ellipse plutôt que cercle) : sans
        // ça la rose se lisait comme vue de dessus (mandala à plat) au lieu
        // d'être présentée de face, la tige en bas ancrant le "haut".
        canvas.translate(
          center.dx + cos(angle) * radius,
          center.dy + sin(angle) * radius * _verticalSquash,
        );
        // Chaque pétale pointe vers l'extérieur, légèrement basculé pour un
        // effet de courbure naturelle plutôt que purement radial.
        canvas.rotate(angle + pi / 2 + 0.22);
        canvas.scale(petalScale);

        final hue = (350 + layer.hueShift) % 360;
        final baseColor =
            HSVColor.fromAHSV(1, hue, 0.88, (0.28 + layer.valueBoost).clamp(0.0, 0.85)).toColor();
        final tipColor =
            HSVColor.fromAHSV(1, hue, 0.7, (0.55 + layer.valueBoost).clamp(0.0, 0.95)).toColor();
        final petalPath = _petalPath(length, width);
        final petalPaint = Paint()
          ..style = PaintingStyle.fill
          ..shader = ui.Gradient.linear(
            const Offset(0, 0),
            Offset(0, -length),
            [baseColor, tipColor],
          );
        canvas.drawPath(petalPath, petalPaint);

        // Fine ombre le long du pli central — donne un semblant de volume
        // sans avoir à modéliser une vraie courbure 3D du pétale.
        final creasePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 0.06
          ..strokeCap = StrokeCap.round
          ..color = Colors.black.withValues(alpha: 0.12);
        canvas.drawLine(const Offset(0, 0), Offset(0, -length * 0.85), creasePaint);

        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RosePainter oldDelegate) =>
      oldDelegate.bloomProgress != bloomProgress || oldDelegate.time != time;
}
