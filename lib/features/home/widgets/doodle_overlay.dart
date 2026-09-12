import 'package:flutter/material.dart';

import '../../../core/app_router.dart';
import '../../../core/doodle_notifier.dart';
import '../../doodle/doodle_view_screen.dart';

/// Ouvre automatiquement [DoodleViewScreen] en PLEIN ÉCRAN dès qu'un doodle
/// arrive (voir demande utilisateur : "s'affiche en plein écran chez
/// l'autre", pas une petite bulle comme GameInviteOverlay) — ce widget ne
/// dessine rien lui-même, il se contente de pousser l'écran puis efface
/// [DoodleNotifier.pendingDoodle] pour ne pas le repousser deux fois.
class DoodleOverlay extends StatefulWidget {
  const DoodleOverlay({super.key});

  @override
  State<DoodleOverlay> createState() => _DoodleOverlayState();
}

class _DoodleOverlayState extends State<DoodleOverlay> {
  // La route actuellement affichée, s'il y en a une — permet de la
  // REMPLACER plutôt que d'en empiler une nouvelle par-dessus si un
  // deuxième doodle arrive avant que le premier n'ait été fermé (voir
  // demande utilisateur : "ça s'est superposé... il faudra fermer et
  // afficher le nouveau").
  Route<void>? _activeRoute;

  @override
  void initState() {
    super.initState();
    DoodleNotifier.instance.addListener(_onChanged);
    // Rattrape un doodle arrivé pendant que ce widget était démonté — voir
    // AppShell, qui retire tout son Stack (donc ce widget) tant qu'un écran
    // immersif est ouvert (SlideDetailScreen, DoodleHistoryScreen...). Sans
    // ce rattrapage, un doodle reçu pendant ce temps ne déclenchait plus
    // jamais le plein écran automatique, même une fois revenu (voir demande
    // utilisateur : "ça s'affiche plus automatiquement").
    WidgetsBinding.instance.addPostFrameCallback((_) => _onChanged());
  }

  @override
  void dispose() {
    DoodleNotifier.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final doodle = DoodleNotifier.instance.pendingDoodle;
    if (doodle == null) return;

    // Vérifié AVANT d'effacer/marquer quoi que ce soit (voir bug rapporté
    // par l'utilisateur : l'ancien ordre effaçait le dessin en attente même
    // quand le Navigator n'était pas encore prêt — ex. juste après un tap
    // sur la notification, app tout juste relancée — le perdant pour de
    // bon). Si le Navigator n'est pas encore attaché, on retente au frame
    // suivant plutôt que d'abandonner : le dessin reste en attente entre
    // temps, donc rien n'est perdu.
    final navContext = AppRouter.navigatorKey.currentContext;
    if (navContext == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onChanged());
      return;
    }
    final navigator = Navigator.of(navContext);

    // Efface seulement maintenant qu'on est sûr de pouvoir l'afficher : le
    // plein écran qu'on pousse ci-dessous EST l'affichage, pas besoin de le
    // garder en mémoire une fois la navigation lancée (sinon un rebuild
    // ultérieur le repousserait).
    DoodleNotifier.instance.dismissPendingDoodle();
    DoodleNotifier.instance.markShown(doodle.id);

    // Route NON opaque (voir doodleViewRoute) — l'écran déjà affiché
    // derrière (Carnet de bord, Duo...) continue d'être peint, on voit
    // vraiment à travers. Pas de viewerUserId ici : une arrivée en direct
    // est TOUJOURS un mot reçu, jamais le sien propre.
    final route = doodleViewRoute(doodle);

    final previousRoute = _activeRoute;
    _activeRoute = route;
    // Comparaison par identité de route (pas juste "y avait-il une route ?")
    // — évite de remettre _activeRoute à null par erreur si CE callback se
    // déclenche après qu'une route plus récente a déjà pris sa place.
    route.popped.then((_) {
      if (_activeRoute == route) _activeRoute = null;
    });

    if (previousRoute != null) {
      // Un doodle est déjà affiché sans avoir été fermé — le remplace au
      // lieu d'en empiler un second par-dessus.
      navigator.pushReplacement(route);
    } else {
      navigator.push(route);
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
