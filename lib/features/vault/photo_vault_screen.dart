import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../l10n/locale_scope.dart';
import '../../models/box_photo.dart';
import '../../theme/app_colors.dart';
import '../../widgets/empty_state.dart';
import 'photo_vault_service.dart';
import 'photo_viewer_screen.dart';
import 'widgets/expired_photo_button.dart';

/// "Jardin secret" — album photo privé du couple (voir BoxPhotoController).
/// Plafonné à [PhotoVaultService.maxPhotos] côté serveur ; chaque envoi est
/// recompressé côté backend, pas ici — l'app envoie le fichier tel quel.
class PhotoVaultScreen extends StatefulWidget {
  const PhotoVaultScreen({super.key});

  @override
  State<PhotoVaultScreen> createState() => _PhotoVaultScreenState();
}

class _PhotoVaultScreenState extends State<PhotoVaultScreen> {
  List<BoxPhoto>? _photos;
  bool _initialLoading = true;
  bool _loadError = false;
  bool _uploading = false;
  bool _deleting = false;

  /// Id de la photo sélectionnée (appui maintenu sur une tuile) — la
  /// suppression se fait depuis la grille via ce mode sélection, plutôt que
  /// d'exiger d'ouvrir la photo en plein écran d'abord.
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final photos = await PhotoVaultService.instance.fetchPhotos();
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _initialLoading = false;
        _loadError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        _loadError = _photos == null;
      });
    }
  }

  Future<void> _pickAndUpload(BuildContext context) async {
    final photos = _photos;
    if (photos != null && photos.length >= PhotoVaultService.maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LocaleScope.of(context).t('vault_full_snackbar'))),
      );
      return;
    }

    final source = await _chooseSource(context);
    if (source == null || !context.mounted) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final photo = await PhotoVaultService.instance.uploadPhoto(
        File(picked.path),
      );
      if (!mounted) return;
      setState(() => _photos = [photo, ...?_photos]);
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LocaleScope.of(context).t('vault_upload_error'))),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<ImageSource?> _chooseSource(BuildContext context) {
    final t = LocaleScope.of(context).t;
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.blushCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(
                Icons.photo_camera_rounded,
                color: AppColors.primary,
              ),
              title: Text(t('vault_take_photo')),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_rounded,
                color: AppColors.primary,
              ),
              title: Text(t('vault_choose_gallery')),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _deletePhoto(BoxPhoto photo) async {
    try {
      await PhotoVaultService.instance.deletePhoto(photo.id);
      if (!mounted) return;
      setState(() {
        _photos = _photos?.where((p) => p.id != photo.id).toList();
        if (_selectedId == photo.id) _selectedId = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LocaleScope.of(context).t('vault_delete_error'))),
      );
    }
  }

  Future<void> _deleteSelected() async {
    final id = _selectedId;
    if (id == null) return;
    final photo = _photos?.firstWhere((p) => p.id == id);
    if (photo == null) return;

    setState(() => _deleting = true);
    await _deletePhoto(photo);
    if (mounted) setState(() => _deleting = false);
  }

  void _toggleSelection(String photoId) {
    setState(() => _selectedId = _selectedId == photoId ? null : photoId);
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photos ?? [];
    final t = LocaleScope.of(context).t;

    return Scaffold(
      backgroundColor: AppColors.blush,
      appBar: AppBar(
        backgroundColor: AppColors.blush,
        elevation: 0,
        foregroundColor: AppColors.textOnBlush,
        title: Text(
          t('vault_title'),
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: AppColors.textOnBlush,
          ),
        ),
        actions: [
          if (_selectedId != null)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: t('vault_cancel_selection'),
              onPressed: () => setState(() => _selectedId = null),
            )
          else if (!_initialLoading)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${photos.length}/${PhotoVaultService.maxPhotos}',
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textOnBlushMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _selectedId != null
          ? FloatingActionButton(
              backgroundColor: Theme.of(context).colorScheme.error,
              onPressed: _deleting ? null : _deleteSelected,
              child: _deleting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Icon(Icons.delete_outline_rounded, color: Colors.white),
            )
          : FloatingActionButton(
              backgroundColor: AppColors.primary,
              onPressed: _uploading ? null : () => _pickAndUpload(context),
              child: _uploading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add_a_photo_rounded, color: Colors.white),
            ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t('vault_subtitle'),
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        color: AppColors.textOnBlushMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(photos)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<BoxPhoto> photos) {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final t = LocaleScope.of(context).t;
    if (_loadError) {
      return EmptyState(
        icon: Icons.wifi_off_rounded,
        message: t('vault_load_error'),
      );
    }
    if (photos.isEmpty) {
      return EmptyState(
        icon: Icons.photo_rounded,
        message: t('vault_empty'),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.82,
      ),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        final photo = photos[index];
        final selected = _selectedId == photo.id;
        return _PhotoTile(
          photo: photo,
          selected: selected,
          onTap: () {
            // En mode sélection, un tap simple bascule la sélection au lieu
            // d'ouvrir la photo — évite d'ouvrir la visionneuse par erreur
            // en essayant de désélectionner.
            if (_selectedId != null) {
              _toggleSelection(photo.id);
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PhotoViewerScreen(
                  photos: photos,
                  initialIndex: index,
                  onDelete: _deletePhoto,
                ),
              ),
            );
          },
          onLongPress: () => _toggleSelection(photo.id),
        );
      },
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final BoxPhoto photo;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _PhotoTile({
    required this.photo,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: photo.url,
                fit: BoxFit.cover,
                placeholder: (context, url) => const ColoredBox(color: Color(0x11000000)),
                errorWidget: (context, url, error) => ColoredBox(
                  color: Colors.black.withValues(alpha: 0.55),
                  child: Center(child: ExpiredPhotoButton(photoId: photo.id, compact: true)),
                ),
              ),
              if (selected) ...[
                Container(color: Colors.black.withValues(alpha: 0.35)),
                const Center(
                  child: Icon(Icons.check_circle_rounded, color: Colors.white, size: 36),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
