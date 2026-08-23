import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api_client.dart';
import '../../../models/pack.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../content_service.dart';
import 'slide_pack_viewer.dart';

/// Revoir un poème déjà envoyé, en grand — par-dessus l'écran de discussion
/// actuel (fond flouté/assombri) plutôt qu'en changeant de page : fermer la
/// modale doit ramener instantanément au fil, pas déclencher un retour de
/// navigation. Taille volontairement contenue (pas plein écran) pour rester
/// soigné — mêmes proportions que la bulle principale de la carte, juste un
/// cran plus petites pour bien se distinguer du fond.
Future<void> showPackReplyModal(BuildContext context, {required String packId}) {
  return showGeneralDialog(
    context: context,
    barrierLabel: 'Fermer',
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) =>
        _PackReplyModal(packId: packId),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _PackReplyModal extends StatefulWidget {
  final String packId;

  const _PackReplyModal({required this.packId});

  @override
  State<_PackReplyModal> createState() => _PackReplyModalState();
}

class _PackReplyModalState extends State<_PackReplyModal> {
  Pack? _pack;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pack = await ContentService.instance.fetchPack(widget.packId);
      if (!mounted) return;
      setState(() {
        _pack = pack;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final screen = MediaQuery.of(context).size;
    // Large et lisible — juste assez de marge autour pour garder le fond
    // flouté visible et signaler "posée par-dessus", sans coller aux bords.
    final cardWidth = (screen.width * 0.9).clamp(280.0, 420.0);

    return Stack(
      children: [
        // Fond flouté/assombri — même esprit "verre dépoli" que la bulle de
        // chat, pour que la modale reste cohérente avec le reste de l'écran.
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(color: Colors.black.withValues(alpha: 0.45)),
            ),
          ),
        ),
        Center(
          child: SizedBox(
            width: cardWidth,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: AspectRatio(
                    // Plus haute que la carte "pleine largeur" (3/4) : ici la
                    // largeur est déjà contrainte par cardWidth, donc on peut
                    // se permettre plus de hauteur sans déborder de l'écran.
                    aspectRatio: 0.7,
                    child: Container(
                      // Transparent plutôt que theme.surface : le fond flouté
                      // derrière doit se voir dans l'espace entre les cartes
                      // pendant le swipe, pas un bloc de couleur pleine qui
                      // ressemble à un cadre photo.
                      color: Colors.transparent,
                      child: _content(theme),
                    ),
                  ),
                ),
                Positioned(
                  top: -14,
                  right: -14,
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 4,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.close_rounded, size: 20, color: Colors.black87),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _content(ThemePalette theme) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: theme.primary));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(color: theme.textOnBackground),
          ),
        ),
      );
    }
    final pack = _pack!;
    if (pack.slides.isEmpty) {
      return Center(
        child: Text(
          'Aucune slide dans ce pack.',
          style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
        ),
      );
    }
    return SlidePackViewer(
      slides: pack.slides,
      theme: theme,
      category: pack.category,
      // Marge horizontale seulement : garde les cartes bord à bord en
      // hauteur (pas de liseré en haut/bas), mais les sépare bien l'une de
      // l'autre pendant le swipe plutôt que de les laisser se toucher.
      slideMargin: const EdgeInsets.symmetric(horizontal: 6),
    );
  }
}
