import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../photo_vault_service.dart';

/// Affiché à la place d'une photo du Jardin secret dont le fichier a
/// disparu du serveur (voir ExpireBoxPhotos/BoxPhotoController::markViewed
/// côté backend) — jamais un simple échec réseau générique : ce cas précis
/// a une action possible (prévenir qui a envoyé), contrairement à une vraie
/// coupure de connexion où retenter suffit. Best-effort et sans état
/// "déjà demandé" : renvoyer la requête plusieurs fois reste sans danger
/// (juste une notification de plus côté serveur), pas besoin de complexifier
/// pour l'éviter.
class ExpiredPhotoButton extends StatelessWidget {
  final String photoId;
  final bool compact;

  const ExpiredPhotoButton({super.key, required this.photoId, this.compact = false});

  Future<void> _requestResend(BuildContext context) async {
    final t = LocaleScope.of(context).t;
    try {
      await PhotoVaultService.instance.requestResend(photoId);
    } catch (_) {
      // best effort — la notification est un bonus, pas une garantie.
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t('vault_resend_requested_snackbar'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = LocaleScope.of(context).t;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.hourglass_disabled_rounded,
          color: compact ? Colors.white70 : Colors.white54,
          size: compact ? 20 : 40,
        ),
        SizedBox(height: compact ? 4 : 10),
        Text(
          t('vault_photo_expired'),
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(
            fontSize: compact ? 10 : 13,
            color: Colors.white70,
          ),
        ),
        SizedBox(height: compact ? 4 : 12),
        compact
            ? IconButton(
                onPressed: () => _requestResend(context),
                icon: const Icon(Icons.replay_rounded, size: 16, color: Colors.white),
                tooltip: t('vault_resend_button'),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
              )
            : OutlinedButton.icon(
                onPressed: () => _requestResend(context),
                icon: const Icon(Icons.replay_rounded, size: 18, color: Colors.white),
                label: Text(t('vault_resend_button'), style: const TextStyle(color: Colors.white)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white54)),
              ),
      ],
    );
  }
}
