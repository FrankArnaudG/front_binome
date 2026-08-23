import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api_client.dart';
import '../../../l10n/locale_scope.dart';
import '../../../theme/theme_scope.dart';
import '../../../widgets/primary_button.dart';
import '../../../widgets/themed_card.dart';
import '../../auth/auth_service.dart';

class PasswordCard extends StatefulWidget {
  const PasswordCard({super.key});

  @override
  State<PasswordCard> createState() => _PasswordCardState();
}

class _PasswordCardState extends State<PasswordCard> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AuthService.instance.updatePassword(
        currentPassword: _currentController.text,
        password: _newController.text,
        passwordConfirmation: _confirmController.text,
      );
      _currentController.clear();
      _newController.clear();
      _confirmController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocaleScope.t(context, 'password_updated'))));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return ThemedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('password_title'), style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: theme.textOnBackground)),
          const SizedBox(height: 12),
          TextField(
            controller: _currentController,
            obscureText: true,
            style: TextStyle(color: theme.textOnBackground),
            decoration: InputDecoration(labelText: t('password_current'), labelStyle: TextStyle(color: theme.textOnBackgroundMuted)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newController,
            obscureText: true,
            style: TextStyle(color: theme.textOnBackground),
            decoration: InputDecoration(labelText: t('password_new'), labelStyle: TextStyle(color: theme.textOnBackgroundMuted)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmController,
            obscureText: true,
            style: TextStyle(color: theme.textOnBackground),
            decoration: InputDecoration(labelText: t('password_confirm'), labelStyle: TextStyle(color: theme.textOnBackgroundMuted)),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: PrimaryButton(label: t('common_update'), loading: _saving, onPressed: _save),
          ),
        ],
      ),
    );
  }
}
