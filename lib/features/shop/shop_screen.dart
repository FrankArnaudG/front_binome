import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/locale_scope.dart';
import '../../models/coin_pack.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/coin_balance_badge.dart';
import '../../widgets/coin_icon.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_chip.dart';
import 'currency_picker.dart';
import 'currency_service.dart';
import 'preferred_currency_notifier.dart';
import 'shop_service.dart';
import 'subscription_screen.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  // Peint depuis le cache (voir LocalCache/ShopService.cachedCoinPacks)
  // immédiatement au premier rendu SANS jamais montrer de loader tant qu'on
  // a déjà quelque chose à l'écran — le réseau ne fait ensuite que
  // rafraîchir discrètement par-dessus. Même principe que TimelineScreen.
  List<CoinPack>? _packs;
  bool _initialLoading = true;
  bool _loadError = false;
  bool _currencyCheckStarted = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    // Un changement de devise depuis les Paramètres doit se refléter ici
    // même si cet écran était déjà ouvert (sinon : prix visiblement
    // périmés tant qu'on n'a pas quitté/rouvert la Boutique à la main).
    PreferredCurrencyNotifier.instance.addListener(_onCurrencyChanged);
    // Demandée dès l'ouverture de la Boutique — pas seulement au moment de
    // taper sur un pack — pour que les prix affichés soient déjà dans la
    // bonne devise avant même de parcourir les packs.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _ensureCurrencySelected(),
    );
  }

  @override
  void dispose() {
    PreferredCurrencyNotifier.instance.removeListener(_onCurrencyChanged);
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final cached = await ShopService.instance.cachedCoinPacks();
    if (cached != null && mounted) {
      setState(() {
        _packs = cached;
        _initialLoading = false;
      });
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    try {
      final packs = await ShopService.instance.fetchCoinPacks();
      if (!mounted) return;
      setState(() {
        _packs = packs;
        _initialLoading = false;
        _loadError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        _loadError = _packs == null;
      });
    }
  }

  void _onCurrencyChanged() {
    if (!mounted) return;
    _refresh();
  }

  /// Décide instantanément (depuis le cache déjà chargé au démarrage de
  /// l'app, voir main.dart) s'il faut proposer le choix de devise — sans
  /// attendre de réseau, qui laissait sinon les prix s'afficher un court
  /// instant avant que la modale n'apparaisse. Le serveur est ensuite
  /// consulté en silence juste après pour rattraper un changement fait
  /// depuis un autre appareil (voir PreferredCurrencyNotifier.refresh).
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
    // Pas de fermeture sans choisir la première fois (dismissible: false
    // par défaut) — ce n'est pas une option secondaire, la Boutique en a
    // besoin pour afficher des prix cohérents.
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

    // Notifie tous les écrans à l'écoute (dont celui-ci, via
    // _onCurrencyChanged) — plus besoin de refetch manuellement ici.
    PreferredCurrencyNotifier.instance.set(chosen);
  }

  Future<void> _openPurchase(CoinPack pack) async {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    // Filet de sécurité : la devise est normalement déjà réglée dès
    // l'ouverture de l'écran (voir _ensureCurrencySelected).
    if (PreferredCurrencyNotifier.instance.currency == null) {
      await _promptCurrencyChoice();
      if (!mounted) return;
      final refreshed = await ShopService.instance.fetchCoinPacks();
      pack = refreshed.firstWhere((p) => p.id == pack.id, orElse: () => pack);
    }

    if (!mounted) return;
    final provider = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: theme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ProviderSheet(pack: pack),
    );
    if (provider == null || !mounted) return;

    // "ligdicash" est un 3e choix distinct proposé par _ProviderSheet, en
    // plus des deux tiles de test existants (Orange Money/Wave, inchangés
    // ci-dessous) — voir la demande explicite de garder le flux manuel
    // actuel comme chemin par défaut, LigdiCash n'étant qu'une option
    // supplémentaire tant qu'il n'est pas éprouvé en conditions réelles.
    if (provider == 'ligdicash') {
      await _payViaLigdiCash(pack);
      return;
    }

    try {
      await ShopService.instance.createOrder(
        coinPackId: pack.id,
        provider: provider,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('shop_order_created_title')),
          content: Text(
            t('shop_order_created_body', {
              'amount': '${pack.coinAmount}',
              'provider': _providerLabel(provider),
            }),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(t('common_ok')),
            ),
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('common_network_error'))),
      );
    }
  }

  /// Chemin séparé pour la vraie passerelle LigdiCash — ne remplace ni ne
  /// dégrade vers le dialogue "commande créée, en attente" existant : si
  /// `payment_url` est absent (clés pas encore configurées côté back), on
  /// le dit clairement plutôt que de basculer silencieusement sur l'autre
  /// flux, ce qui serait trompeur pour un bouton qui promet un vrai paiement.
  Future<void> _payViaLigdiCash(CoinPack pack) async {
    final t = LocaleScope.of(context).t;

    try {
      final order = await ShopService.instance.createOrder(
        coinPackId: pack.id,
        provider: 'manual',
      );
      if (!mounted) return;

      final paymentUrl = order.paymentUrl;
      if (paymentUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('shop_ligdicash_not_configured'))),
        );
        return;
      }

      // LigdiCash bloque explicitement l'affichage en iframe/WebView —
      // navigateur externe obligatoire. Le webhook back confirmera le
      // paiement ; WalletBalanceNotifier se rafraîchit tout seul au retour
      // dans l'app (voir AppShell.didChangeAppLifecycleState).
      await launchUrl(Uri.parse(paymentUrl), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('common_network_error'))),
      );
    }
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
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: theme.textOnBackground,
          ),
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
          child: Builder(
            builder: (context) {
              if (_initialLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (_loadError) {
                return EmptyState(
                  icon: Icons.wifi_off_rounded,
                  message: t('shop_load_error'),
                );
              }
              final packs = _packs ?? [];
              if (packs.isEmpty) {
                return EmptyState(
                  icon: Icons.monetization_on_rounded,
                  message: t('shop_empty'),
                );
              }
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: _SubscriptionBanner(theme: theme, t: t),
                  ),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(20),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.76,
                      ),
                      itemCount: packs.length,
                      itemBuilder: (context, index) {
                        final pack = packs[index];
                        return _CoinPackTile(
                          pack: pack,
                          onTap: () => _openPurchase(pack),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Voir demande utilisateur : petite section faisant découvrir l'abonnement
/// depuis la Boutique aux pièces elle-même, plutôt qu'un simple bouton
/// discret dans la barre du haut.
class _SubscriptionBanner extends StatelessWidget {
  final ThemePalette theme;
  final String Function(String, [Map<String, String>?]) t;

  const _SubscriptionBanner({required this.theme, required this.t});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.primary.withValues(alpha: theme.isDark ? 0.22 : 0.1),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [theme.primary, theme.secondary]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('shop_subscription_banner_title'),
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: theme.textOnBackground),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t('shop_subscription_banner_body'),
                      style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: theme.textOnBackgroundMuted, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

String _providerLabel(String provider) => switch (provider) {
  'orange_money' => 'Orange Money',
  'wave' => 'Wave',
  _ => provider,
};

/// Le FCFA n'a pas de sous-unité usuelle (toujours des montants ronds) —
/// les autres devises (EUR, USD) en ont besoin pour rester lisibles sur de
/// petits packs (ex. 0,31 € et non 0 €).
String _formatPrice(CoinPack pack) {
  final decimals = pack.priceCurrency == 'XOF' ? 0 : 2;
  return '${pack.priceAmount.toStringAsFixed(decimals)} ${currencySymbol(pack.priceCurrency)}';
}

class _ProviderSheet extends StatelessWidget {
  final CoinPack pack;

  const _ProviderSheet({required this.pack});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pack.name,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: theme.textOnBackground,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${t('coin_count', {'amount': '${pack.coinAmount}'})} • ${_formatPrice(pack)}',
              style: GoogleFonts.nunito(
                fontSize: 14,
                color: theme.textOnBackgroundMuted,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              t('shop_payment_method'),
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.textOnBackground,
              ),
            ),
            const SizedBox(height: 12),
            _ProviderTile(
              label: 'Orange Money',
              value: 'orange_money',
              theme: theme,
            ),
            const SizedBox(height: 10),
            _ProviderTile(label: 'Wave', value: 'wave', theme: theme),
            const SizedBox(height: 16),
            Divider(color: (theme.isDark ? Colors.white : Colors.black).withValues(alpha: 0.08)),
            const SizedBox(height: 4),
            _ProviderTile(
              label: t('shop_pay_ligdicash'),
              value: 'ligdicash',
              theme: theme,
              icon: Icons.bolt_rounded,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  final String label;
  final String value;
  final ThemePalette theme;
  final IconData icon;

  const _ProviderTile({
    required this.label,
    required this.value,
    required this.theme,
    this.icon = Icons.account_balance_wallet_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).pop(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: (theme.isDark ? Colors.white : Colors.black).withValues(
                alpha: 0.06,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: theme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: theme.textOnBackground,
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

class _CoinPackTile extends StatelessWidget {
  final CoinPack pack;
  final VoidCallback onTap;

  const _CoinPackTile({required this.pack, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return Material(
      color: theme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: (theme.isDark ? Colors.white : Colors.black).withValues(
                alpha: 0.06,
              ),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CoinIcon(
                size: 32,
                fallbackColor: theme.primaryDeep,
                assetPath: pack.imagePath != null
                    ? 'assets/images/shop/${pack.imagePath}'
                    : null,
              ),
              const SizedBox(height: 8),
              Text(
                pack.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: theme.textOnBackground,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                t('coin_count', {'amount': '${pack.coinAmount}'}),
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  color: theme.textOnBackgroundMuted,
                ),
              ),
              if (pack.bonusCoins != null) ...[
                const SizedBox(height: 4),
                StatusChip(
                  label: t('shop_bonus_label', {'bonus': '${pack.bonusCoins}'}),
                  color: theme.secondary,
                ),
              ],
              const SizedBox(height: 6),
              Text(
                _formatPrice(pack),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: theme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
