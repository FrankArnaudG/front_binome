import 'package:flutter/painting.dart';

/// Apparence d'une famille de battements de cœur (tendresse, pensée, manque…) :
/// image packagée dans l'app + zone où poser le texte. La famille est portée
/// par le message du catalogue et recopiée dans l'envoi (voir
/// HeartbeatNudge::family côté backend) ; un message personnalisé ou un
/// ancien envoi n'en a pas et garde la carte blanche habituelle.
///
/// Chaque image est composée (voir prompts) avec les personnages dans le bas
/// et une zone dégagée en haut, à gauche/droite/centre selon la famille : le
/// texte se pose dans cette zone, jamais par-dessus le couple.
class HeartbeatFamilyStyle {
  /// Nom de fichier sans extension, dans assets/heartbeat_categories/.
  final String assetBase;

  /// Deux variantes (`_fille` / `_garcon`) : l'image montre la personne qui
  /// ENVOIE le battement, pour elle comme pour son binôme à la réception.
  final bool byGender;

  /// Où se trouve la zone dégagée (haut-gauche, haut-droite, haut-centre).
  final Alignment textAlignment;
  final TextAlign textAlign;

  /// Largeur de la zone de texte, en fraction de la largeur de la carte.
  final double widthFactor;

  const HeartbeatFamilyStyle(
    this.assetBase,
    this.textAlignment,
    this.textAlign,
    this.widthFactor, {
    this.byGender = false,
  });

  String assetFor(String? senderGender) {
    final suffix = byGender ? (senderGender == 'Femme' ? '_fille' : '_garcon') : '';
    return 'assets/heartbeat_categories/$assetBase$suffix.jpg';
  }
}

// Public (pas de préfixe `_`) — voir demande utilisateur : "afficher la
// liste des images utilisées pour les familles" pour l'option
// "Personnalisé" (voir HeartbeatFamilyPicker), qui a besoin d'énumérer ces
// mêmes familles plutôt que de les redéfinir en double.
const Map<String, HeartbeatFamilyStyle> heartbeatFamilies = {
  'tendresse': HeartbeatFamilyStyle('tendresse', Alignment.topLeft, TextAlign.left, 0.72),
  'pensee': HeartbeatFamilyStyle('pensee', Alignment.topLeft, TextAlign.left, 0.72, byGender: true),
  'manque': HeartbeatFamilyStyle('manque', Alignment.topRight, TextAlign.right, 0.72, byGender: true),
  'amour': HeartbeatFamilyStyle('amour', Alignment.topCenter, TextAlign.center, 0.86),
  'seduction': HeartbeatFamilyStyle('seduction', Alignment.topRight, TextAlign.right, 0.72),
  'humour': HeartbeatFamilyStyle('humour', Alignment.topCenter, TextAlign.center, 0.86),
  'battements': HeartbeatFamilyStyle('battements', Alignment.topLeft, TextAlign.left, 0.72),
  'profond': HeartbeatFamilyStyle('profond', Alignment.topCenter, TextAlign.center, 0.86),
  'reconfort': HeartbeatFamilyStyle('reconfort', Alignment.topLeft, TextAlign.left, 0.72),
};

/// `null` si la famille est absente ou n'a pas encore d'image dans l'app.
HeartbeatFamilyStyle? heartbeatFamilyStyleFor(String? family) =>
    family == null ? null : heartbeatFamilies[family];
