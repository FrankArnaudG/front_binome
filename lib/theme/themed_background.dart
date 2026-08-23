import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme_scope.dart';

/// Fond d'écran unifié pour tous les écrans qui suivent le thème
/// personnel : affiche le [ThemePalette.sceneBackground] illustré s'il y
/// en a un (dégradé + étoiles/montagnes/brume), sinon retombe sur le
/// dégradé plat classique — pour que chaque thème s'applique de la même
/// façon partout, pas juste sur un écran choisi au hasard.
class ThemedBackground extends StatelessWidget {
  final Widget child;

  const ThemedBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final scene = theme.sceneBackground;

    // Edge-to-edge (voir main.dart) laisse le contenu s'étendre derrière la
    // barre de navigation système, mais celle-ci reste dessinée par-dessus
    // : sans ceci, ses icônes restent dans leur luminosité par défaut,
    // illisibles sur un thème sombre.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: theme.statusBarOverlayStyle.copyWith(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: theme.isDark ? Brightness.light : Brightness.dark,
      ),
      child: Stack(
        // Sans ça (fit par défaut = loose), le Stack se dimensionne sur son
        // enfant non positionné — ici un contenu défilant plus court que
        // l'écran (voir ProfileCompletionScreen) — et Positioned.fill ne
        // couvre alors que cette hauteur réduite, laissant apparaître le
        // fond blanc par défaut du Scaffold en dessous.
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: scene != null ? scene(context) : DecoratedBox(decoration: BoxDecoration(gradient: theme.backgroundGradient)),
          ),
          child,
        ],
      ),
    );
  }
}
