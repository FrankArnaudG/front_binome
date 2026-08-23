import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Micro-interaction locale pour "Faire battre son cœur" : vibration
/// haptique en deux temps (façon battement) + une petite explosion de
/// cœurs qui s'envolent depuis le widget enveloppé, joue instantanément au
/// tap — indépendamment du succès de l'appel réseau, qui peut prendre le
/// temps qu'il veut en arrière-plan.
class HeartBurst extends StatefulWidget {
  final Widget child;

  const HeartBurst({super.key, required this.child});

  @override
  State<HeartBurst> createState() => HeartBurstState();
}

class HeartBurstState extends State<HeartBurst> with TickerProviderStateMixin {
  final List<AnimationController> _bursts = [];

  /// À appeler au moment du tap — joue la vibration et lance une explosion
  /// de cœurs qui se retire toute seule une fois terminée.
  void trigger() {
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 130), () {
      if (mounted) HapticFeedback.lightImpact();
    });

    final controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
    setState(() => _bursts.add(controller));
    controller.forward().whenComplete(() {
      if (mounted) setState(() => _bursts.remove(controller));
      controller.dispose();
    });
  }

  @override
  void dispose() {
    for (final c in _bursts) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // `Positioned.fill` pour que le child reçoive les mêmes contraintes
    // strictes que s'il n'était pas enveloppé dans un Stack (sinon les
    // enfants non positionnés d'un Stack ne reçoivent que des contraintes
    // lâches et la tuile rétrécirait à la taille de son contenu).
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: widget.child),
        for (final controller in _bursts)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(child: _BurstHearts(controller: controller)),
            ),
          ),
      ],
    );
  }
}

class _BurstHearts extends StatelessWidget {
  static const _count = 7;
  final AnimationController controller;

  const _BurstHearts({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: List.generate(_count, (i) {
            final angle = (2 * math.pi / _count) * i - math.pi / 2;
            // Décalage de la progression par cœur pour un envol plus organique.
            final t = (controller.value - (i % 3) * 0.05).clamp(0.0, 1.0);
            final ease = Curves.easeOut.transform(t);
            final distance = 38.0 * ease;
            final dx = math.cos(angle) * distance;
            final dy = math.sin(angle) * distance;
            final scale = (1 - (t - 0.6).clamp(0.0, 0.4) / 0.4) * (0.6 + 0.5 * Curves.easeOut.transform((t * 2).clamp(0.0, 1.0)));
            final opacity = 1 - Curves.easeIn.transform(((t - 0.5).clamp(0.0, 0.5)) / 0.5);

            return Transform.translate(
              offset: Offset(dx, dy),
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: scale.clamp(0.0, 1.4),
                  child: Icon(Icons.favorite_rounded, color: [Colors.pinkAccent, Colors.redAccent][i % 2], size: 16),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
