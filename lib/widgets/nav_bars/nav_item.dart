import 'package:flutter/material.dart';

/// Description d'un onglet, partagée par les 4 styles de barre de
/// navigation (voir [NavBarStyleController]) : icône "outlined" au repos,
/// icône pleine à l'état actif, label toujours visible.
class NavItem {
  final IconData outlinedIcon;
  final IconData filledIcon;
  final String label;

  /// Nombre à afficher dans une petite pastille sur l'icône (ex. envois
  /// reçus non ouverts sur l'onglet Carnet de bord) — `null`/`0` : pas de
  /// pastille.
  final int? badgeCount;

  const NavItem({required this.outlinedIcon, required this.filledIcon, required this.label, this.badgeCount});
}
