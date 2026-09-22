/// Note ajoutée aux guides des écrans qui MÈNENT à une partie à distance ou en
/// présentiel connecté (choix du mode, choix de la difficulté) — voir demande
/// utilisateur : le guide "Comment jouer" n'existe plus sur l'écran de jeu de
/// ces deux modes, il ne reste que dans le mode "Présentiel, un seul
/// téléphone" (une seule personne le suit, sans dépendre de l'autre).
///
/// Ne concerne pas le Jeu de Carte Classique, qui n'a pas de mode à un seul
/// téléphone : la note y renverrait vers une option qui n'existe pas.
const String kHowToPlayNote =
    "N.B. : pour suivre le guide « Comment jouer », choisis l'option « Présentiel, un seul téléphone ».";

/// Texte d'une bulle de guide, avec la note à la suite (séparée par une ligne
/// vide) quand [note] est renseignée.
String withGuideNote(String description, String? note) => note == null ? description : '$description\n\n$note';
