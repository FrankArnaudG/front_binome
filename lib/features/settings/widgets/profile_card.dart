import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api_client.dart';
import '../../../l10n/locale_scope.dart';
import '../../../models/app_user.dart';
import '../../../theme/theme_scope.dart';
import '../../../widgets/primary_button.dart';
import '../../../widgets/themed_card.dart';
import '../../auth/auth_service.dart';

enum _AvatarAction { view, camera, gallery, remove }

class ProfileCard extends StatefulWidget {
  final AppUser user;
  final ValueChanged<AppUser> onUpdated;

  const ProfileCard({super.key, required this.user, required this.onUpdated});

  @override
  State<ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<ProfileCard> {
  late final TextEditingController _nameController;
  late final TextEditingController _prenomController;
  bool _saving = false;
  bool _avatarBusy = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.name);
    _prenomController = TextEditingController(text: widget.user.prenom);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _prenomController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // Les petits noms s'éditent désormais depuis "Notre Bulle à nous"
      // (voir CoupleProfileScreen) via un petit crayon sur l'avatar — plus
      // ici. loveName omis : AuthService.updateProfile ne touche pas au
      // champ quand il est absent, pas besoin de le renvoyer inchangé.
      final updated = await AuthService.instance.updateProfile(
        name: _nameController.text.trim(),
        prenom: _prenomController.text.trim(),
      );
      widget.onUpdated(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocaleScope.t(context, 'profile_updated'))));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseAvatarAction() async {
    if (_avatarBusy) return;
    final theme = ThemeScope.paletteOf(context);
    final hasAvatar = widget.user.avatar != null;

    final action = await showModalBottomSheet<_AvatarAction>(
      context: context,
      backgroundColor: theme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            if (hasAvatar)
              ListTile(
                leading: Icon(Icons.visibility_rounded, color: theme.primary),
                title: Text(LocaleScope.t(context, 'photo_view'), style: GoogleFonts.nunito(color: theme.textOnBackground)),
                onTap: () => Navigator.of(ctx).pop(_AvatarAction.view),
              ),
            ListTile(
              leading: Icon(Icons.photo_camera_rounded, color: theme.primary),
              title: Text(LocaleScope.t(context, 'photo_camera'), style: GoogleFonts.nunito(color: theme.textOnBackground)),
              onTap: () => Navigator.of(ctx).pop(_AvatarAction.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_rounded, color: theme.primary),
              title: Text(LocaleScope.t(context, 'photo_gallery'), style: GoogleFonts.nunito(color: theme.textOnBackground)),
              onTap: () => Navigator.of(ctx).pop(_AvatarAction.gallery),
            ),
            if (hasAvatar)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                title: Text(LocaleScope.t(context, 'photo_remove'), style: GoogleFonts.nunito(color: Colors.redAccent)),
                onTap: () => Navigator.of(ctx).pop(_AvatarAction.remove),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    if (action == _AvatarAction.view) {
      final url = widget.user.avatar;
      if (url != null) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => _AvatarPhotoViewer(url: url)));
      }
      return;
    }

    if (action == _AvatarAction.remove) {
      final confirmed = await _confirmRemoveAvatar();
      if (confirmed) await _removeAvatar();
      return;
    }

    final picked = await ImagePicker().pickImage(
      source: action == _AvatarAction.camera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;
    await _uploadAvatar(File(picked.path));
  }

  Future<void> _uploadAvatar(File file) async {
    setState(() => _avatarBusy = true);
    try {
      final updated = await AuthService.instance.uploadAvatar(file);
      widget.onUpdated(updated);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Impossible d'ajouter cette photo pour le moment.")));
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<bool> _confirmRemoveAvatar() async {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          t('photo_remove_confirm_title'),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
        content: Text(
          t('photo_remove_confirm_content'),
          style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t('common_cancel'), style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              t('common_delete'),
              style: GoogleFonts.nunito(color: Colors.redAccent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _removeAvatar() async {
    setState(() => _avatarBusy = true);
    try {
      final updated = await AuthService.instance.deleteAvatar();
      widget.onUpdated(updated);
    } catch (_) {
      // best effort
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
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
          Row(
            children: [
              GestureDetector(
                onTap: _chooseAvatarAction,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: theme.primary,
                        backgroundImage: widget.user.avatar != null ? NetworkImage(widget.user.avatar!) : null,
                        child: widget.user.avatar == null
                            ? Text(widget.user.prenom.isNotEmpty ? widget.user.prenom[0].toUpperCase() : '?',
                                style: const TextStyle(color: Colors.white))
                            : null,
                      ),
                      if (!_avatarBusy)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: theme.primary,
                              border: Border.all(color: theme.surface, width: 2),
                            ),
                            child: const Icon(Icons.add_a_photo_rounded, size: 10, color: Colors.white),
                          ),
                        ),
                      if (_avatarBusy)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), shape: BoxShape.circle),
                            child: const Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.user.email,
                  style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _prenomController,
            style: TextStyle(color: theme.textOnBackground),
            decoration: InputDecoration(labelText: t('profile_firstname'), labelStyle: TextStyle(color: theme.textOnBackgroundMuted)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            style: TextStyle(color: theme.textOnBackground),
            decoration: InputDecoration(labelText: t('profile_lastname'), labelStyle: TextStyle(color: theme.textOnBackgroundMuted)),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: PrimaryButton(label: t('common_save'), loading: _saving, onPressed: _save),
          ),
        ],
      ),
    );
  }
}

class _AvatarPhotoViewer extends StatelessWidget {
  final String url;

  const _AvatarPhotoViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 48),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
