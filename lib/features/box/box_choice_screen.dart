import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../core/app_router.dart';
import '../../models/app_user.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/asset_or_fallback.dart';
import '../../widgets/binome_wordmark.dart';
import '../../widgets/primary_button.dart';
import 'box_service.dart';
import 'widgets/box_hero_fallback.dart';

class BoxChoiceScreen extends StatefulWidget {
  final AppUser user;

  const BoxChoiceScreen({super.key, required this.user});

  @override
  State<BoxChoiceScreen> createState() => _BoxChoiceScreenState();
}

class _BoxChoiceScreenState extends State<BoxChoiceScreen> {
  final _codeController = TextEditingController();
  bool _creating = false;
  bool _joining = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createBox() async {
    setState(() => _creating = true);
    try {
      final box = await BoxService.instance.createBox();
      if (!mounted) return;
      AppRouter.toBoxWaiting(context, widget.user, box, replace: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _joinBox() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      _showError('Entre le code de la Box de ton/ta partenaire.');
      return;
    }

    setState(() => _joining = true);
    try {
      await BoxService.instance.joinBox(code);
      if (!mounted) return;
      AppRouter.toHome(context, widget.user, replace: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      drawer: AppDrawer(user: widget.user),
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        elevation: 0,
        centerTitle: true,
        title: const BinomeWordmark(fontSize: 20),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              const AssetOrFallback(
                assetPath: 'assets/images/pairing_phones.png',
                fallback: BoxHeroFallback(),
              ),
              const SizedBox(height: 28),
              Text(
                'Connecte-toi avec\nton/ta partenaire',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 10),
              Text(
                "*Pour générer l'ID de la Box",
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(fontSize: 13, color: AppColors.textOnNavyMuted),
              ),
              const SizedBox(height: 36),
              PrimaryButton(label: 'Créer une Box', loading: _creating, onPressed: _createBox),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(child: Divider(color: AppColors.textOnNavyMuted)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('OU', style: GoogleFonts.nunito(color: AppColors.textOnNavyMuted)),
                  ),
                  const Expanded(child: Divider(color: AppColors.textOnNavyMuted)),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _codeController,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                maxLength: 5,
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 4),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'XXXXX',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _joining ? null : _joinBox,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
                child: _joining
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text('Rejoindre la Box'),
              ),
              const SizedBox(height: 10),
              Text(
                "Saisis l'ID de la Box du partenaire",
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(fontSize: 13, color: AppColors.textOnNavyMuted),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
