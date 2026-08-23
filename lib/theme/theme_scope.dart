import 'package:flutter/widgets.dart';

import 'theme_controller.dart';
import 'theme_palette.dart';

/// Rend le thème personnel choisi disponible à toute l'app — monté une
/// seule fois dans `main.dart`, autour du Navigator entier (comme
/// [BoxScope]), pas seulement autour de [MainTabScreen] : un écran poussé
/// (Boutique, Poèmes-Slides...) peut donc lire [paletteOf] en toute
/// sécurité. Les écrans qui n'ont pas encore été migrés vers ce système
/// gardent simplement leur palette [AppColors] fixe — ils n'ont pas besoin
/// de ce scope pour fonctionner, ils l'ignorent juste.
class ThemeScope extends InheritedNotifier<ThemeController> {
  ThemeScope({super.key, required super.child}) : super(notifier: ThemeController.instance);

  static ThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'ThemeScope.of() appelé sans ThemeScope ancêtre.');
    return scope!.notifier!;
  }

  static ThemePalette paletteOf(BuildContext context) => of(context).current;
}
