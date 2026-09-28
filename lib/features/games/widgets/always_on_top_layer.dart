import 'package:flutter/material.dart';

/// Affiche [child] par-dessus TOUT, y compris une feuille de score déjà
/// ouverte (`showModalBottomSheet`) — voir demande utilisateur : "le modèle
/// qui affiche le score ne doit pas cacher le micro, et la caméra". Une
/// feuille modale intercepte tous les taps de l'écran derrière elle (c'est
/// ce qui la rend "modale") ; un simple enfant du Stack de l'écran de jeu
/// resterait donc invisible/inatteignable dès qu'elle s'ouvre. En rendant
/// [child] dans l'Overlay RACINE de l'app (voir OverlayPortal.targetsRootOverlay)
/// plutôt que dans le Stack local, il passe AU-DESSUS de cette barrière —
/// visible et tapable même feuille ouverte.
///
/// [child] reste monté en continu (l'OverlayPortal, lui, ne change jamais) —
/// c'est à [child] lui-même de se rendre invisible (`SizedBox.shrink()`)
/// quand il n'a rien à montrer, exactement comme VoiceCallOverlay le fait
/// déjà via `widget.enabled`.
class AlwaysOnTopLayer extends StatefulWidget {
  final Widget child;

  const AlwaysOnTopLayer({super.key, required this.child});

  @override
  State<AlwaysOnTopLayer> createState() => _AlwaysOnTopLayerState();
}

class _AlwaysOnTopLayerState extends State<AlwaysOnTopLayer> {
  final _controller = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    // Affiché après le premier frame — OverlayPortal.show() avant qu'un
    // Overlay racine existe dans l'arbre lèverait une erreur.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.show();
    });
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal.targetsRootOverlay(
      controller: _controller,
      overlayChildBuilder: (context) => widget.child,
    );
  }
}
