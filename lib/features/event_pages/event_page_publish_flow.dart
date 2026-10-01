import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../theme/theme_scope.dart';
import '../../widgets/coin_icon.dart';
import '../shop/wallet_balance_notifier.dart';
import 'event_page.dart';
import 'event_page_service.dart';

/// Confirme la publication d'une page événement — débite le tarif fixe
/// courant côté backend (voir EventPagePublishController::publish). Même
/// gabarit que ensureRomanPhotoVolumePurchased : dialog de confirmation
/// avec le prix, puis POST, puis SnackBar en cas d'erreur (solde
/// insuffisant par ex., message déjà localisé côté serveur).
Future<EventPage?> runEventPagePublishFlow(BuildContext context, EventPage page) async {
  double fee;
  try {
    fee = await EventPageService.instance.fetchPublishFee();
  } catch (_) {
    fee = 0;
  }
  if (!context.mounted) return null;

  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _PublishConfirmDialog(fee: fee, alreadyPublished: page.isPublished),
  );
  if (confirmed != true || !context.mounted) return null;

  try {
    final published = await EventPageService.instance.publish(page.id);
    await WalletBalanceNotifier.instance.refresh();
    if (!context.mounted) return published;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Page événement publiée !')));
    return published;
  } catch (e) {
    if (!context.mounted) return null;
    final message = e is ApiException ? e.message : 'Une erreur est survenue.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    return null;
  }
}

class _PublishConfirmDialog extends StatelessWidget {
  final double fee;
  final bool alreadyPublished;

  const _PublishConfirmDialog({required this.fee, required this.alreadyPublished});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);

    return AlertDialog(
      backgroundColor: theme.surface,
      title: Text(
        alreadyPublished ? 'Mettre à jour la page publique' : 'Publier la page événement',
        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
      ),
      content: alreadyPublished
          ? Text(
              'Cette page est déjà publiée — la mise à jour est gratuite, le lien reste le même.',
              style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ta page sera visible par n\'importe qui via un lien public, même sans compte.',
                  style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const CoinIcon(size: 18),
                    const SizedBox(width: 6),
                    Text('${fee.toStringAsFixed(fee == fee.roundToDouble() ? 0 : 2)} pièces',
                        style: GoogleFonts.nunito(fontWeight: FontWeight.w700, color: theme.textOnBackground)),
                  ],
                ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Annuler', style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(backgroundColor: theme.primary, foregroundColor: Colors.white),
          child: Text(alreadyPublished ? 'Mettre à jour' : 'Publier'),
        ),
      ],
    );
  }
}
