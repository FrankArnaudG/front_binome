import 'package:flutter/material.dart';

import '../../../core/api_client.dart';

/// Gère un tap sur "Reprendre" de façon identique pour les 7 jeux
/// interactifs — voir demande utilisateur : "il y a-t-il un loader dès que
/// l'on clique sur reprendre?" (il n'y en avait aucun, et aucune erreur
/// n'était affichée en cas de 422 "solde toujours insuffisant", voir
/// AuthorizesResume côté serveur). [setBusy] désactive le bouton le temps de
/// l'appel ; en cas d'échec, affiche le message exact du serveur, avec un
/// raccourci "Recharger" si c'est un souci de solde.
Future<void> handleResumeTap(
  BuildContext context,
  Future<void> Function() resume,
  void Function(bool) setBusy,
) async {
  setBusy(true);
  try {
    await resume();
  } catch (e) {
    if (!context.mounted) return;
    final isWalletIssue = e is ApiException && e.statusCode == 422 && e.message.toLowerCase().contains('solde');
    // Voir demande utilisateur : "la notification est cachée par les
    // icônes" — un solde/abonnement insuffisant est déjà expliqué par
    // l'encart persistant GameWalletDepletedNotice (affiché dès que
    // pausedByUserId == null, exactement la condition de cet échec),
    // inutile d'empiler un SnackBar par-dessus qui chevauche le micro.
    // Pour tout AUTRE échec (rare), le SnackBar reste utile — repositionné
    // "flottant" avec une marge qui dégage le cluster micro/caméra/chat
    // (même hauteur que le bandeau de GameWalletGuard, left/right:16
    // bottom:24).
    if (isWalletIssue) return;
    final message = e is ApiException ? e.message : "Impossible de reprendre la partie. Réessaie dans un instant.";
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 92),
      ),
    );
  } finally {
    if (context.mounted) setBusy(false);
  }
}
