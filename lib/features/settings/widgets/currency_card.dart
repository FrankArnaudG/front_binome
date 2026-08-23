import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../theme/theme_scope.dart';
import '../../../widgets/themed_card.dart';
import '../../shop/currency_picker.dart';
import '../../shop/currency_service.dart';
import '../../shop/preferred_currency_notifier.dart';

/// Nom complet de la devise si trouvé dans la liste chargée depuis
/// l'admin, ex. "Franc CFA (XOF)" — sinon juste le code (ex. le temps que
/// [_options] finisse de charger, ou une devise retirée entre-temps).
String _currencyDisplayLabel(BuildContext context, String? currencyCode, List<CurrencyOption> options) {
  if (currencyCode == null) return LocaleScope.of(context).t('shop_currency_not_chosen');
  for (final option in options) {
    if (option.currency == currencyCode) {
      return option.label != null ? '${option.label} ($currencyCode)' : currencyCode;
    }
  }
  return currencyCode;
}

/// Devise d'affichage de la Boutique — modifiable à tout moment,
/// contrairement au code promo de parrainage. Chaque commande garde de
/// toute façon sa propre devise figée à l'achat, donc changer cette
/// préférence n'affecte jamais l'historique, seulement les prochains achats
/// (voir ProfileController::setPreferredCurrency côté backend).
class CurrencyCard extends StatefulWidget {
  const CurrencyCard({super.key});

  @override
  State<CurrencyCard> createState() => _CurrencyCardState();
}

class _CurrencyCardState extends State<CurrencyCard> {
  List<CurrencyOption> _options = const [];

  @override
  void initState() {
    super.initState();
    PreferredCurrencyNotifier.instance.addListener(_onCurrencyChanged);
    // Toujours interroger le serveur en arrivant sur cet écran plutôt que de
    // faire confiance à une valeur en cache qui pourrait être périmée.
    PreferredCurrencyNotifier.instance.refresh();
    // Pour afficher le nom complet de la devise (ex. "Franc CFA") à côté du
    // code — le seul endroit qui le connaît est cette liste, le code seul
    // ne suffit pas à le retrouver côté app.
    CurrencyService.instance.fetchAvailableCurrencies().then((options) {
      if (mounted) setState(() => _options = options);
    });
  }

  @override
  void dispose() {
    PreferredCurrencyNotifier.instance.removeListener(_onCurrencyChanged);
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _change() async {
    final chosen = await showCurrencyPicker(context, dismissible: true);
    if (chosen == null || !mounted) return;

    try {
      await CurrencyService.instance.setPreferredCurrency(chosen);
      // Notifie tous les écrans à l'écoute (dont la Boutique si déjà
      // ouverte) — voir PreferredCurrencyNotifier.
      PreferredCurrencyNotifier.instance.set(chosen);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LocaleScope.of(context).t('common_network_error'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;
    final currency = PreferredCurrencyNotifier.instance.currency;

    return ThemedCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('shop_currency_title'),
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: theme.textOnBackground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _currencyDisplayLabel(context, currency, _options),
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    color: theme.textOnBackgroundMuted,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: _change, child: Text(t('common_edit'))),
        ],
      ),
    );
  }
}
