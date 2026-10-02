import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../shop/shop_screen.dart';

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
    final message = e is ApiException ? e.message : "Impossible de reprendre la partie. Réessaie dans un instant.";
    final isWalletIssue = e is ApiException && e.statusCode == 422 && e.message.toLowerCase().contains('solde');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        action: isWalletIssue
            ? SnackBarAction(
                label: 'Recharger',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShopScreen())),
              )
            : null,
      ),
    );
  } finally {
    if (context.mounted) setBusy(false);
  }
}
