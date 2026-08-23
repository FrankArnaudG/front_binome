import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../../l10n/locale_scope.dart';
import '../../../models/box.dart';
import '../../../theme/theme_scope.dart';
import '../../../widgets/themed_card.dart';

/// "Gestion du Jumelage" — affiche le code de la Box et permet de le
/// partager à nouveau (utile si le/la partenaire doit réinstaller l'app).
/// La rupture de lien reste dans la Zone dangereuse ([DangerZoneCard]).
class BoxManagementCard extends StatelessWidget {
  final Box box;
  final String? partnerName;

  const BoxManagementCard({super.key, required this.box, this.partnerName});

  void _shareCode(String Function(String, [Map<String, String>?]) t) {
    Share.share(t('invite_share_text', {'code': box.code}));
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return ThemedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('box_management_title'), style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: theme.textOnBackground)),
          const SizedBox(height: 4),
          Text(
            box.isActive ? t('box_management_subtitle', {'name': partnerName ?? ''}) : t('box_management_waiting'),
            style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.primary.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    box.code,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 4, color: theme.primary),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: () => _shareCode(t),
                style: IconButton.styleFrom(backgroundColor: theme.primary),
                icon: const Icon(Icons.ios_share_rounded, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
