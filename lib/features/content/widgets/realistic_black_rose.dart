import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Quatrième cadeau généré en direct : une rose noire réellement
/// positionnée en 3D (chaque pétale a une vraie position x/y/z autour d'un
/// bouton, pas un aplat 2D écrasé comme [EternalRose]) — l'utilisateur fait
/// glisser le doigt pour la faire pivoter et regarder la face de son choix,
/// avec un tri par profondeur et un éclairage par pétale pour un rendu
/// aussi réaliste que possible en vectoriel.
class RealisticBlackRose extends StatefulWidget {
  final double size;

  /// false pour une vignette (boutique) : pas de GestureDetector — sinon le
  /// glissement entrerait en conflit avec le défilement de la grille. La
  /// rotation reste automatique et continue dans ce cas.
  final bool interactive;

  const RealisticBlackRose({super.key, this.size = 280, this.interactive = true});

  @override
  State<RealisticBlackRose> createState() => _RealisticBlackRoseState();
}

class _RealisticBlackRoseState extends State<RealisticBlackRose>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  double _rotY = -0.6;
  double _rotX = -0.15;
  double _idleSince = 0;
  double _time = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ticker.start();
    });
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    setState(() {
      _time += dt;
      // Rotation automatique douce — reprend après un temps d'inactivité
      // si l'utilisateur peut interagir, ou tourne en continu sinon
      // (vignette de boutique).
      if (!widget.interactive || _time - _idleSince > 1.2) {
        _rotY += dt * 0.35;
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _rotY += details.delta.dx * 0.012;
      _rotX = (_rotX - details.delta.dy * 0.012).clamp(-0.9, 0.9);
      _idleSince = _time;
    });
  }

  @override
  Widget build(BuildContext context) {
    final painter = CustomPaint(
      size: Size.square(widget.size),
      painter: _RosePainter3D(rotX: _rotX, rotY: _rotY),
    );
    final rose = RepaintBoundary(child: painter);
    if (!widget.interactive) return rose;
    return GestureDetector(
      onPanUpdate: _onPanUpdate,
      child: rose,
    );
  }
}

typedef _Vec3 = ({double x, double y, double z});

_Vec3 _vAdd(_Vec3 a, _Vec3 b) => (x: a.x + b.x, y: a.y + b.y, z: a.z + b.z);
_Vec3 _vScale(_Vec3 a, double s) => (x: a.x * s, y: a.y * s, z: a.z * s);
_Vec3 _vCross(_Vec3 a, _Vec3 b) => (
      x: a.y * b.z - a.z * b.y,
      y: a.z * b.x - a.x * b.z,
      z: a.x * b.y - a.y * b.x,
    );
double _vDot(_Vec3 a, _Vec3 b) => a.x * b.x + a.y * b.y + a.z * b.z;
_Vec3 _vNorm(_Vec3 a) {
  final len = sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
  if (len < 1e-6) return (x: 0, y: 0, z: 0);
  return (x: a.x / len, y: a.y / len, z: a.z / len);
}

_Vec3 _rotate3d(_Vec3 p, double ax, double ay) {
  final cosAx = cos(ax), sinAx = sin(ax);
  final y1 = p.y * cosAx - p.z * sinAx;
  final z1 = p.y * sinAx + p.z * cosAx;
  final cosAy = cos(ay), sinAy = sin(ay);
  final x2 = p.x * cosAy + z1 * sinAy;
  final z2 = -p.x * sinAy + z1 * cosAy;
  return (x: x2, y: y1, z: z2);
}

class _RoseLayer3D {
  final int petalCount;
  final double tilt; // 0 = pointe vers le haut (bouton fermé), ~1.4 = grand ouvert
  final double baseRadius;
  final double length;
  final double width;
  final double curl;
  final double angleOffset;
  final double lightBoost;

  const _RoseLayer3D({
    required this.petalCount,
    required this.tilt,
    required this.baseRadius,
    required this.length,
    required this.width,
    required this.curl,
    required this.angleOffset,
    required this.lightBoost,
  });
}

