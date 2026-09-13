import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/theme_palette.dart';
import '../game_service.dart';

/// Petit encart informatif sous l'option "À distance" (voir demande
/// utilisateur) — rappelle ce que permet ce mode (jouer en temps réel avec
/// son/sa partenaire où qu'il/elle soit, tout en communiquant par message,
/// audio ou vidéo) ET son coût réel en pièces, calculé depuis le VRAI
/// réglage admin (voir GameService.fetchGameEconomyRate) plutôt qu'une
/// valeur codée en dur qui se désynchroniserait dès qu'un admin ajuste le
/// taux.
class RemoteBillingInfo extends StatefulWidget {
  final ThemePalette theme;

  const RemoteBillingInfo({super.key, required this.theme});

  @override
  State<RemoteBillingInfo> createState() => _RemoteBillingInfoState();
}

class _RemoteBillingInfoState extends State<RemoteBillingInfo> {
  Map<String, int>? _rate;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rate = await GameService.instance.fetchGameEconomyRate();
      if (mounted) setState(() => _rate = rate);
    } catch (_) {
      // Best-effort — hors ligne ou serveur indisponible : l'écran reste
      // utilisable, juste sans ce détail de coût affiché.
    }
  }

  String _formatMinutes(int totalMinutes) {
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours <= 0) return '${minutes}min';
    if (minutes == 0) return '${hours}h';
    return '${hours}h${minutes.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final rate = _rate;
    final theme = widget.theme;

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 8, bottom: 6),
      decoration: BoxDecoration(
        color: theme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.public_rounded, size: 18, color: theme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Jouez en temps réel avec votre partenaire, où qu'il/elle soit dans le monde — vous pouvez aussi vous parler par message, audio ou vidéo pendant la partie.",
                  style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                ),
                if (rate != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Facturé au temps de jeu : 1 pièce = ${rate['minutes_per_coin']} min '
                    '(15 pièces ≈ ${_formatMinutes(15 * (rate['minutes_per_coin'] ?? 8))})',
                    style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: theme.primary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
