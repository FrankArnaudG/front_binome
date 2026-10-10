import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../../../widgets/coin_icon.dart';
import '../../../widgets/themed_card.dart';
import '../../shop/monetization_hub_screen.dart';
import '../../shop/subscription_screen.dart';
import '../../shop/subscription_status_notifier.dart';
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
    SubscriptionStatusNotifier.instance.addListener(_onBalanceChanged);
    // Voir demande utilisateur : "on doit voir si j'ai un abonnement ou
    // pas... si y a abonnement, montrer les détails et les dates" — le
    // cache chargé au démarrage (voir main.dart) ne porte que la date
    // d'expiration, sans le plan (voir SubscriptionStatusNotifier.loadCached) ;
    // ce refresh va chercher le plan complet dès l'ouverture des Paramètres,
    // même principe que SubscriptionScreen._loadInitial.
    SubscriptionStatusNotifier.instance.refresh();
  }

  @override
  void dispose() {
    WalletBalanceNotifier.instance.removeListener(_onBalanceChanged);
    SubscriptionStatusNotifier.instance.removeListener(_onBalanceChanged);
    super.dispose();
  }

  void _onBalanceChanged() {
    if (mounted) setState(() {});
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
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
                // Voir demande utilisateur : "en cliquant sur recharger on
                // doit voir où on demande si je veux faire abonnement ou
                // payer des tokens" — ouvre désormais le choix (voir
                // MonetizationHubScreen), plus l'accès direct à ShopScreen
                // qui sautait cette étape.
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MonetizationHubScreen())),
                child: Text(t('account_recharge_button')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            t('account_payment_note'),
            style: GoogleFonts.nunito(fontSize: 11, fontStyle: FontStyle.italic, color: theme.textOnBackgroundMuted),
          ),
          const SizedBox(height: 14),
          _buildSubscriptionStatus(theme, t),
        ],
      ),
    );
  }

  /// Voir demande utilisateur : "on doit aussi voir si j'ai un abonnement
  /// ou pas, si y a abonnement montrer les détails et les dates" — statut
  /// affiché directement ici plutôt que de forcer un détour par
  /// SubscriptionScreen pour le savoir (cet écran reste accessible au tap,
  /// pour voir/changer de formule).
  Widget _buildSubscriptionStatus(ThemePalette theme, String Function(String, [Map<String, String>?]) t) {
    final subscription = SubscriptionStatusNotifier.instance.subscription;
    final active = SubscriptionStatusNotifier.instance.isActive;

    return Material(
      color: (active ? theme.secondary : theme.textOnBackgroundMuted).withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscriptionScreen())),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                Icons.workspace_premium_rounded,
                color: active ? theme.secondary : theme.textOnBackgroundMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active ? (subscription?.plan?.name ?? t('account_subscription_active_title')) : t('account_subscription_none_title'),
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: theme.textOnBackground),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      active && subscription != null
                          ? t('account_subscription_dates', {
                              'start': _formatDate(subscription.startedAt),
                              'expires': _formatDate(subscription.expiresAt),
                            })
                          : t('account_subscription_none_body'),
                      style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                    ),
                  ],
                ),
              ),
              if (!active)
                Text(
                  t('account_subscription_cta'),
                  style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: theme.primary),
                )
              else
                Icon(Icons.chevron_right_rounded, color: theme.textOnBackgroundMuted),
            ],
          ),
        ),
      ),
    );
  }
}
