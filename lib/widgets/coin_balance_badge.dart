import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../features/shop/wallet_balance_notifier.dart';
import '../theme/app_colors.dart';
import 'coin_icon.dart';

/// Badge de solde de pièces (à poser dans une AppBar). Se reconstruit
/// automatiquement quand [WalletBalanceNotifier] change.
class CoinBalanceBadge extends StatelessWidget {
  /// null par défaut : ni la Boutique ni la grille de Cadeaux (déjà à un
  /// tap de la Boutique) n'ont besoin de rendre leur propre badge cliquable.
  final VoidCallback? onTap;

  const CoinBalanceBadge({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WalletBalanceNotifier.instance,
      builder: (context, _) {
        final badge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
