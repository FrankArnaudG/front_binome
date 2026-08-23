import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

/// Composition de secours pour le haut de l'écran de connexion, tant que
/// l'illustration "personnages" générée n'est pas encore fournie.
class LoginHeroFallback extends StatelessWidget {
  const LoginHeroFallback({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.navyDeep, AppColors.navy],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 40,
            left: 24,
            child: Icon(Icons.favorite_rounded, color: AppColors.primary.withValues(alpha: 0.25), size: 22),
          ),
          Positioned(
            bottom: 60,
            right: 32,
            child: Icon(Icons.favorite_rounded, color: AppColors.secondary.withValues(alpha: 0.3), size: 16),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _personBubble(AppColors.primary),
              const SizedBox(width: 8),
              const Icon(Icons.favorite_rounded, color: Colors.white, size: 28),
              const SizedBox(width: 8),
              _personBubble(AppColors.secondary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _personBubble(Color color) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Icon(Icons.person_rounded, color: color, size: 34),
    );
  }
}