class _Petal3D {
  final List<_Vec3> outline;
  final _Vec3 normal;
  final double lightBoost;
  const _Petal3D({required this.outline, required this.normal, required this.lightBoost});
}

class _RosePainter3D extends CustomPainter {
  final double rotX;
  final double rotY;

  _RosePainter3D({required this.rotX, required this.rotY});

  static const _lightDir = (x: 0.35, y: -0.65, z: -0.68);

  static const _layers = [
    _RoseLayer3D(
      petalCount: 5,
      tilt: 0.18,
      baseRadius: 3,
      length: 15,
      width: 8,
      curl: 2,
      angleOffset: 0,
      lightBoost: -0.05,
    ),
    _RoseLayer3D(
      petalCount: 6,
      tilt: 0.55,
      baseRadius: 5,
      length: 21,
      width: 12,
      curl: 4,
      angleOffset: 0.5,
      lightBoost: 0,
    ),
    _RoseLayer3D(
      petalCount: 7,
      tilt: 0.95,
      baseRadius: 7,
      length: 26,
      width: 15,
      curl: 7,
      angleOffset: 1.0,
      lightBoost: 0.04,
    ),
    _RoseLayer3D(
      petalCount: 8,
      tilt: 1.3,
      baseRadius: 9,
      length: 30,
      width: 17,
      curl: 10,
      angleOffset: 1.6,
      lightBoost: 0.08,
    ),
    _RoseLayer3D(
      petalCount: 9,
      tilt: 1.55,
      baseRadius: 10,
      length: 33,
      width: 18,
      curl: 13,
      angleOffset: 2.2,
      lightBoost: 0.1,
    ),
  ];

  // Points d'un pétale arrondi dans son propre repère 2D (largeur, longueur
  // de la base 0 à la pointe) — même profil "goutte" que les autres
  // cadeaux, échantillonné en points discrets plutôt qu'un Path à courbes,
  // pour pouvoir transformer chaque sommet individuellement en 3D.
  static List<Offset> _petalOutline2D(double length, double width) {
    const steps = 10;
    final right = <Offset>[];
    for (var i = 0; i <= steps; i++) {
      final v = i / steps;
      final w = width * pow(sin(pi * v), 0.75) * (1 - v * 0.15);
      right.add(Offset(w, v * length));
    }
    final left = <Offset>[
      for (var i = steps; i >= 0; i--) Offset(-right[i].dx, right[i].dy),
    ];
    return [...right, ...left];
  }

