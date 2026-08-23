import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_locale.dart';
import '../../l10n/locale_scope.dart';
import '../../theme/app_colors.dart';
import '../../widgets/circle_nav_button.dart';
import '../auth/login_screen.dart';
import 'widgets/hero_page.dart';

/// Un seul écran d'accueil désormais (voir demande utilisateur : les pages
/// "Round 1"/mini-jeu et "Rien qu'à vous deux" ont été retirées) — la flèche
/// mène directement à la connexion, plus de PageView/indicateur à faire
/// avancer.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  void _goToLogin(BuildContext context) {
    // push (pas pushReplacement) : garde cet écran dans la pile pour
    // pouvoir y revenir en arrière depuis la connexion (voir demande
    // utilisateur) — LoginScreen affiche sa propre flèche retour pour ça.
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  /// Choix de la langue avant même la connexion — sinon la seule occasion
  /// de la changer était depuis Paramètres, une fois déjà connecté·e, ce qui
  /// laissait tout l'onboarding/la connexion en français par défaut pour
  /// qui ne lit pas cette langue.
  Future<void> _pickLanguage(BuildContext context) async {
    final controller = LocaleScope.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1B2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      // 12 langues sur 4 colonnes tiennent rarement dans la hauteur par
      // défaut d'une bottom sheet (surtout en paysage/petit écran) — sans
      // isScrollControlled + la contrainte de hauteur ci-dessous, le
      // contenu débordait silencieusement sous l'écran (voir capture
      // utilisateur : "BOTTOM OVERFLOWED BY 59 PIXELS").
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.75),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Text(
                  controller.t('language_title'),
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: Colors.white),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.62,
                    ),
                    itemCount: AppLocale.all.length,
                    itemBuilder: (context, index) {
                      final locale = AppLocale.all[index];
                      final selected = locale.code == controller.current.code;
                      return InkWell(
                        onTap: () {
                          controller.select(locale.code);
                          Navigator.of(sheetContext).pop();
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.08),
                                border: Border.all(color: selected ? AppColors.primary : Colors.transparent, width: 2.5),
                                boxShadow: selected
                                    ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 8)]
                                    : null,
                              ),
                              child: selected
                                  ? const Center(child: Icon(Icons.check_rounded, color: AppColors.primary, size: 18))
                                  : Center(child: Text(locale.flag, style: const TextStyle(fontSize: 18))),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              locale.name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.nunito(
                                fontSize: 9.5,
                                height: 1.15,
                                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                                color: selected ? AppColors.primary : Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: Stack(
        children: [
          const HeroPage(),
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: Material(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => _pickLanguage(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(LocaleScope.of(context).current.flag, style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 4),
                          const Icon(Icons.expand_more_rounded, color: Colors.white70, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 28,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: CircleNavButton(
                  icon: Icons.chevron_right_rounded,
                  onPressed: () => _goToLogin(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
