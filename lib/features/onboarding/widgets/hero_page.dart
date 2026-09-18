import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/binome_wordmark.dart';

/// Première page d'onboarding : photo plein écran + accroche, comme un
/// vrai écran hero plutôt qu'une illustration.
class HeroPage extends StatelessWidget {
  const HeroPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = LocaleScope.of(context).t;

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/hero_couple.jpg',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(color: AppColors.navy),
        ),
        DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: AppColors.heroOverlay,
              stops: [0.3, 1],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                const Center(child: BinomeWordmark(fontSize: 26)),
                const Spacer(),
                Text(
                  t('onboarding_hero_title'),
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  t('onboarding_hero_subtitle'),
                  // Manuscrite plutôt que Poppins — reprend la même famille
                  // que le nouveau logo cursif (voir demande utilisateur) et
                  // que les Poèmes-Slides (voir SlideController::FONTS,
                  // même police "Dancing Script"), pour une identité
                  // cohérente plutôt qu'une police de plus.
                  style: GoogleFonts.dancingScript(
                    color: AppColors.primary,
                    // Une police manuscrite paraît plus petite qu'une
                    // sans-serif grasse à taille égale (moins de masse
                    // visuelle) — 30 semblait trop discret à côté de "VOTRE
                    // MONDE" (voir capture utilisateur), remonté à 40.
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 110),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
