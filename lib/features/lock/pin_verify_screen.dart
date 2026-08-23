import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/pin_storage.dart';
import '../../theme/app_colors.dart';
import 'widgets/pin_dots.dart';
import 'widgets/pin_keypad.dart';

/// Demande le code PIN existant (avant de le désactiver ou de le changer),
/// et renvoie `true` via [Navigator.pop] en cas de succès.
class PinVerifyScreen extends StatefulWidget {
  final String title;

  const PinVerifyScreen({super.key, this.title = 'Entre ton code actuel'});

  @override
  State<PinVerifyScreen> createState() => _PinVerifyScreenState();
}

class _PinVerifyScreenState extends State<PinVerifyScreen> {
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
        Navigator.of(context).pop(true);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blush,
      appBar: AppBar(
        backgroundColor: AppColors.blush,
        elevation: 0,
        foregroundColor: AppColors.textOnBlush,
        title: Text(widget.title, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: AppColors.textOnBlush)),
      ),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PinDotsOnBlush(filled: _pin.length),
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
