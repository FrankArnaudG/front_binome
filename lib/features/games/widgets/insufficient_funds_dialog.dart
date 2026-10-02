import 'package:flutter/material.dart';

import '../../shop/shop_screen.dart';
import '../../shop/subscription_screen.dart';

/// Modal bloquant affiché quand une invitation à une partie à distance ne
/// peut pas être acceptée faute de tokens/abonnement — voir demande
/// utilisateur : "tu affiches un modal et tu stoppes la connexion", repris
/// à l'identique pour l'invité·e (GameInviteOverlay, réponse HTTP directe)
/// ET pour l'auteur resté sur l'écran d'attente (GameInviteWaitingScreen,
/// voir GameInviteJoinFailed côté serveur) — voir demande utilisateur :
/// "ce modal doit apparaître pour les 2 binômes".
void showInsufficientFundsDialog(BuildContext context, String message) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.account_balance_wallet_outlined),
      title: const Text('Impossible de rejoindre'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Fermer'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShopScreen()));
          },
          child: const Text('Acheter des tokens'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
          },
          child: const Text("S'abonner"),
        ),
      ],
    ),
  );
}
