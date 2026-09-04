import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/locale_scope.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import 'currency_service.dart';

/// Ouvre le sélecteur de devise et retourne le code choisi (ou `null` si
/// annulé) — réutilisé par la Boutique (premier achat) et les Paramètres
/// (modification ultérieure). La liste vient de l'admin (activer/désactiver
/// des devises), pas d'une liste figée côté app. Une confirmation est
/// demandée avant de valider (voir [_CurrencyTile]) car une erreur de
/// sélection change directement ce que l'utilisateur paie ensuite.
Future<String?> showCurrencyPicker(BuildContext context, {bool dismissible = false}) {
  final theme = ThemeScope.paletteOf(context);

  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: theme.surface,
    isDismissible: dismissible,
    enableDrag: dismissible,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: const _CurrencyPickerSheet(),
    ),
  );
}

class _CurrencyPickerSheet extends StatefulWidget {
  const _CurrencyPickerSheet();

  @override
  State<_CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

class _CurrencyPickerSheetState extends State<_CurrencyPickerSheet> {
  late Future<List<CurrencyOption>> _future;

  @override
  void initState() {
    super.initState();
    _future = CurrencyService.instance.fetchAvailableCurrencies();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('currency_picker_title'), style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: theme.textOnBackground)),
            const SizedBox(height: 4),
            Text(
              t('currency_picker_subtitle'),
              style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: FutureBuilder<List<CurrencyOption>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final options = snapshot.data ?? [];
                  if (snapshot.hasError || options.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        t('currency_load_error'),
                        style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: options.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _CurrencyTile(option: options[index], theme: theme),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Code ISO accompagné de son symbole quand il en existe un et diffère du
/// code lui-même (ex. `$ USD`, `€ EUR`) — sinon juste le code (ex. `XOF`).
String _currencyLabel(String currencyCode) {
  final symbol = currencySymbol(currencyCode);
  return symbol == currencyCode ? currencyCode : '$symbol $currencyCode';
}

class _CurrencyTile extends StatelessWidget {
  final CurrencyOption option;
  final ThemePalette theme;

  const _CurrencyTile({required this.option, required this.theme});

  /// Redemande confirmation avant de fermer le sélecteur — un tap malheureux
  /// changerait directement la devise dans laquelle l'utilisateur paie.
  Future<void> _confirmAndSelect(BuildContext context) async {
    final t = LocaleScope.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('currency_confirm_title')),
        content: Text(
          t('currency_confirm_body', {
            'label': option.label ?? option.currency,
            'code': option.currency,
          }),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t('common_cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(t('common_confirm'))),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      Navigator.of(context).pop(option.currency);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _confirmAndSelect(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: (theme.isDark ? Colors.white : Colors.black).withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Icon(Icons.payments_rounded, color: theme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option.label ?? option.currency, style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w600, color: theme.textOnBackground)),
                    if (option.country != null)
                      Text(option.country!, style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted)),
                  ],
                ),
              ),
              // Flexible + ellipsis : libellé de devise potentiellement long
              // (voir option.currency, source admin) sans limite de largeur
              // sinon, à côté d'un Expanded qui prend déjà le plus de place.
              Flexible(
                child: Text(
                  _currencyLabel(option.currency),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
