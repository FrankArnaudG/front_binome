import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../theme/theme_scope.dart';
import '../../../widgets/coin_icon.dart';
import '../../../widgets/themed_card.dart';
import '../../shop/shop_screen.dart';
import '../../shop/wallet_balance_notifier.dart';

/// "Compte & Paiement" — solde de tokens + accès direct à la Boutique pour
/// recharger, sans devoir repasser par l'onglet Jeux/Dashboard.
class AccountPaymentCard extends StatefulWidget {
  const AccountPaymentCard({super.key});

  @override
  State<AccountPaymentCard> createState() => _AccountPaymentCardState();
}

class _AccountPaymentCardState extends State<AccountPaymentCard> {
  @override
  void initState() {
    super.initState();
    WalletBalanceNotifier.instance.addListener(_onBalanceChanged);
  }

  @override
  void dispose() {
    WalletBalanceNotifier.instance.removeListener(_onBalanceChanged);
    super.dispose();
  }

  void _onBalanceChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return ThemedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('account_payment_title'), style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: theme.textOnBackground)),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: theme.primaryDeep.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Center(child: CoinIcon(size: 20, fallbackColor: theme.primaryDeep)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('account_balance_label'), style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted)),
                    Text(
                      '${WalletBalanceNotifier.instance.balance}',
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: theme.textOnBackground),
                    ),
                  ],
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: theme.primary),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShopScreen())),
                child: Text(t('account_recharge_button')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            t('account_payment_note'),
            style: GoogleFonts.nunito(fontSize: 11, fontStyle: FontStyle.italic, color: theme.textOnBackgroundMuted),
          ),
        ],
      ),
    );
  }
}