  List<_Petal3D> _buildPetals(_Vec3 budCenter) {
    final petals = <_Petal3D>[];
    for (final layer in _layers) {
      final outline2D = _petalOutline2D(layer.length, layer.width);
      for (var p = 0; p < layer.petalCount; p++) {
        final theta = (2 * pi * p / layer.petalCount) + layer.angleOffset;
        final outward = _vNorm((
          x: sin(layer.tilt) * cos(theta),
          y: -cos(layer.tilt),
          z: sin(layer.tilt) * sin(theta),
        ));
        var tangent = _vCross(outward, (x: 0, y: 1, z: 0));
        if (tangent.x.abs() < 1e-4 && tangent.y.abs() < 1e-4 && tangent.z.abs() < 1e-4) {
          tangent = (x: 1, y: 0, z: 0);
        }
        tangent = _vNorm(tangent);
        final petalNormal = _vNorm(_vCross(tangent, outward));

        final anchor = _vAdd(budCenter, _vScale(outward, layer.baseRadius));

        final outline = outline2D.map((pt) {
          final v = pt.dy / layer.length;
          final curlAmount = layer.curl * v * v;
          var world = _vAdd(anchor, _vScale(tangent, pt.dx));
          world = _vAdd(world, _vScale(outward, pt.dy));
          world = _vAdd(world, _vScale(petalNormal, curlAmount));
          return world;
        }).toList();

        petals.add(_Petal3D(outline: outline, normal: petalNormal, lightBoost: layer.lightBoost));
      }
    }
    return petals;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scaleUnit = size.width / 68;
    final cameraDistance = 240.0;
    final screenCenter = Offset(size.width / 2, size.height * 0.4);

    ({double x, double y, double scale}) project(_Vec3 p) {
      final rotated = _rotate3d(p, rotX, rotY);
      final s = cameraDistance / (cameraDistance + rotated.z);
      return (x: rotated.x * s, y: rotated.y * s, scale: s);
    }

    const budCenter = (x: 0.0, y: 0.0, z: 0.0);
    final petals = _buildPetals(budCenter);

    // Tri peintre : les pétales les plus loin de la caméra (z tourné le
    // plus grand) sont dessinés en premier, pour que les plus proches
    // recouvrent correctement quel que soit l'angle choisi au doigt.
    final withDepth = petals.map((petal) {
      final avgZ = petal.outline
              .map((p) => _rotate3d(p, rotX, rotY).z)
              .reduce((a, b) => a + b) /
          petal.outline.length;
      return (petal: petal, depth: avgZ);
    }).toList()
      ..sort((a, b) => b.depth.compareTo(a.depth));

    _paintStem(canvas, size, project, scaleUnit);

    const darkColor = Color(0xFF140508);
    const litColor = Color(0xFF6E1420);
    const highlightColor = Color(0xFFB6455A);

    for (final entry in withDepth) {
      final petal = entry.petal;
      final rotatedNormal = _rotate3d(petal.normal, rotX, rotY);
      final lightFactor =
          (_vDot(rotatedNormal, _lightDir) * 0.5 + 0.5 + petal.lightBoost).clamp(0.0, 1.0);

      final path = Path();
      final projected = petal.outline.map((p) {
        final proj = project(_vScale(p, scaleUnit));
        return screenCenter + Offset(proj.x, proj.y);
      }).toList();
      path.moveTo(projected.first.dx, projected.first.dy);
      for (final pt in projected.skip(1)) {
        path.lineTo(pt.dx, pt.dy);
      }
      path.close();

      final fillColor = lightFactor > 0.72
          ? Color.lerp(litColor, highlightColor, (lightFactor - 0.72) / 0.28)!
          : Color.lerp(darkColor, litColor, (lightFactor / 0.72).clamp(0.0, 1.0))!;

      canvas.drawPath(path, Paint()..color = fillColor);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = Colors.black.withValues(alpha: 0.35),
      );
    }
  }

  void _paintStem(
    Canvas canvas,
    Size size,
    ({double x, double y, double scale}) Function(_Vec3) project,
    double scaleUnit,
  ) {
    final segments = <_Vec3>[
      (x: 0, y: 12, z: 0),
      (x: -2, y: 30, z: 2),
      (x: 2, y: 48, z: -1),
      (x: -1, y: 64, z: 3),
    ];
    final screenCenter = Offset(size.width / 2, size.height * 0.4);
    final points = segments.map((p) {
      final proj = project(_vScale(p, scaleUnit));
      return screenCenter + Offset(proj.x, proj.y);
    }).toList();

    final stemPath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final pt in points.skip(1)) {
      stemPath.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(
      stemPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.02
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF1C2A18),
    );

    // Feuilles : deux petits pétales verts sombres accrochés à mi-tige.
    for (final side in [-1.0, 1.0]) {
      final leafBase = segments[2];
      final leafOutline = _petalOutline2D(16, 8).map((pt) {
        final local = (x: side * pt.dx, y: pt.dy * 0.9, z: side * 4.0);
        return _vAdd(leafBase, local);
      }).toList();
      final projected = leafOutline.map((p) {
        final proj = project(_vScale(p, scaleUnit));
        return screenCenter + Offset(proj.x, proj.y);
      }).toList();
      final leafPath = Path()..moveTo(projected.first.dx, projected.first.dy);
      for (final pt in projected.skip(1)) {
        leafPath.lineTo(pt.dx, pt.dy);
      }
      leafPath.close();
      canvas.drawPath(leafPath, Paint()..color = const Color(0xFF223B1E));
    }
  }

  @override
  bool shouldRepaint(covariant _RosePainter3D oldDelegate) =>
      oldDelegate.rotX != rotX || oldDelegate.rotY != rotY;
}
