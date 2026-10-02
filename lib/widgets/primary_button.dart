import 'package:flutter/material.dart';

/// Bouton principal de l'app (pilule, style venant du thème global) avec un
/// état de chargement intégré, pour éviter de dupliquer ce pattern sur
/// chaque écran avec appel API (créer/rejoindre une Box, débloquer un pack,
/// envoyer un cadeau, acheter des tokens...).
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (loading) {
      child = const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
      );
    } else if (icon != null) {
      child = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)],
      );
    } else {
      child = Text(label);
    }

    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      child: child,
    );
  }
}
