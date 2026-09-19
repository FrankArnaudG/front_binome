import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/payment_return_watcher.dart';
import '../../l10n/locale_scope.dart';
import '../../models/coin_pack.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/coin_balance_badge.dart';
import '../../widgets/coin_icon.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_chip.dart';
import 'currency_picker.dart';
import 'currency_service.dart';
import 'payment_confirm_sheet.dart';
import 'preferred_currency_notifier.dart';
import 'shop_service.dart';

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
    // Récapitulatif avant paiement (voir demande utilisateur) — annonce
    // clairement l'équivalent FCFA puisque YengaPay ne règle qu'en XOF,
    // même si le prix ci-dessus est affiché dans une autre devise.
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PaymentConfirmSheet(
        title: pack.name,
        subtitle: t('coin_count', {'amount': '${pack.coinAmount}'}),
        xofAmountLabel: '${pack.priceAmountXofNative.toStringAsFixed(0)} FCFA',
        // Équivalent dans la devise choisie — inutile si elle est déjà XOF
        // (voir demande utilisateur : "ajoute le montant en euro ou dans
        // la devise demandée").
        approxAmountLabel: pack.priceCurrency == 'XOF' ? null : _formatPrice(pack),
        onConfirm: () => _payViaYengaPay(pack),
      ),
    );
  }

  /// Un seul vrai moyen de paiement désormais : YengaPay (voir demande
  /// utilisateur, remplace les anciennes tuiles Orange Money/Wave
  /// manuelles qui ne déclenchaient aucun vrai paiement, et LigdiCash).
  /// YengaPay affiche lui-même le choix mobile money/carte sur SA page de
  /// checkout — rien à distinguer côté app.
  Future<void> _payViaYengaPay(CoinPack pack) async {
    final t = LocaleScope.of(context).t;

    try {
      final order = await ShopService.instance.createOrder(
        coinPackId: pack.id,
        provider: 'yengapay',
      );
      if (!mounted) return;

      final paymentUrl = order.paymentUrl;
      if (paymentUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('shop_yengapay_not_configured'))),
        );
        return;
      }

      // Navigateur externe (pas de WebView) : le webhook back confirmera
      // le paiement ; WalletBalanceNotifier se rafraîchit tout seul au
      // retour dans l'app (voir AppShell.didChangeAppLifecycleState).
      PaymentReturnWatcher.instance.arm();
      await launchUrl(Uri.parse(paymentUrl), mode: LaunchMode.externalApplication);
    } on ApiException catch (e) {
      // Affiche le vrai message du serveur (ex. "Non authentifié") plutôt
      // que le message réseau générique — celui-ci masquait des échecs qui
      // n'avaient rien à voir avec la connexion (voir demande utilisateur :
      // session cassée après un changement de compte, confondue avec un
      // problème réseau faute de détail affiché).
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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


/// Le FCFA n'a pas de sous-unité usuelle (toujours des montants ronds) —
/// les autres devises (EUR, USD) en ont besoin pour rester lisibles sur de
/// petits packs (ex. 0,31 € et non 0 €).
String _formatPrice(CoinPack pack) {
  final decimals = pack.priceCurrency == 'XOF' ? 0 : 2;
  return '${pack.priceAmount.toStringAsFixed(decimals)} ${currencySymbol(pack.priceCurrency)}';
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
