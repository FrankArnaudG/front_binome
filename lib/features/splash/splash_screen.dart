import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/app_router.dart';
import '../../theme/app_colors.dart';
import '../../widgets/binome_wordmark.dart';
import '../auth/auth_service.dart';
import '../box/box_service.dart';
import '../onboarding/onboarding_screen.dart';

/// Écran de démarrage — le temps de restaurer la session (voir
/// _checkSession), avant de savoir où envoyer la personne. Reprend
/// l'habillage de l'accueil (voir HeroPage : même photo, même fond sombre)
/// plutôt qu'un logo isolé qui pulse — le "Binome" central (déjà "coupé"
/// par le cœur au milieu du mot, voir BinomeWordmark) et les points de
/// chargement en dessous suffisent à signaler l'attente.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _dotsController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    // Démarrage instantané : session + Box connues en local et Box active →
    // on ouvre l'app tout de suite (pas d'attente de deux appels réseau
    // successifs), puis on revérifie tout en arrière-plan.
    final cachedUser = await AuthService.instance.cachedUserIfLoggedIn();
    final cachedBox = cachedUser == null ? null : await BoxService.instance.loadCached();
    if (!mounted) return;
    if (cachedUser != null &&
        !cachedUser.needsProfileCompletion &&
        cachedBox != null &&
        !cachedBox.isDissolved &&
        !cachedBox.isWaiting) {
      AppRouter.routeAfterAuth(context, cachedUser, cachedBox);
      unawaited(_revalidateInBackground());
      return;
    }

    final user = await AuthService.instance.restoreSession();
    if (!mounted) return;

    if (user == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      );
      return;
    }

    // fetchCurrent() gère déjà ses propres erreurs réseau en retombant sur
    // la Box en cache (voir BoxService) — pas besoin de catchError ici.
    final box = await BoxService.instance.fetchCurrent();
    if (!mounted) return;
    AppRouter.routeAfterAuth(context, user, box);
  }

  /// Après un démarrage sur cache : session invalide (401) → retour à
  /// l'accueil ; sinon la Box (et donc l'écran) se met à jour toute seule.
  Future<void> _revalidateInBackground() async {
    final user = await AuthService.instance.restoreSession();
    if (user == null) {
      AppRouter.navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        (_) => false,
      );
      return;
    }
    await BoxService.instance.fetchCurrent();
  }

  @override
  void dispose() {
    _dotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/hero_couple.jpg',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(color: AppColors.navy),
          ),
          // Voile uniforme (pas le dégradé haut-transparent de HeroPage,
          // pensé pour un texte ancré en bas) — le contenu est ici centré,
          // il lui faut du contraste sur toute la hauteur de la photo.
          Container(color: Colors.black.withValues(alpha: 0.55)),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BinomeWordmark(fontSize: 36),
                const SizedBox(height: 24),
                _LoadingDots(controller: _dotsController),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Trois points en vague — décalés d'1/3 de cycle chacun (voir [_phase]),
/// classique indicateur "ça charge" sans texte à traduire.
class _LoadingDots extends StatelessWidget {
  final AnimationController controller;

  const _LoadingDots({required this.controller});

  double _phase(int index) => (controller.value + index * (1 / 3)) % 1.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final wave = (sin(_phase(index) * 2 * pi) + 1) / 2; // 0..1
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Opacity(
                opacity: 0.35 + 0.65 * wave,
                child: Transform.scale(
                  scale: 0.6 + 0.4 * wave,
                  child: const _Dot(),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
    );
  }
}
