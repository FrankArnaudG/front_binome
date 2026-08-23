import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

/// Composition de secours (deux téléphones qui se connectent) tant que
/// l'illustration générée n'est pas fournie.
class BoxHeroFallback extends StatelessWidget {
  const BoxHeroFallback({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.rotate(angle: -0.12, child: _phone(AppColors.primary)),
              const SizedBox(width: 4),
              Transform.rotate(angle: 0.12, child: _phone(AppColors.secondary)),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.navy,
              border: Border.all(color: AppColors.primary, width: 2),
            ),
            child: const Icon(Icons.favorite_rounded, color: AppColors.primary, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _phone(Color color) {
    return Container(
      width: 70,
      height: 130,
      decoration: BoxDecoration(
        color: AppColors.navySurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.person_rounded, color: color, size: 30),
    );
  }
}
