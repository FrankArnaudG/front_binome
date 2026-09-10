import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/locale_scope.dart';
import '../../models/subscription_plan.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_chip.dart';
import 'currency_picker.dart';
import 'currency_service.dart';
import 'preferred_currency_notifier.dart';
import 'subscription_service.dart';
import 'subscription_status_notifier.dart';

/// Écran de test pour l'abonnement — alternative au système de pièces
/// (voir ShopScreen, dont cet écran reprend la même structure : choix de
/// devise, feuille de choix du moyen de paiement, commande "en attente"
/// confirmée manuellement par un admin, aucune vraie passerelle de
/// paiement pour l'instant).
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  List<SubscriptionPlan>? _plans;
  bool _initialLoading = true;
  bool _loadError = false;
  bool _currencyCheckStarted = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    PreferredCurrencyNotifier.instance.addListener(_onCurrencyChanged);
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
    await Future.wait([
      _refresh(),
      SubscriptionStatusNotifier.instance.refresh(),
    ]);
  }

  Future<void> _refresh() async {
    try {
      final plans = await SubscriptionService.instance.fetchPlans();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _initialLoading = false;
        _loadError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        _loadError = _plans == null;
      });
    }
  }

  void _onCurrencyChanged() {
    if (!mounted) return;
    _refresh();
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

  Future<void> _openPurchase(SubscriptionPlan plan) async {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    if (PreferredCurrencyNotifier.instance.currency == null) {
      await _promptCurrencyChoice();
      if (!mounted) return;
      final refreshed = await SubscriptionService.instance.fetchPlans();
      plan = refreshed.firstWhere((p) => p.id == plan.id, orElse: () => plan);
    }

    if (!mounted) return;
    final provider = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: theme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ProviderSheet(plan: plan),
    );
    if (provider == null || !mounted) return;

    // "ligdicash" est un 3e choix distinct proposé par _ProviderSheet, en
    // plus des deux tiles de test existants (Orange Money/Wave, inchangés
    // ci-dessous) — voir ShopScreen._payViaLigdiCash pour le même principe
    // côté achat de pièces : le flux manuel reste le chemin par défaut.
    if (provider == 'ligdicash') {
      await _payViaLigdiCash(plan);
      return;
    }

    try {
      await SubscriptionService.instance.createOrder(
        subscriptionPlanId: plan.id,
        provider: provider,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('subscription_order_created_title')),
          content: Text(
            t('subscription_order_created_body', {
              'plan': plan.name,
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

  /// Chemin séparé pour la vraie passerelle LigdiCash — voir
  /// ShopScreen._payViaLigdiCash (mirroir exact) : ne remplace ni ne
  /// dégrade vers le dialogue "commande créée, en attente" existant.
  Future<void> _payViaLigdiCash(SubscriptionPlan plan) async {
    final t = LocaleScope.of(context).t;

    try {
      final order = await SubscriptionService.instance.createOrder(
        subscriptionPlanId: plan.id,
        provider: 'manual',
      );
      if (!mounted) return;

      final paymentUrl = order.paymentUrl;
      if (paymentUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('subscription_ligdicash_not_configured'))),
        );
        return;
      }

      await launchUrl(Uri.parse(paymentUrl), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('common_network_error'))),
      );
    }
  }

  /// Voir demande utilisateur : "ajouter les pourcentages... si vous
  /// économisez tel pourcent" — badge sur la formule annuelle, calculé par
  /// rapport à la mensuelle de LA MÊME formule (solo vs solo, couple vs
  /// couple — jamais l'annuel solo comparé au mensuel couple).
  List<Widget> _planTiles(List<SubscriptionPlan> scopedPlans, String Function(String, [Map<String, String>?]) t) {
    final monthlyMatches = scopedPlans.where((p) => !p.isAnnual);
    final monthly = monthlyMatches.isEmpty ? null : monthlyMatches.first;
    return scopedPlans
        .map(
          (plan) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PlanTile(
              plan: plan,
              savingsPercent: (plan.isAnnual && monthly != null) ? _savingsPercent(monthly, plan) : null,
              onTap: () => _openPurchase(plan),
            ),
          ),
        )
        .toList();
  }

  int? _savingsPercent(SubscriptionPlan monthly, SubscriptionPlan annual) {
    final yearlyIfMonthly = monthly.priceAmountXof * 12;
    if (yearlyIfMonthly <= 0 || annual.priceAmountXof >= yearlyIfMonthly) return null;
    return (((yearlyIfMonthly - annual.priceAmountXof) / yearlyIfMonthly) * 100).round();
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
          t('subscription_title'),
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: theme.textOnBackground,
          ),
        ),
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
                  message: t('subscription_load_error'),
                );
              }
              final plans = _plans ?? [];
              if (plans.isEmpty) {
                return EmptyState(
                  icon: Icons.workspace_premium_rounded,
                  message: t('subscription_empty'),
                );
              }
              final soloPlans = plans.where((p) => !p.isCouple).toList();
              final couplePlans = plans.where((p) => p.isCouple).toList();

              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _StatusBanner(theme: theme, t: t),
                  const SizedBox(height: 20),
                  if (soloPlans.isNotEmpty) ...[
                    _ScopeHeader(title: t('subscription_scope_solo'), theme: theme),
                    const SizedBox(height: 10),
                    ..._planTiles(soloPlans, t),
                    const SizedBox(height: 20),
                  ],
                  if (couplePlans.isNotEmpty) ...[
                    _ScopeHeader(title: t('subscription_scope_couple'), subtitle: t('subscription_scope_couple_hint'), theme: theme),
                    const SizedBox(height: 10),
                    ..._planTiles(couplePlans, t),
                  ],
                ],
              );
            },
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

