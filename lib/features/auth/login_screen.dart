import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../core/app_router.dart';
import '../../l10n/locale_scope.dart';
import '../../theme/app_colors.dart';
import '../../widgets/asset_or_fallback.dart';
import '../../widgets/binome_wordmark.dart';
import '../box/box_service.dart';
import '../settings/privacy_policy_screen.dart';
import '../settings/terms_of_service_screen.dart';
import 'auth_service.dart';
import 'widgets/google_logo_painter.dart';
import 'widgets/login_hero_fallback.dart';

enum _PromoCodeState { idle, checking, valid, invalid }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;
  bool _showPromoField = false;
  String? _error;
  final _promoCodeController = TextEditingController();
  _PromoCodeState _promoCodeState = _PromoCodeState.idle;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _promoCodeController.dispose();
    super.dispose();
  }

  /// Vérifie en temps réel que le code correspond à un partenaire approuvé
  /// (voir PartnerController::validateReferralCode, endpoint public — cet
  /// écran s'utilise avant toute authentification). Un champ vide n'est
  /// jamais bloquant, un code invalide grise le bouton Google.
  void _onPromoCodeChanged(String value) {
    _debounce?.cancel();
    final code = value.trim();
    if (code.isEmpty) {
      setState(() => _promoCodeState = _PromoCodeState.idle);
      return;
    }
    setState(() => _promoCodeState = _PromoCodeState.checking);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final data =
            await ApiClient.instance.get(
                  '/partner/promo-code/validate?code=${Uri.encodeQueryComponent(code)}',
                )
                as Map<String, dynamic>;
        if (!mounted || _promoCodeController.text.trim() != code) return;
        setState(() {
          _promoCodeState = (data['valid'] as bool)
              ? _PromoCodeState.valid
              : _PromoCodeState.invalid;
        });
      } catch (_) {
        if (mounted) setState(() => _promoCodeState = _PromoCodeState.idle);
      }
    });
  }

  bool get _canSignIn {
    if (_loading) return false;
    if (_promoCodeController.text.trim().isEmpty) return true;
    return _promoCodeState == _PromoCodeState.valid;
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = await AuthService.instance.signInWithGoogle(
        promoCode: _promoCodeController.text,
      );
      if (!mounted) return;

      if (user == null) {
        // Connexion annulée par l'utilisateur.
        setState(() => _loading = false);
        return;
      }

      final box = await BoxService.instance.fetchCurrent();
      if (!mounted) return;
      AppRouter.routeAfterAuth(context, user, box);
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = LocaleScope.of(context).t('login_signin_error');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LocaleScope.of(context).t;

    return Scaffold(
      backgroundColor: AppColors.navy,
      body: Column(
        children: [
          Expanded(
            flex: 11,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AssetOrFallback(
                  assetPath: 'assets/images/login_couple.png',
                  fit: BoxFit.cover,
                  fallback: const LoginHeroFallback(),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: BinomeWordmark(fontSize: 24),
                    ),
                  ),
                ),
                // Retour vers l'onboarding — n'apparaît que si on y est
                // réellement arrivé·e depuis là (voir demande utilisateur),
                // jamais après une déconnexion (voir AppRouter.toLogin, qui
                // vide toute la pile).
                if (Navigator.of(context).canPop())
                  // Positioned indispensable ici : le Stack ambiant est en
                  // StackFit.expand (voir AssetOrFallback juste au-dessus,
                  // qui doit couvrir toute la photo) — un enfant NON
                  // positionné est alors étiré à la taille entière du
                  // Stack, et CircleBorder dessinait un cercle géant sur
                  // toute cette zone au lieu d'un petit bouton (voir
                  // capture utilisateur).
                  Positioned(
                    top: 0,
                    left: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12, top: 4),
                        child: Material(
                          color: Colors.white.withValues(alpha: 0.12),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => Navigator.of(context).pop(),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 9,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 20),
              decoration: const BoxDecoration(
                color: AppColors.blush,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text.rich(
                      TextSpan(
                        style: GoogleFonts.poppins(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textOnBlush,
                          height: 1.25,
                        ),
                        children: [
                          TextSpan(text: t('login_tagline_part1')),
                          TextSpan(
                            text: t('login_tagline_highlight1'),
                            style: const TextStyle(color: AppColors.primary),
                          ),
                          TextSpan(text: t('login_tagline_part2')),
                          const TextSpan(
                            text: 'Binomes',
                            style: TextStyle(color: AppColors.primary),
                          ),
                          TextSpan(text: t('login_tagline_part3')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (_showPromoField) ...[
                      TextField(
                        controller: _promoCodeController,
                        textCapitalization: TextCapitalization.characters,
                        onChanged: _onPromoCodeChanged,
                        decoration: InputDecoration(
                          labelText: t('login_promo_hint'),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          suffixIcon: switch (_promoCodeState) {
                            _PromoCodeState.checking => const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                            _PromoCodeState.valid => const Icon(
                              Icons.check_circle,
                              color: Color(0xFF2E9E5B),
                            ),
                            _PromoCodeState.invalid => const Icon(
                              Icons.cancel,
                              color: Color(0xFFC0294A),
                            ),
                            _PromoCodeState.idle => null,
                          },
                        ),
                      ),
                      if (_promoCodeState == _PromoCodeState.invalid) ...[
                        const SizedBox(height: 6),
                        Text(
                          t('login_promo_invalid'),
                          style: GoogleFonts.nunito(
                            fontSize: 13,
                            color: const Color(0xFFC0294A),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                    ] else ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () =>
                              setState(() => _showPromoField = true),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            t('login_promo_link'),
                            style: GoogleFonts.nunito(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: const TextStyle(color: Color(0xFFC0294A)),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _canSignIn ? _handleGoogleSignIn : null,
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                    ),
                                    child: const GoogleLogo(size: 16),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(t('login_google_button')),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text.rich(
                      TextSpan(
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          color: AppColors.textOnBlushMuted,
                          height: 1.4,
                        ),
                        children: [
                          TextSpan(text: t('login_terms_prefix')),
                          TextSpan(
                            text: t('login_terms_privacy_label'),
                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                                  ),
                          ),
                          TextSpan(text: t('login_terms_middle')),
                          TextSpan(
                            text: t('login_terms_terms_label'),
                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const TermsOfServiceScreen()),
                                  ),
                          ),
                          TextSpan(text: t('login_terms_suffix')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
