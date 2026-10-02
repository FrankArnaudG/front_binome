import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/theme_palette.dart';

/// Carte persistante sous le bouton "Reprendre" quand la pause est due à un
/// solde de pièces épuisé — voir demande utilisateur : "écrire en dessous
/// du bouton pour faire passer le message, tu peux t'inspirer de quand on
/// envoie une demande pour rejoindre le jeu et que le binôme n'est pas
/// connecté" (voir le bandeau "Ton binôme n'est pas en ligne" dans
/// GameInviteWaitingScreen, repris ici à l'identique).
class GameWalletDepletedNotice extends StatelessWidget {
  final ThemePalette theme;

  const GameWalletDepletedNotice({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 18, color: theme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Solde de pièces épuisé.',
                    style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w800, color: theme.textOnBackground),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Recharge des pièces ou abonne-toi pour que n'importe qui puisse reprendre la partie.",
                    style: GoogleFonts.nunito(fontSize: 12.5, height: 1.35, color: theme.textOnBackgroundMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
