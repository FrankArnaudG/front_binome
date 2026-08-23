import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../theme/theme_scope.dart';
import '../../../widgets/themed_card.dart';
import '../privacy_policy_screen.dart';
import 'contact_dialog.dart';

/// "À propos" — version de l'app, politique de confidentialité et support
/// technique.
class AboutCard extends StatelessWidget {
  const AboutCard({super.key});

  void _showPrivacyPolicy(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
    );
  }

  void _showContact(BuildContext context) => showContactDialog(context);

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return ThemedCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(t('about_title'), style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: theme.textOnBackground)),
            ),
          ),
          ListTile(
            leading: Icon(Icons.privacy_tip_outlined, color: theme.primary),
            title: Text(t('about_privacy'), style: GoogleFonts.nunito(fontSize: 14, color: theme.textOnBackground)),
            trailing: Icon(Icons.chevron_right_rounded, color: theme.textOnBackgroundMuted),
            onTap: () => _showPrivacyPolicy(context),
          ),
          ListTile(
            leading: Icon(Icons.mail_outline_rounded, color: theme.primary),
            title: Text(t('about_support'), style: GoogleFonts.nunito(fontSize: 14, color: theme.textOnBackground)),
            trailing: Icon(Icons.chevron_right_rounded, color: theme.textOnBackgroundMuted),
            onTap: () => _showContact(context),
          ),
          ListTile(
            leading: Icon(Icons.info_outline_rounded, color: theme.textOnBackgroundMuted),
            title: Text(t('about_version'), style: GoogleFonts.nunito(fontSize: 14, color: theme.textOnBackground)),
            trailing: Text('1.0.0', style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted)),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
