import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/pin_storage.dart';
import '../../../l10n/locale_scope.dart';
import '../../../theme/theme_scope.dart';
import '../../../widgets/themed_card.dart';
import '../../lock/pin_setup_screen.dart';
import '../../lock/pin_verify_screen.dart';

class AppLockCard extends StatefulWidget {
  const AppLockCard({super.key});

  @override
  State<AppLockCard> createState() => _AppLockCardState();
}

class _AppLockCardState extends State<AppLockCard> {
  bool _enabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await PinStorage.instance.isEnabled();
    if (mounted) {
      setState(() {
        _enabled = enabled;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(bool value) async {
    if (value) {
      final created = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const PinSetupScreen()),
      );
      if (created == true && mounted) setState(() => _enabled = true);
    } else {
      final verified = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const PinVerifyScreen(title: 'Entre ton code pour désactiver')),
      );
      if (verified == true) {
        await PinStorage.instance.clear();
        if (mounted) setState(() => _enabled = false);
      }
    }
  }

  Future<void> _changePin() async {
    final verified = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PinVerifyScreen(title: 'Entre ton code actuel')),
    );
    if (verified != true || !mounted) return;
    await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const PinSetupScreen()));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return ThemedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('applock_title'), style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: theme.textOnBackground)),
          const SizedBox(height: 4),
          Text(
            t('applock_subtitle'),
            style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _enabled,
            onChanged: _toggle,
            activeColor: theme.primary,
            title: Text(t('common_enabled'), style: GoogleFonts.nunito(fontSize: 14, color: theme.textOnBackground)),
          ),
          if (_enabled)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.password_rounded, color: theme.primary),
              title: Text(t('applock_change'), style: GoogleFonts.nunito(fontSize: 14, color: theme.textOnBackground)),
              onTap: _changePin,
            ),
        ],
      ),
    );
  }
}
