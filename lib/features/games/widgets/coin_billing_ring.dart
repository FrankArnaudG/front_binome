import 'package:flutter/material.dart';

import '../../../theme/theme_palette.dart';
import '../../../widgets/coin_icon.dart';
import '../../shop/subscription_status_notifier.dart';

/// Petit indicateur visuel de la progression vers le prochain token
/// déduit en mode à distance (voir demande utilisateur) — un token
/// ([CoinIcon]) entouré d'un anneau qui se remplit au fil du temps réel
/// de jeu, sur la durée réglée en admin (`minutes_per_coin`, voir
/// GameEconomySetting). Purement indicatif côté client, même principe que
/// le chrono affiché à côté (_elapsed()) : fluide à l'écran, jamais la
/// source de vérité — c'est toujours `BillGameSessions` côté serveur qui
/// déduit réellement les tokens (voir GameWalletGuard/GameWalletTicked).
class CoinBillingRing extends StatelessWidget {
  final ThemePalette theme;
  final double progress;
  final double size;

  const CoinBillingRing({super.key, required this.theme, required this.progress, this.size = 20});

  @override
  Widget build(BuildContext context) {
    // Abonnement actif : le temps de jeu est illimité et gratuit (voir
    // BillGameSessions côté backend, aucun débit pour un abonné) — plus
    // aucune raison d'afficher une progression vers un token déduit qui
    // n'arrivera jamais (voir demande utilisateur : "rien ne doit
    // apparaître").
    if (SubscriptionStatusNotifier.instance.isActive) return SizedBox(width: size, height: size);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress.clamp(0, 1),
              strokeWidth: 2,
              backgroundColor: theme.textOnBackgroundMuted.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(theme.primary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(3),
            child: CoinIcon(size: size - 6),
          ),
        ],
      ),
    );
  }
}
