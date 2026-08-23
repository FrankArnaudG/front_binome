import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/app_user.dart';
import '../../../theme/theme_scope.dart';

/// Deux petits avatars circulaires (le sien, celui du/de la partenaire),
/// légèrement superposés et reliés par un cœur — remplace l'en-tête texte
/// seul du Dashboard par un rappel visuel immédiat "à deux".
///
/// Quand [partnerPresent] est vrai, ce cœur central passe au vert — couleur
/// fixe et universellement reconnue comme "en ligne" (WhatsApp/Messenger),
/// jamais dérivée d'un thème (donc lisible pareil sur les ~16 thèmes,
/// clairs comme sombres) : un seul indicateur de présence plutôt que d'en
/// dupliquer un second (point séparé) sur l'avatar.
class CoupleAvatarsBadge extends StatelessWidget {
  static const _onlineColor = Color(0xFF2ECC71);

  final AppUser user;
  final AppUser? partner;
  final bool partnerPresent;

  const CoupleAvatarsBadge({super.key, required this.user, this.partner, this.partnerPresent = false});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);

    return SizedBox(
      width: 50,
      height: 34,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            child: _Avatar(user: user, background: theme.primary),
          ),
          Positioned(
            left: 20,
            child: _Avatar(user: partner, background: theme.secondary),
          ),
          Positioned(
            left: 15,
            top: 9,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.background,
                border: Border.all(color: theme.surface, width: 1.5),
              ),
              child: Icon(
                Icons.favorite_rounded,
                size: 9,
                color: partnerPresent ? _onlineColor : theme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final AppUser? user;
  final Color background;

  const _Avatar({required this.user, required this.background});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final avatar = user?.avatar;
    final initial = user != null && user!.prenom.isNotEmpty ? user!.prenom[0].toUpperCase() : '?';

    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: theme.background, width: 2)),
      child: CircleAvatar(
        radius: 13,
        backgroundColor: background,
        // Mis en cache sur disque (pas juste en mémoire comme NetworkImage
        // par défaut) — la photo de profil ne se re-télécharge plus à
        // chaque ouverture de l'app, ni ne clignote le temps du fetch
        // réseau à chaque rebuild de ce badge, très visible ici puisqu'il
        // est de retour sur presque tous les écrans du Dashboard.
        backgroundImage: avatar != null ? CachedNetworkImageProvider(avatar) : null,
        child: avatar == null ? Text(initial, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)) : null,
      ),
    );
  }
}
