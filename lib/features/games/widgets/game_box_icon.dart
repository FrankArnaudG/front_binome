import 'package:flutter/material.dart';

/// Doit rester synchronisé avec GameBoxController::ICONS côté backend.
IconData iconForGameBox(String? key) {
  switch (key) {
    case 'sprout':
      return Icons.eco_rounded;
    case 'roots':
      return Icons.park_rounded;
    case 'compass':
      return Icons.explore_rounded;
    case 'open_heart':
      return Icons.favorite_rounded;
    case 'horizon':
      return Icons.wb_twilight_rounded;
    case 'star':
      return Icons.star_rounded;
    case 'flame':
      return Icons.local_fire_department_rounded;
    case 'key':
      return Icons.vpn_key_rounded;
    case 'paw':
      return Icons.pets_rounded;
    case 'briefcase':
      return Icons.work_rounded;
    case 'film':
      return Icons.movie_rounded;
    case 'ball':
      return Icons.sports_soccer_rounded;
    default:
      return Icons.auto_awesome_rounded;
  }
}
