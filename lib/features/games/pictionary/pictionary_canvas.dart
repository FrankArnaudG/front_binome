import 'package:flutter/material.dart';

import '../../../models/pictionary_session.dart';

/// Canvas de dessin — capture un TRAIT COMPLET par geste (voir
/// [onStrokeComplete], appelé une fois le doigt levé, jamais par petits
/// segments intermédiaires) : simplification délibérée par rapport à un
/// streaming point-par-point, qui ajouterait beaucoup de trafic réseau
/// pour un gain de fluidité marginal sur un trait de dessin typique
/// (quelques centaines de ms à 1-2s) — le trait apparaît chez l'autre dès
/// qu'il est terminé, pas au bout des 70 secondes de la manche.
///
/// Les points sont NORMALISÉS (fraction 0..1 de la largeur/hauteur du
/// canvas) avant d'être transmis — les deux téléphones n'ont pas
/// forcément le même écran, voir [PictionaryStroke].
class PictionaryCanvas extends StatefulWidget {
  final List<PictionaryStroke> strokes;
  final bool interactive;
  final void Function(PictionaryStroke stroke)? onStrokeComplete;
  // Couleur/épaisseur du prochain trait dessiné — par défaut celles du jeu
  // Pictionary (bleu fixe, voir _kStrokeColor), reconfigurables pour un
  // usage hors-jeu (voir DoodleComposeScreen, qui propose un choix de
  // couleurs).
  final String strokeColor;
  final double strokeWidth;
  // Gomme (voir DoodleComposeScreen) — un geste retire les traits touchés
  // au lieu d'en ajouter un nouveau. [eraserRadius] est normalisé (même
  // espace 0..1 que les points d'un trait), converti en pixels ici
  // seulement pour l'indicateur visuel qui suit le doigt.
  final bool eraseMode;
  final double eraserRadius;
  final void Function(Offset normalizedPoint)? onErase;

  const PictionaryCanvas({
    super.key,
    required this.strokes,
    required this.interactive,
    this.onStrokeComplete,
    this.strokeColor = _kStrokeColor,
    this.strokeWidth = _kStrokeWidth,
    this.eraseMode = false,
    this.eraserRadius = 0.03,
    this.onErase,
  });

  @override
  State<PictionaryCanvas> createState() => _PictionaryCanvasState();
}

const _kStrokeColor = '#2F6FED';
const _kStrokeWidth = 4.0;

class _PictionaryCanvasState extends State<PictionaryCanvas> {
  final List<Offset> _liveNormalizedPoints = [];
  Size _canvasSize = Size.zero;
  // Position du doigt en mode gomme (pixels locaux) — juste pour dessiner
  // l'indicateur de zone d'effacement, voir _PictionaryPainter.
  Offset? _eraserPosition;

  Offset _normalize(Offset local) => Offset(local.dx / _canvasSize.width, local.dy / _canvasSize.height);

  void _onPanStart(DragStartDetails details) {
    if (!widget.interactive || _canvasSize == Size.zero) return;
    if (widget.eraseMode) {
      setState(() => _eraserPosition = details.localPosition);
      widget.onErase?.call(_normalize(details.localPosition));
      return;
    }
    setState(() {
      _liveNormalizedPoints
        ..clear()
        ..add(_normalize(details.localPosition));
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!widget.interactive || _canvasSize == Size.zero) return;
    if (widget.eraseMode) {
      setState(() => _eraserPosition = details.localPosition);
      widget.onErase?.call(_normalize(details.localPosition));
      return;
    }
    setState(() {
      _liveNormalizedPoints.add(_normalize(details.localPosition));
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (widget.eraseMode) {
      setState(() => _eraserPosition = null);
      return;
    }
    if (!widget.interactive || _liveNormalizedPoints.length < 2) {
      setState(() => _liveNormalizedPoints.clear());
      return;
    }
    final stroke = PictionaryStroke(
      points: _liveNormalizedPoints.map((p) => [p.dx, p.dy]).toList(),
      color: widget.strokeColor,
      width: widget.strokeWidth,
    );
    setState(() => _liveNormalizedPoints.clear());
    widget.onStrokeComplete?.call(stroke);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: CustomPaint(
            size: _canvasSize,
            painter: _PictionaryPainter(
              strokes: widget.strokes,
              liveNormalizedPoints: _liveNormalizedPoints,
              liveColor: widget.strokeColor,
              liveWidth: widget.strokeWidth,
              eraserPosition: _eraserPosition,
              eraserRadiusPx: widget.eraserRadius * _canvasSize.width,
            ),
          ),
        );
      },
    );
  }
}

class _PictionaryPainter extends CustomPainter {
  final List<PictionaryStroke> strokes;
  final List<Offset> liveNormalizedPoints;
  final String liveColor;
  final double liveWidth;
  final Offset? eraserPosition;
  final double eraserRadiusPx;

  _PictionaryPainter({
    required this.strokes,
    required this.liveNormalizedPoints,
    this.liveColor = _kStrokeColor,
    this.liveWidth = _kStrokeWidth,
    this.eraserPosition,
    this.eraserRadiusPx = 0,
  });

  void _paintStroke(Canvas canvas, Size size, List<List<double>> points, Color color, double width) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first[0] * size.width, points.first[1] * size.height);
    for (final p in points.skip(1)) {
      path.lineTo(p[0] * size.width, p[1] * size.height);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      final color = Color(int.parse(stroke.color.replaceFirst('#', '0xFF')));
      _paintStroke(canvas, size, stroke.points, color, stroke.width);
    }
    if (liveNormalizedPoints.length >= 2) {
      final color = Color(int.parse(liveColor.replaceFirst('#', '0xFF')));
      _paintStroke(canvas, size, liveNormalizedPoints.map((p) => [p.dx, p.dy]).toList(), color, liveWidth);
    }
    if (eraserPosition != null) {
      canvas.drawCircle(
        eraserPosition!,
        eraserRadiusPx,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        eraserPosition!,
        eraserRadiusPx,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PictionaryPainter oldDelegate) =>
      oldDelegate.strokes.length != strokes.length ||
      oldDelegate.liveNormalizedPoints != liveNormalizedPoints ||
      oldDelegate.eraserPosition != eraserPosition;
}
