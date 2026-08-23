import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Second cadeau généré en direct, complémentaire de [QuantumLoveHeart] :
/// ici le cœur est fixe (pas de rotation 3D) et se dessine progressivement,
/// trait par trait, comme si une main le traçait au crayon. Boucle en
/// continu (retrace → tient → s'efface → retrace) pour rester vivant dans
/// une vignette ou un carnet de bord, sans jamais rester figé sur un état
/// intermédiaire.
class SketchedLoveHeart extends StatefulWidget {
  final double size;

  const SketchedLoveHeart({super.key, this.size = 260});

  @override
  State<SketchedLoveHeart> createState() => _SketchedLoveHeartState();
}

class _SketchedLoveHeartState extends State<SketchedLoveHeart>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _elapsed = 0;

  // Durées du cycle : tracé -> pause (signature visible) -> effacement.
  static const double _drawSeconds = 3.2;
  static const double _holdSeconds = 2.0;
  static const double _fadeSeconds = 0.8;
  static const double _cycleSeconds = _drawSeconds + _holdSeconds + _fadeSeconds;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    // Démarrer le chrono seulement après la première image affichée à
    // l'écran, pas dès initState : sinon le temps passé pendant le
    // montage/la transition d'ouverture (avant que l'utilisateur ne voie
    // réellement le widget) s'accumulait déjà, et le tracé apparaissait en
    // cours de route au lieu de partir de zéro à l'ouverture du cadeau.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ticker.start();
    });
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    setState(() {
      _elapsed = (_elapsed + dt) % _cycleSeconds;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _elapsed;

    // Tracé : progression 0..1 adoucie (le crayon accélère puis ralentit),
    // figée à 1 dès que le contour est terminé.
    final drawProgress = t < _drawSeconds
        ? Curves.easeInOut.transform((t / _drawSeconds).clamp(0.0, 1.0))
        : 1.0;

    // Effacement global en toute fin de cycle, pour repartir de zéro sur
    // un cœur invisible plutôt qu'un jump-cut brutal.
    final fadeStart = _drawSeconds + _holdSeconds;
    final overallOpacity = t < fadeStart
        ? 1.0
        : 1.0 - ((t - fadeStart) / _fadeSeconds).clamp(0.0, 1.0);

    return Opacity(
      opacity: overallOpacity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: _SketchedHeartPainter(drawProgress: drawProgress),
            ),
          ),
        ],
      ),
    );
  }
}

class _SketchedHeartPainter extends CustomPainter {
  final double drawProgress;

  _SketchedHeartPainter({required this.drawProgress});

  static Offset _heartPoint(double u, double scale) {
    final x = 16 * pow(sin(u), 3);
    // Même inversion de signe que QuantumLoveHeart : la pointe du cœur
    // doit se retrouver en bas du canvas (Y croissant vers le bas).
    final y = -(13 * cos(u) - 5 * cos(2 * u) - 2 * cos(3 * u) - cos(4 * u));
    return Offset(x.toDouble() * scale, y.toDouble() * scale);
  }

  // Inclinaison fixe vers la gauche du cœur "de base" — c'est sur cette
  // même base inclinée que les repasses suivantes sont dessinées, pour
  // qu'elles restent alignées entre elles plutôt que chacune tournée
  // différemment.
  static const double _tiltAngle = -0.34; // ~19.5°

  // Décalages entre les passes, en fraction de la largeur du widget (pas
  // en pixels fixes) — sinon l'écart devient invisible sur un grand cœur
  // et disproportionné sur une petite vignette. Nettement plus marqués
  // que la première version pour bien distinguer les repasses du tracé
  // principal (0,0), plutôt qu'un simple épaississement collé dessus.
  static const List<Offset> _passOffsetFractions = [
    Offset(0, 0),
    Offset(0.055, 0.03),
    Offset(-0.045, 0.05),
  ];

  // Le cœur est remonté et légèrement réduit par rapport au centre du
  // widget, pour dégager de la place sous sa pointe : c'est là que
  // convergent les 3 passes (voir _passOffsetFractions), et le prénom doit
  // pouvoir s'afficher en dessous sans jamais chevaucher ce fouillis.
  static const double _heartCenterYFraction = -0.09;
  static const double _heartScaleDivisor = 48;

  Offset _heartCenter(Size size) =>
      Offset(size.width / 2, size.height / 2 + size.height * _heartCenterYFraction);

  Path _buildHeartPath(Size size, Offset jitterFraction) {
    final jitter = Offset(jitterFraction.dx * size.width, jitterFraction.dy * size.width);
    final center = _heartCenter(size) + jitter;
    final scale = size.width / _heartScaleDivisor;
    const steps = 120;
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final u = (i / steps) * 2 * pi;
      final p = center + _heartPoint(u, scale);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = _heartCenter(size);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(_tiltAngle);
    canvas.translate(-center.dx, -center.dy);

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    // Épaisseur divisée par 2 par rapport à la première version.
    final baseStrokeWidth = size.width * 0.009;

    for (var i = 0; i < _passOffsetFractions.length; i++) {
      // Chaque passe se dessine dans sa propre tranche de temps, l'une
      // après l'autre, plutôt que toutes en même temps.
      final windowStart = i / _passOffsetFractions.length;
      final windowEnd = (i + 1) / _passOffsetFractions.length;
      final passProgress = ((drawProgress - windowStart) / (windowEnd - windowStart))
          .clamp(0.0, 1.0);
      if (passProgress <= 0) continue;

      final path = _buildHeartPath(size, _passOffsetFractions[i]);
      final metrics = path.computeMetrics().toList();
      if (metrics.isEmpty) continue;
      final metric = metrics.first;
      final visiblePath = metric.extractPath(0, metric.length * passProgress);

      // Les repasses (i > 0) sont plus fines et plus discrètes que le
      // tracé principal, comme un vrai coup de crayon de renfort — un
      // dégradé (shader) ignore l'opacité posée sur `color`, donc seul le
      // tracé principal porte le dégradé ; les repasses utilisent une
      // teinte unie semi-transparente.
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = i == 0 ? baseStrokeWidth : baseStrokeWidth * 0.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (i == 0) {
        strokePaint.shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          const [Color(0xFFFF9A52), Color(0xFFB5182B)],
        );
      } else {
        strokePaint.color = const Color(0xFFFF9A52).withValues(alpha: 0.55);
      }
      canvas.drawPath(visiblePath, strokePaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SketchedHeartPainter oldDelegate) =>
      oldDelegate.drawProgress != drawProgress;
}
