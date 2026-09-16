import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/locale_scope.dart';
import '../../theme/theme_scope.dart';

/// Récapitulatif avant paiement (voir demande utilisateur : "tu fait sortir
/// un modele et tu recapitule... faire savoir que le paiement se fera en
/// FCFA et donner l'équivalent... si je clique sur continuer ça tourne
/// (loader) et la page yenga s'affiche") — partagé entre ShopScreen et
/// SubscriptionScreen (même besoin exact dans les deux).
class PaymentConfirmSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final String xofAmountLabel;
  // Équivalent dans la devise choisie par l'utilisateur (voir demande
  // utilisateur : "completer par le symbole sensiblement egale a et on
  // ajoute le montant en euro ou dans la devise demandée") — `null` quand
  // cette devise est déjà XOF (l'équivalence serait redondante).
  final String? approxAmountLabel;
  final Future<void> Function() onConfirm;

  const PaymentConfirmSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.xofAmountLabel,
    this.approxAmountLabel,
    required this.onConfirm,
  });

  @override
  State<PaymentConfirmSheet> createState() => _PaymentConfirmSheetState();
}

class _PaymentConfirmSheetState extends State<PaymentConfirmSheet> {
  bool _loading = false;

  Future<void> _confirm() async {
    setState(() => _loading = true);
    // onConfirm() gère lui-même ses erreurs (snackbar) — on ferme la feuille
    // dans tous les cas une fois l'appel terminé (succès : le navigateur
    // externe vient de s'ouvrir ; échec : le message d'erreur est déjà
    // affiché par l'écran appelant).
    await widget.onConfirm();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

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
              widget.title,
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: theme.textOnBackground),
            ),
            const SizedBox(height: 4),
            Text(
              widget.subtitle,
              style: GoogleFonts.nunito(fontSize: 14, color: theme.textOnBackgroundMuted),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 20, color: theme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.approxAmountLabel == null
                          ? t('shop_payment_xof_notice', {'amount': widget.xofAmountLabel})
                          : '${t('shop_payment_xof_notice', {'amount': widget.xofAmountLabel})} '
                              '(≈ ${widget.approxAmountLabel})',
                      style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackground, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        t('common_continue'),
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
