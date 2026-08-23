import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

/// Indicateurs de saisie du code PIN (6 points, remplis au fur et à mesure).
class PinDots extends StatelessWidget {
  final int length;
  final int filled;
  final Color color;

  const PinDots({super.key, this.length = 6, required this.filled, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(length, (i) {
        final isFilled = i < filled;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 7),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled ? color : Colors.transparent,
            border: Border.all(color: color.withValues(alpha: isFilled ? 1 : 0.5), width: 1.5),
          ),
        );
      }),
    );
  }
}

/// Variante pour les écrans à fond clair (Paramètres).
class PinDotsOnBlush extends StatelessWidget {
  final int length;
  final int filled;

  const PinDotsOnBlush({super.key, this.length = 6, required this.filled});

  @override
  Widget build(BuildContext context) {
    return PinDots(length: length, filled: filled, color: AppColors.primary);
  }
}
