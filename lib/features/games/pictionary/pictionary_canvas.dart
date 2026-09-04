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

  const PictionaryCanvas({
    super.key,
    required this.strokes,
    required this.interactive,
    this.onStrokeComplete,
  });

  @override
  State<PictionaryCanvas> createState() => _PictionaryCanvasState();
}

const _kStrokeColor = '#2F6FED';
const _kStrokeWidth = 4.0;

class _PictionaryCanvasState extends State<PictionaryCanvas> {
  final List<Offset> _liveNormalizedPoints = [];
  Size _canvasSize = Size.zero;

  void _onPanStart(DragStartDetails details) {
    if (!widget.interactive || _canvasSize == Size.zero) return;
    setState(() {
      _liveNormalizedPoints
        ..clear()
        ..add(Offset(details.localPosition.dx / _canvasSize.width, details.localPosition.dy / _canvasSize.height));
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!widget.interactive || _canvasSize == Size.zero) return;
    setState(() {
      _liveNormalizedPoints.add(Offset(details.localPosition.dx / _canvasSize.width, details.localPosition.dy / _canvasSize.height));
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (!widget.interactive || _liveNormalizedPoints.length < 2) {
      setState(() => _liveNormalizedPoints.clear());
      return;
    }
    final stroke = PictionaryStroke(
      points: _liveNormalizedPoints.map((p) => [p.dx, p.dy]).toList(),
      color: _kStrokeColor,
      width: _kStrokeWidth,
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
            painter: _PictionaryPainter(strokes: widget.strokes, liveNormalizedPoints: _liveNormalizedPoints),
          ),
        );
      },
    );
  }
}

class _PictionaryPainter extends CustomPainter {
  final List<PictionaryStroke> strokes;
  final List<Offset> liveNormalizedPoints;

  _PictionaryPainter({required this.strokes, required this.liveNormalizedPoints});

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
      _paintStroke(canvas, size, liveNormalizedPoints.map((p) => [p.dx, p.dy]).toList(), const Color(0xFF2F6FED), _kStrokeWidth);
    }
  }

  @override
  bool shouldRepaint(covariant _PictionaryPainter oldDelegate) =>
      oldDelegate.strokes.length != strokes.length || oldDelegate.liveNormalizedPoints != liveNormalizedPoints;
}
