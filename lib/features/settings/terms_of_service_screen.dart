import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/locale_scope.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';

/// Document légal complet, référencé depuis LoginScreen ("Conditions
/// générales") — même structure que PrivacyPolicyScreen.
class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    Widget sectionTitle(String text) => Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 8),
          child: Text(
            text,
            style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: theme.textOnBackground),
          ),
        );

    Widget body(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            text,
            style: GoogleFonts.nunito(fontSize: 14, height: 1.6, color: theme.textOnBackgroundMuted),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(
          t('terms_title'),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              body(t('terms_last_update', {'year': DateTime.now().year.toString()})),

              sectionTitle(t('terms_s1_title')),
              body(t('terms_s1_body')),

              sectionTitle(t('terms_s2_title')),
              body(t('terms_s2_body')),

              sectionTitle(t('terms_s3_title')),
              body(t('terms_s3_body')),

              sectionTitle(t('terms_s4_title')),
              body(t('terms_s4_body')),

              sectionTitle(t('terms_s5_title')),
              body(t('terms_s5_body1')),
              body(t('terms_s5_body2')),

              sectionTitle(t('terms_s6_title')),
              body(t('terms_s6_body')),

              sectionTitle(t('terms_s7_title')),
              body(t('terms_s7_body')),

              sectionTitle(t('terms_s8_title')),
              body(t('terms_s8_body')),

              sectionTitle(t('terms_s9_title')),
              body(t('terms_s9_body')),

              sectionTitle(t('terms_s10_title')),
              body(t('terms_s10_body')),

              sectionTitle(t('terms_s11_title')),
              body(t('terms_s11_body')),

              sectionTitle(t('terms_s12_title')),
              body(t('terms_s12_body')),
            ],
          ),
        ),
      ),
    );
  }
}
