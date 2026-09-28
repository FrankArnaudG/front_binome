import 'package:flutter/material.dart';

/// Simple relais transparent vers [child] — voir demande utilisateur : "le
/// micro tourne depuis et ne se connecte jamais", constaté en réel dès
/// qu'une partie à distance démarre, PAS SEULEMENT après la fin d'une
/// manche (contrairement à l'objectif initial de ce fichier).
///
/// PREMIÈRE version : [child] (VoiceCallOverlay/NearbyVoiceOverlay) était
/// rendu dans l'Overlay RACINE de l'app via `OverlayPortal.targetsRootOverlay`
/// — voir demande utilisateur : "le modèle qui affiche le score ne doit pas
/// cacher le micro" — pour passer au-dessus du voile modal de la feuille de
/// score. Retiré : ce mécanisme cassait la connexion voix/vidéo (boucle de
/// reconnexion infinie, les DEUX côtés à la fois), probablement un montage
/// en double le temps d'une transition d'écran (VoiceCallService ouvre une
/// seconde connexion WebRTC pour la même Box pendant que la première
/// n'est pas encore proprement fermée). La correction du micro caché par la
/// feuille de score reste À FAIRE (voir demande utilisateur), mais PAS via
/// ce mécanisme — un vrai appel qui ne se connecte plus est bien pire qu'un
/// bouton temporairement voilé par la feuille de score.
class AlwaysOnTopLayer extends StatelessWidget {
  final Widget child;

  const AlwaysOnTopLayer({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
