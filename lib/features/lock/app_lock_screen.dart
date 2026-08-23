import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/app_router.dart';
import '../../core/pin_storage.dart';
import '../../theme/app_colors.dart';
import '../../widgets/binome_wordmark.dart';
import '../auth/auth_service.dart';
import 'widgets/pin_dots.dart';
import 'widgets/pin_keypad.dart';

/// Écran de verrouillage affiché à chaque ouverture de l'app quand un code
/// PIN a été défini (voir [PinStorage]/Paramètres). Purement local — ne
/// contacte jamais le backend, sauf via "Code oublié ?" qui déconnecte
/// l'utilisateur pour forcer une reconnexion Google (preuve d'identité).
class AppLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const AppLockScreen({super.key, required this.onUnlocked});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  String _pin = '';
  String? _error;
  bool _checking = false;

  Future<void> _onDigit(String d) async {
    if (_pin.length >= 6 || _checking) return;
    setState(() {
      _pin += d;
      _error = null;
    });

    if (_pin.length == 6) {
      setState(() => _checking = true);
      final ok = await PinStorage.instance.verify(_pin);
      if (!mounted) return;
      if (ok) {
        widget.onUnlocked();
      } else {
        setState(() {
          _error = 'Code incorrect';
          _pin = '';
          _checking = false;
        });
      }
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _forgotPin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Code oublié ?'),
        content: const Text(
          'Tu vas être déconnecté·e et devras te reconnecter avec Google pour réinitialiser ton code de verrouillage.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Réinitialiser')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await PinStorage.instance.clear();
    await AuthService.instance.signOut();
    if (!mounted) return;
    AppRouter.toLogin(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_rounded, color: Colors.white, size: 36),
              const SizedBox(height: 16),
              const BinomeWordmark(fontSize: 22),
              const SizedBox(height: 10),
              Text('Entre ton code', style: GoogleFonts.nunito(color: AppColors.textOnNavyMuted, fontSize: 14)),
              const SizedBox(height: 24),
              PinDots(filled: _pin.length),
              const SizedBox(height: 12),
              SizedBox(
                height: 20,
                child: _error != null ? Text(_error!, style: GoogleFonts.nunito(color: Colors.redAccent, fontSize: 13)) : null,
              ),
              const SizedBox(height: 24),
              PinKeypad(onDigit: _onDigit, onBackspace: _onBackspace),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _forgotPin,
                child: Text('Code oublié ?', style: GoogleFonts.nunito(color: AppColors.textOnNavyMuted, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
