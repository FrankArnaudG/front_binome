import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/locale_scope.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';

/// Document légal complet — remplace le résumé provisoire affiché depuis
/// AboutCard tant que celui-ci n'était pas encore rédigé.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

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

    Widget subTitle(String text) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            text,
            style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w700, color: theme.textOnBackground),
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
          t('privacy_title'),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              body(t('privacy_last_update', {'year': DateTime.now().year.toString()})),

              sectionTitle(t('privacy_s1_title')),
              body(t('privacy_s1_body1')),
              body(t('privacy_s1_body2')),

              sectionTitle(t('privacy_s2_title')),
              subTitle(t('privacy_s2_sub1_title')),
              body(t('privacy_s2_sub1_body')),
              subTitle(t('privacy_s2_sub2_title')),
              body(t('privacy_s2_sub2_body')),
              subTitle(t('privacy_s2_sub3_title')),
              body(t('privacy_s2_sub3_body')),
              subTitle(t('privacy_s2_sub4_title')),
              body(t('privacy_s2_sub4_body')),
              subTitle(t('privacy_s2_sub5_title')),
              body(t('privacy_s2_sub5_body')),
              subTitle(t('privacy_s2_sub6_title')),
              body(t('privacy_s2_sub6_body')),

              sectionTitle(t('privacy_s3_title')),
              body(t('privacy_s3_bullet1')),
              body(t('privacy_s3_bullet2')),
              body(t('privacy_s3_bullet3')),
              body(t('privacy_s3_bullet4')),
              body(t('privacy_s3_bullet5')),
              body(t('privacy_s3_note')),

              sectionTitle(t('privacy_s4_title')),
              body(t('privacy_s4_intro')),
              body(t('privacy_s4_bullet1')),
              body(t('privacy_s4_bullet2')),
              body(t('privacy_s4_bullet3')),
              body(t('privacy_s4_note')),

              sectionTitle(t('privacy_s5_title')),
              body(t('privacy_s5_body')),

              sectionTitle(t('privacy_s6_title')),
              body(t('privacy_s6_intro')),
              body(t('privacy_s6_bullet1')),
              body(t('privacy_s6_bullet2')),
              body(t('privacy_s6_bullet3')),

              sectionTitle(t('privacy_s7_title')),
              body(t('privacy_s7_body')),

              sectionTitle(t('privacy_s8_title')),
              body(t('privacy_s8_body')),
            ],
          ),
        ),
      ),
    );
  }
}
