import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/locale_scope.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/coin_balance_badge.dart';
import 'currency_picker.dart';
import 'currency_service.dart';
import 'preferred_currency_notifier.dart';
import 'shop_screen.dart';
import 'subscription_screen.dart';

/// Écran d'entrée de la Boutique — voir demande utilisateur : l'ancien
/// accès direct à [ShopScreen] (les packs de pièces) ne montrait
/// l'abonnement que via une petite bannière secondaire, facile à ne jamais
/// remarquer. Ici, les deux façons de payer (abonnement ou pièces à
/// l'unité) sont présentées à égalité, dès l'ouverture, chacune avec un "i"
/// expliquant son avantage — c'est CET écran que la tuile "Boutique" du
/// Dashboard ouvre désormais, [ShopScreen]/[SubscriptionScreen] restant
/// leurs propres écrans, atteints d'ici.
class MonetizationHubScreen extends StatefulWidget {
  const MonetizationHubScreen({super.key});

  @override
  State<MonetizationHubScreen> createState() => _MonetizationHubScreenState();
}

class _MonetizationHubScreenState extends State<MonetizationHubScreen> {
  bool _currencyCheckStarted = false;

  @override
  void initState() {
    super.initState();
    // Le choix de devise doit être fait ICI, avant même de choisir entre
    // abonnement et pièces — les deux écrans suivants en ont besoin pour
    // afficher des prix cohérents (voir demande utilisateur : "des que lon
    // ouvre on doit voir on demande de choisir la devise si pas deja
    // choisit").
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCurrencySelected());
  }

  Future<void> _ensureCurrencySelected() async {
    if (_currencyCheckStarted || !mounted) return;
    _currencyCheckStarted = true;

    if (PreferredCurrencyNotifier.instance.currency == null) {
      await _promptCurrencyChoice();
      if (!mounted) return;
    }

    await PreferredCurrencyNotifier.instance.refresh();
  }

  Future<void> _promptCurrencyChoice() async {
    final chosen = await showCurrencyPicker(context);
    if (chosen == null || !mounted) return;

    try {
      await CurrencyService.instance.setPreferredCurrency(chosen);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LocaleScope.of(context).t('common_network_error'))),
      );
      return;
    }

    PreferredCurrencyNotifier.instance.set(chosen);
  }

  void _showInfo(String title, String body) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground)),
        content: Text(body, style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(t('common_ok'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(
          t('shop_title'),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: CoinBalanceBadge()),
          ),
        ],
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                t('monetization_hub_prompt'),
                style: GoogleFonts.nunito(fontSize: 14, color: theme.textOnBackgroundMuted),
              ),
              const SizedBox(height: 20),
              _MonetizationOptionCard(
                theme: theme,
                icon: Icons.workspace_premium_rounded,
                iconGradient: [theme.primary, theme.secondary],
                title: t('monetization_option_subscription_title'),
                body: t('monetization_option_subscription_body'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                ),
                onInfoTap: () => _showInfo(
                  t('monetization_option_subscription_title'),
                  t('monetization_option_subscription_info'),
                ),
              ),
              const SizedBox(height: 16),
              _MonetizationOptionCard(
                theme: theme,
                icon: Icons.monetization_on_rounded,
                iconGradient: [theme.accent, theme.primaryDeep],
                title: t('monetization_option_coins_title'),
                body: t('monetization_option_coins_body'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ShopScreen()),
                ),
                onInfoTap: () => _showInfo(
                  t('monetization_option_coins_title'),
                  t('monetization_option_coins_info'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonetizationOptionCard extends StatelessWidget {
  final ThemePalette theme;
  final IconData icon;
  final List<Color> iconGradient;
  final String title;
  final String body;
  final VoidCallback onTap;
  final VoidCallback onInfoTap;

  const _MonetizationOptionCard({
    required this.theme,
    required this.icon,
    required this.iconGradient,
    required this.title,
    required this.body,
    required this.onTap,
    required this.onInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: iconGradient),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16, color: theme.textOnBackground),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted, height: 1.3),
                    ),
                  ],
                ),
              ),
              // Cercle "i" séparé du reste de la carte (voir demande
              // utilisateur : "avec un i pour expliquer l'avantage") — un
              // simple InkWell dédié plutôt qu'un IconButton, pour un
              // cercle de taille cohérente avec le reste de la carte.
              Material(
                color: theme.primary.withValues(alpha: 0.12),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onInfoTap,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.info_outline_rounded, size: 18, color: theme.primary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
