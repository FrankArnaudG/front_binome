import 'package:flutter/material.dart';

import '../../core/app_router.dart';
import '../auth/auth_service.dart';
import '../box/box_service.dart';
import '../onboarding/onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final Animation<double> _pulse = Tween<double>(begin: 0.9, end: 1.08).animate(
    CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
  );

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
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

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ScaleTransition(
          scale: _pulse,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Image.asset(
              'assets/logo/binome_logo.png',
              width: 140,
              height: 140 * 1024 / 1536,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}
