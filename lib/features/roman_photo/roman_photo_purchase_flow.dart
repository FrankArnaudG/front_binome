import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../l10n/locale_scope.dart';
import '../../theme/theme_scope.dart';
import '../shop/wallet_balance_notifier.dart';
import '../../widgets/coin_icon.dart';
import 'roman_photo_service.dart';
import 'roman_photo_story.dart';

/// Garantit qu'un tome payant est acheté avant de le télécharger (voir
/// demande utilisateur : "pour les bd payant, il faut d'abord confirmer
/// l'achat et ensuite télécharger") — no-op immédiat pour un tome gratuit ou
/// déjà acheté (voir RomanPhotoVolume.needsPurchase). Retourne `true` si le
/// téléchargement peut continuer (achat confirmé ou pas nécessaire), `false`
/// si annulé ou en échec (message déjà affiché dans ce cas).
Future<bool> ensureRomanPhotoVolumePurchased(BuildContext context, RomanPhotoVolume volume) async {
  if (!volume.needsPurchase) return true;

  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _PurchaseConfirmDialog(volume: volume),
  );
  if (confirmed != true || !context.mounted) return false;

  try {
    await RomanPhotoService.instance.purchaseVolume(volume.id);
    await WalletBalanceNotifier.instance.refresh();
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    final message = e is ApiException ? e.message : LocaleScope.of(context).t('roman_photo_purchase_error');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    return false;
  }
}

class _PurchaseConfirmDialog extends StatelessWidget {
  final RomanPhotoVolume volume;

  const _PurchaseConfirmDialog({required this.volume});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;
    final localeCode = LocaleScope.of(context).current.code;

    return AlertDialog(
      backgroundColor: theme.surface,
      title: Text(
        t('roman_photo_purchase_title'),
        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            volume.titleFor(localeCode),
            style: GoogleFonts.nunito(fontWeight: FontWeight.w700, color: theme.textOnBackground),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const CoinIcon(size: 18),
              const SizedBox(width: 6),
              // Flexible + ellipsis : phrase traduite avec un prix
              // interpolé, pas de longueur garantie selon la langue.
              Flexible(
                child: Text(
                  t('roman_photo_purchase_price', {'price': '${volume.coinPrice}'}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t('common_cancel'), style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(backgroundColor: theme.primary, foregroundColor: Colors.white),
          child: Text(t('roman_photo_purchase_confirm')),
        ),
      ],
    );
  }
}
