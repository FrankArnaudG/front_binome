import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/box_photo.dart';
import 'photo_vault_service.dart';
import 'widgets/expired_photo_button.dart';

/// Visionneuse plein écran (défilement + zoom) pour le Jardin secret.
class PhotoViewerScreen extends StatefulWidget {
  final List<BoxPhoto> photos;
  final int initialIndex;
  final Future<void> Function(BoxPhoto photo) onDelete;

  const PhotoViewerScreen({super.key, required this.photos, required this.initialIndex, required this.onDelete});

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController _controller;
  late int _index;
  late List<BoxPhoto> _photos;

  @override
  void initState() {
    super.initState();
    _photos = List.of(widget.photos);
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
    _markViewed(_index);
  }

  // Marque la photo affichée comme "vue" (voir PhotoVaultService.markViewed)
  // — seule l'ouverture en plein écran compte, jamais le simple défilement
  // de la grille (voir PhotoVaultScreen). Ne fait rien pour un id déjà
  // marqué côté serveur : firstOrCreate() y est idempotent.
  void _markViewed(int index) {
    PhotoVaultService.instance.markViewed(_photos[index].id);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    final photo = _photos[_index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette photo ?'),
        content: const Text('Cette action est irréversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Supprimer', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await widget.onDelete(photo);
    if (!mounted) return;

    setState(() => _photos.removeAt(_index));
    if (_photos.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    if (_index >= _photos.length) setState(() => _index = _photos.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: _photos.length,
            onPageChanged: (i) {
              setState(() => _index = i);
              _markViewed(i);
            },
            itemBuilder: (context, i) {
              final photo = _photos[i];
              return InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  // CachedNetworkImage (pas Image.network) : la mise en cache
                  // disque, pas juste mémoire, est ce qui permet à la photo
                  // de rester consultable une fois son fichier retiré du
                  // serveur (voir PhotoVaultService.markViewed).
                  child: CachedNetworkImage(
                    imageUrl: photo.url,
                    fit: BoxFit.contain,
                    errorWidget: (context, url, error) => ExpiredPhotoButton(photoId: photo.id),
                  ),
                ),
              );
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                    onPressed: _confirmDelete,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Text(
                  _relativeDate(_photos[_index].createdAt),
                  style: GoogleFonts.nunito(fontSize: 13, color: Colors.white70),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _relativeDate(DateTime date) {
  final d = date.toLocal();
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
