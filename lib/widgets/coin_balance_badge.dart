import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../features/shop/subscription_status_notifier.dart';
import '../features/shop/wallet_balance_notifier.dart';
import '../l10n/locale_scope.dart';
import '../theme/app_colors.dart';
import 'coin_icon.dart';

/// Badge de solde de pièces (à poser dans une AppBar). Se reconstruit
/// automatiquement quand [WalletBalanceNotifier] change — et, avec un
/// abonnement actif, affiche "Illimité" à la place du solde (voir demande
/// utilisateur : "si j'ai un abonnement payant, es ce possible de remplacer
/// les pièces... par quelque chose d'autre") puisque le solde de pièces ne
/// reflète alors plus rien (les pièces restent inchangées, jamais
/// débitées tant que l'abonnement est actif — voir User::hasActiveSubscription
/// côté backend).
class CoinBalanceBadge extends StatelessWidget {
  /// null par défaut : ni la Boutique ni la grille de Cadeaux (déjà à un
  /// tap de la Boutique) n'ont besoin de rendre leur propre badge cliquable.
  final VoidCallback? onTap;

  const CoinBalanceBadge({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([WalletBalanceNotifier.instance, SubscriptionStatusNotifier.instance]),
      builder: (context, _) {
        final subscribed = SubscriptionStatusNotifier.instance.isActive;
        final t = LocaleScope.of(context).t;
        final badge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: (subscribed ? AppColors.secondary : AppColors.accent).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: subscribed
                ? [
                    const Icon(Icons.workspace_premium_rounded, size: 18, color: AppColors.secondary),
                    const SizedBox(width: 6),
                    // Le symbole "∞" seul rendait le badge presque
                    // invisible à taille de texte normale (voir demande
                    // utilisateur : "c'est petit") — taille de police
                    // nettement plus grande ici que pour un nombre de
                    // pièces classique, sans changer la hauteur du badge
                    // (voir height:1 pour éviter un padding vertical
                    // supplémentaire dû à la ligne de police plus grande).
                    Text(
                      t('coin_badge_unlimited'),
                      style: GoogleFonts.poppins(fontSize: 18, height: 1, fontWeight: FontWeight.w800, color: AppColors.textOnBlush),
                    ),
                  ]
                : [
                    const CoinIcon(size: 16, fallbackColor: AppColors.primaryDeep),
                    const SizedBox(width: 6),
                    Text(
                      WalletBalanceNotifier.format(WalletBalanceNotifier.instance.balance),
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textOnBlush),
                    ),
                  ],
          ),
        );
        if (onTap == null) return badge;
        return Material(
          color: Colors.transparent,
          shape: const StadiumBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: badge,
          ),
        );
      },
    );
  }
}
