import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../models/heartbeat_image.dart';
import '../../../theme/theme_scope.dart';
import 'heartbeat_card.dart';

/// Revoir un battement de cœur déjà envoyé, en grand — par-dessus l'écran
/// de discussion actuel (fond flouté/assombri) plutôt qu'en changeant de
/// page, même principe que showPackReplyModal. La vraie carte (photo en
/// rotation, texte manuscrit superposé, cœur discret), pas une vignette
/// simplifiée — [HeartbeatCard] est la même utilisée en plein écran.
Future<void> showHeartbeatReplyModal(
  BuildContext context, {
  required List<HeartbeatImage> images,
  required String message,
  String? family,
  String? senderGender,
}) {
  return showGeneralDialog(
    context: context,
    barrierLabel: 'Fermer',
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) =>
        _HeartbeatReplyModal(images: images, message: message, family: family, senderGender: senderGender),
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

class _HeartbeatReplyModal extends StatelessWidget {
  final List<HeartbeatImage> images;
  final String message;
  final String? family;
  final String? senderGender;

  const _HeartbeatReplyModal({required this.images, required this.message, this.family, this.senderGender});

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
                AspectRatio(
                  // Images de famille en portrait (4:5), photos du catalogue en 4:3.
                  aspectRatio: HeartbeatCard.usesFamilyImage(family, images) ? 4 / 5 : 4 / 3,
                  child: HeartbeatCard(images: images, message: message, theme: theme, family: family, senderGender: senderGender),
                ),
                Positioned(
                  top: -10,
                  right: -10,
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(5),
                        child: Icon(Icons.close_rounded, size: 14, color: Colors.black87),
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
}
