import 'package:flutter/material.dart';

/// Trois points qui rebondissent l'un après l'autre (bas → haut → bas) pour
/// signaler une attente — même animation partout où l'app affiche "en
/// attente de..." (voir EmojiStorySessionScreen, GameCardThreadScreen),
/// plutôt qu'un simple rond qui tourne.
class WaitingDots extends StatefulWidget {
  final Color color;

  const WaitingDots({super.key, required this.color});

  @override
  State<WaitingDots> createState() => _WaitingDotsState();
}

class _WaitingDotsState extends State<WaitingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 10,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (i) {
              final t = (_controller.value - i * 0.2) % 1.0;
              final bounce = t < 0.5 ? t * 2 : (1 - t) * 2;
              return Transform.translate(
                offset: Offset(0, -3 * bounce),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
