import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Bouton de navigation circulaire (suivant/retour) utilisé sur les écrans
/// immersifs (onboarding, pairing) à la place d'un bouton pleine largeur.
class CircleNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;
  final Color? outlineColor;

  const CircleNavButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.filled = true,
    this.outlineColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? AppColors.primary : Colors.transparent,
      shape: CircleBorder(
        side: filled ? BorderSide.none : BorderSide(color: outlineColor ?? Colors.white, width: 1.5),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(icon, color: filled ? Colors.white : (outlineColor ?? Colors.white), size: 22),
        ),
      ),
    );
  }
}
