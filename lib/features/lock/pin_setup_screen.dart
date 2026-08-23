import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/pin_storage.dart';
import '../../theme/app_colors.dart';
import 'widgets/pin_dots.dart';
import 'widgets/pin_keypad.dart';

/// Création (ou modification) du code PIN — saisie en deux temps
/// (nouveau code puis confirmation). Enregistre le code et renvoie `true`
/// via [Navigator.pop] en cas de succès.
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  String _first = '';
  String _current = '';
  bool _confirming = false;
  String? _error;

  Future<void> _onDigit(String d) async {
    if (_current.length >= 6) return;
    setState(() {
      _current += d;
      _error = null;
    });

    if (_current.length != 6) return;

    if (!_confirming) {
      setState(() {
        _first = _current;
        _current = '';
        _confirming = true;
      });
      return;
    }

    if (_current == _first) {
      await PinStorage.instance.setPin(_current);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _error = 'Les codes ne correspondent pas, réessayez';
        _current = '';
        _confirming = false;
        _first = '';
      });
    }
  }

  void _onBackspace() {
    if (_current.isEmpty) return;
    setState(() => _current = _current.substring(0, _current.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blush,
      appBar: AppBar(
        backgroundColor: AppColors.blush,
        elevation: 0,
        foregroundColor: AppColors.textOnBlush,
        title: Text(
          _confirming ? 'Confirme le code' : 'Crée un code',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: AppColors.textOnBlush),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded, size: 40, color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                _confirming ? 'Ressaisis le code pour confirmer' : 'Choisis un code à 6 chiffres',
                style: GoogleFonts.nunito(color: AppColors.textOnBlushMuted, fontSize: 14),
              ),
              const SizedBox(height: 24),
              PinDotsOnBlush(filled: _current.length),
              const SizedBox(height: 12),
              SizedBox(
                height: 20,
                child: _error != null ? Text(_error!, style: GoogleFonts.nunito(color: Colors.redAccent, fontSize: 13)) : null,
              ),
              const SizedBox(height: 24),
              PinKeypad(color: AppColors.textOnBlush, onDigit: _onDigit, onBackspace: _onBackspace),
            ],
          ),
        ),
      ),
    );
  }
}
