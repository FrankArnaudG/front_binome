import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/app_router.dart';
import '../features/auth/auth_service.dart';
import '../models/app_user.dart';
import '../theme/app_colors.dart';

class AppDrawer extends StatelessWidget {
  final AppUser user;

  const AppDrawer({super.key, required this.user});

  Future<void> _signOut(BuildContext context) async {
    await AuthService.instance.signOut();
    if (!context.mounted) return;
    AppRouter.toLogin(context);
  }

  void _comingSoon(BuildContext context) {
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bientôt disponible 💕')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.blush,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textOnBlush),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.primary,
                    backgroundImage: user.avatar != null ? NetworkImage(user.avatar!) : null,
                    child: user.avatar == null
                        ? Text(user.prenom.isNotEmpty ? user.prenom[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white))
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    user.prenom,
                    style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              _MenuTile(icon: Icons.info_outline_rounded, label: 'À propos', onTap: () => _comingSoon(context)),
              _MenuTile(icon: Icons.mail_outline_rounded, label: 'Nous contacter', onTap: () => _comingSoon(context)),
              const Divider(),
              _MenuTile(
                icon: Icons.logout_rounded,
                label: 'Se déconnecter',
                onTap: () => _signOut(context),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Version 1.0.0',
                  style: GoogleFonts.nunito(fontSize: 12, color: AppColors.textOnBlushMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.primary),
      title: Text(label, style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}
