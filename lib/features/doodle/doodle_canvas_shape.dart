/// Hauteur totale (pixels logiques) occupée SOUS le cadre de dessin à
/// l'édition — les rangées Pinceau/Gomme, tailles, couleurs + leurs
/// marges (voir DoodleComposeScreen) — mesurée sur la disposition actuelle
/// de ces 3 rangées. À ajuster si leur contenu change.
///
/// Voir demande utilisateur : "occuper toute la hauteur disponible à
/// l'édition [le cadre ne doit PAS être raccourci artificiellement — les
/// outils en dessous sont un usage réel de cet espace], et adapter la
/// réception en fonction de ça" — plutôt que de deviner un ratio fixe,
/// l'écran de réception (voir DoodleViewScreen, qui n'a pas ces outils)
/// réserve ce même espace de façon invisible (répartie moitié en haut,
/// moitié en bas pour centrer la carte), pour que le cadre obtienne
/// exactement la même taille que celui de l'édition sur un même appareil.
///
/// Ne s'applique volontairement PAS aux vignettes de l'historique (voir
/// demande utilisateur : "uniquement pour cet écran, remettre les
/// dimensions d'avant") — celles-ci gardent leur propre taille fixe,
/// compacte pour une liste, sans chercher à matcher cette forme.
const double kDoodleToolbarReservedHeight = 150;
