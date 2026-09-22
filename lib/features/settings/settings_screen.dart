import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../core/app_router.dart';
import '../../l10n/locale_scope.dart';
import '../../models/app_user.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/themed_card.dart';
import '../auth/auth_service.dart';
import '../box/box_scope.dart';
import '../box/box_service.dart';
import 'widgets/about_card.dart';
import 'widgets/account_payment_card.dart';
import 'widgets/active_devices_card.dart';
import 'widgets/app_lock_card.dart';
import 'widgets/currency_card.dart';
import 'widgets/danger_zone_card.dart';
import 'widgets/evening_ritual_card.dart';
import 'widgets/language_picker_card.dart';
import 'widgets/morning_ritual_card.dart';
import 'widgets/notification_permission_card.dart';
import 'widgets/password_card.dart';
import 'widgets/profile_card.dart';
import 'widgets/theme_picker_card.dart';

class SettingsScreen extends StatefulWidget {
  final AppUser user;

  const SettingsScreen({super.key, required this.user});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppUser _user;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
  }

  /// Reprend la logique de l'ancien AppDrawer (retiré du Dashboard, voir
  /// CoupleAvatarsBadge/BinomeWordmark) — désormais accessible depuis l'onglet
  /// Profil plutôt que derrière un menu séparé.
  Future<void> _confirmSignOut() async {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(t('signout_confirm_title')),
        content: Text(t('signout_confirm_content')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t('common_cancel'))),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t('signout_action'), style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _signOut();
  }

  Future<void> _signOut() async {
    // Bloque l'écran pendant la déconnexion (jeton push, appel serveur,
    // nettoyage du cache local...) — sans ça, un tap impatient sur un autre
    // élément pendant l'attente laissait l'écran dans un état incohérent
    // (constaté en réel avec d'autres actions asynchrones de l'app).
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
    await AuthService.instance.signOut();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // referme le loader
    AppRouter.toLogin(context);
  }

  Future<void> _leaveBox() async {
    final t = LocaleScope.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('leave_partner_confirm_title')),
        content: Text(t('leave_partner_confirm_content')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t('common_cancel'))),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t('danger_leave_partner'), style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await BoxService.instance.leaveBox();
      if (!mounted) return;
      AppRouter.toBoxChoice(context, _user, replace: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deleteAccount() async {
    final passwordController = TextEditingController();
    final t = LocaleScope.of(context).t;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('delete_account_confirm_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('delete_account_confirm_content')),
            if (!_user.isGoogleAccount) ...[
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(hintText: t('delete_account_password_hint')),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t('common_cancel'))),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t('danger_delete_account'), style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await AuthService.instance.deleteAccount(password: _user.isGoogleAccount ? null : passwordController.text);
      if (!mounted) return;
      AppRouter.toLogin(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final box = BoxScope.of(context).currentBox;
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(t('settings_title'), style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground)),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
            children: [
              ProfileCard(user: _user, onUpdated: (updated) => setState(() => _user = updated)),
              const SizedBox(height: 16),
              const NotificationPermissionCard(),
              const SizedBox(height: 16),
              const AccountPaymentCard(),
              const SizedBox(height: 16),
              const CurrencyCard(),
              const SizedBox(height: 16),
              const ThemePickerCard(),
              const SizedBox(height: 16),
              const LanguagePickerCard(),
              const SizedBox(height: 16),
              const AppLockCard(),
              const SizedBox(height: 16),
              const ActiveDevicesCard(),
              if (box != null && box.isActive) ...[
                const SizedBox(height: 16),
                EveningRitualCard(box: box),
                const SizedBox(height: 16),
                MorningRitualCard(box: box),
              ],
              if (!_user.isGoogleAccount) ...[
                const SizedBox(height: 16),
                const PasswordCard(),
              ],
              const SizedBox(height: 16),
              const AboutCard(),
              const SizedBox(height: 16),
              ThemedCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(Icons.logout_rounded, color: theme.primary),
                  title: Text(
                    t('signout_action'),
                    style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w600, color: theme.textOnBackground),
                  ),
                  onTap: _confirmSignOut,
                ),
              ),
              const SizedBox(height: 24),
              Text(t('danger_title'), style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
              DangerZoneCard(
                showLeaveBox: box != null && box.isActive,
                onLeaveBox: _leaveBox,
                onDeleteAccount: _deleteAccount,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