String _formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

String _formatPrice(SubscriptionPlan plan, String Function(String, [Map<String, String>?]) t) {
  final decimals = plan.priceCurrency == 'XOF' ? 0 : 2;
  final period = plan.period == 'year' ? t('subscription_period_year') : t('subscription_period_month');
  return '${plan.priceAmountXof.toStringAsFixed(decimals)} ${currencySymbol(plan.priceCurrency)}$period';
}

/// Voir demande utilisateur : "deux options, paiement pour moi-même et
/// paiement pour le couple" — sépare les formules en deux groupes plutôt
/// qu'une simple liste plate.
class _ScopeHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final ThemePalette theme;

  const _ScopeHeader({required this.title, this.subtitle, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: theme.textOnBackground),
        ),
        if (subtitle != null) ...[
          const SizedBox(width: 8),
          Text(subtitle!, style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted)),
        ],
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final ThemePalette theme;
  final String Function(String, [Map<String, String>?]) t;

  const _StatusBanner({required this.theme, required this.t});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SubscriptionStatusNotifier.instance,
      builder: (context, _) {
        final notifier = SubscriptionStatusNotifier.instance;
        final active = notifier.isActive;
        final message = active
            ? t('subscription_active_banner', {
                'date': _formatDate(notifier.expiresAt!),
              })
            : t('subscription_not_active');

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: (active ? theme.secondary : theme.primary).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(
                active ? Icons.workspace_premium_rounded : Icons.info_outline_rounded,
                color: active ? theme.secondary : theme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.textOnBackground,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProviderSheet extends StatelessWidget {
  final SubscriptionPlan plan;

  const _ProviderSheet({required this.plan});

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
              plan.name,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: theme.textOnBackground,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatPrice(plan, t),
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
              label: t('subscription_pay_ligdicash'),
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

class _PlanTile extends StatelessWidget {
  final SubscriptionPlan plan;
  final int? savingsPercent;
  final VoidCallback onTap;

  const _PlanTile({required this.plan, this.savingsPercent, required this.onTap});

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
          padding: const EdgeInsets.all(16),
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
              Icon(Icons.workspace_premium_rounded, color: theme.primaryDeep, size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: theme.textOnBackground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatPrice(plan, t),
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: theme.primary,
                      ),
                    ),
                    if (savingsPercent != null) ...[
                      const SizedBox(height: 6),
                      StatusChip(
                        label: t('subscription_savings_badge', {'percent': '$savingsPercent'}),
                        color: theme.secondary,
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.textOnBackgroundMuted),
            ],
          ),
        ),
      ),
    );
  }
}
