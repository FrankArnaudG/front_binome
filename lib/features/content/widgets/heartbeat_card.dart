import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/heartbeat_family.dart';
import '../../../models/heartbeat_image.dart';
import '../../../theme/handwritten_fonts.dart';
import '../../../theme/theme_palette.dart';

/// La "vraie carte" d'un battement de cœur — photo en rotation automatique
/// (toutes les 5 secondes, jamais vers une image pas encore chargée), voile
/// dégradé, texte manuscrit superposé, petit cœur discret. Extraite de
/// SlideDetailScreen pour être réutilisée telle quelle dans la modale de
/// réponse (voir showHeartbeatReplyModal) — la même carte doit apparaître
/// partout où un battement de cœur est affiché en grand, pas une variante
/// simplifiée.
class HeartbeatCard extends StatefulWidget {
  final List<HeartbeatImage> images;
  final String message;
  final ThemePalette theme;

  /// Famille du battement + genre de la personne qui l'ENVOIE : sans photo
  /// du catalogue, choisissent l'image packagée qui habille la carte (voir
  /// heartbeat_family.dart). Sans famille (message personnalisé, ancien
  /// envoi), la carte blanche habituelle s'affiche.
  final String? family;
  final String? senderGender;

  /// Multiplie tailles de texte/espacements — 1.0 par défaut (taille
  /// "pleine carte", voir SlideDetailScreen/showHeartbeatReplyModal). À
  /// réduire (voir GameBoxHistoryScreen._buildHeartbeatBubble) quand la
  /// carte est affichée en miniature dans le fil : les valeurs par défaut
  /// sont pensées pour une carte pleine largeur et débordaient/paraissaient
  /// démesurées telles quelles sur une petite carte (même correctif que
  /// SlideVisualCard.scale).
  final double scale;

  const HeartbeatCard({
    super.key,
    required this.images,
    required this.message,
    required this.theme,
    this.family,
    this.senderGender,
    this.scale = 1,
  });

  /// La carte sera-t-elle habillée d'une image de famille ? Les images sont en
  /// portrait (4:5) : l'appelant doit alors lui donner cette proportion plutôt
  /// que le 4:3 paysage des photos du catalogue.
  static bool usesFamilyImage(String? family, List<HeartbeatImage> images) =>
      images.isEmpty && heartbeatFamilyStyleFor(family) != null;

  @override
  State<HeartbeatCard> createState() => _HeartbeatCardState();
}

class _HeartbeatCardState extends State<HeartbeatCard> {
  // Un Set plutôt qu'une List<bool> parallèle, plus simple à tenir à jour vu
  // que le chargement de chaque image se termine dans un ordre imprévisible.
  final Set<String> _loadedImages = {};
  int _imageIndex = 0;
  Timer? _rotationTimer;

  @override
  void initState() {
    super.initState();
    if (widget.images.isNotEmpty) {
      // Après le premier frame : precacheImage a besoin d'un BuildContext
      // déjà rattaché à l'arbre (Directionality, etc.), pas encore garanti
      // pendant initState.
      WidgetsBinding.instance.addPostFrameCallback((_) => _precacheImages());
      _rotationTimer = Timer.periodic(const Duration(seconds: 5), (_) => _rotate());
    }
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    super.dispose();
  }

  /// Précharge chaque image en arrière-plan — la rotation (voir [_rotate])
  /// ne bascule jamais vers une image pas encore prête, pour éviter un flash
  /// de zone vide toutes les 5 secondes.
  void _precacheImages() {
    for (final image in widget.images) {
      precacheImage(NetworkImage(image.url), context).then((_) {
        if (!mounted) return;
        setState(() {
          _loadedImages.add(image.url);
          // L'image affichée au tout premier rendu (index 0) n'est pas
          // forcément la plus rapide à charger — si une AUTRE vient de
          // finir avant elle, autant montrer celle-là tout de suite plutôt
          // que de laisser tourner le loader sans raison. Ne concerne que
          // le tout premier affichage : une fois qu'une image est prête,
          // ce chemin ne se redéclenche plus (voir la condition ci-dessous).
          if (!_loadedImages.contains(widget.images[_imageIndex].url)) {
            final readyIndex = widget.images.indexWhere((img) => _loadedImages.contains(img.url));
            if (readyIndex != -1) _imageIndex = readyIndex;
          }
        });
      }).catchError((_) {
        // Image cassée/indisponible : reste simplement exclue de la
        // rotation, jamais affichée telle quelle.
      });
    }
  }

  /// Avance vers l'image suivante dans l'ordre SI elle est déjà chargée ;
  /// sinon bascule vers n'importe quelle autre image déjà prête plutôt que
  /// de rester bloquée sur l'ordre strict ; si aucune autre n'est encore
  /// chargée, l'image actuelle reste affichée telle quelle.
  void _rotate() {
    final images = widget.images;
    if (images.length < 2 || !mounted) return;

    final next = (_imageIndex + 1) % images.length;
    if (_loadedImages.contains(images[next].url)) {
      setState(() => _imageIndex = next);
      return;
    }

    for (var offset = 1; offset < images.length; offset++) {
      final candidate = (next + offset) % images.length;
      if (candidate == _imageIndex) continue;
      if (_loadedImages.contains(images[candidate].url)) {
        setState(() => _imageIndex = candidate);
        return;
      }
    }
    // Aucune image chargée à part (au mieux) celle déjà affichée : on
    // patiente, rien à changer ce tour-ci.
  }

  /// Remplace le dernier espace par une espace insécable — sans ça, un
  /// emoji final (ex. "Tu me manques 💕") pouvait passer seul à la ligne
  /// suivante et se retrouver centré tout seul, visuellement décentré par
  /// rapport au mot qui le précède.
  String _glueTrailingEmoji(String text) {
    final lastSpace = text.lastIndexOf(' ');
    if (lastSpace == -1) return text;
    return '${text.substring(0, lastSpace)} ${text.substring(lastSpace + 1)}';
  }

  /// Carte "famille" : image packagée plein cadre, message manuscrit posé dans
  /// la zone dégagée (haut de l'image, côté choisi par famille), jamais par-
  /// dessus le couple. Le texte rétrécit au besoin plutôt que de déborder.
  Widget _buildFamilyCard(HeartbeatFamilyStyle style) {
    final theme = widget.theme;
    final scale = widget.scale;
    final badgeOnLeft = style.textAlignment.x > 0.5;
    final textAlignment = Alignment(style.textAlignment.x, -1);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.primary.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(style.assetFor(widget.senderGender), fit: BoxFit.cover),
          // Voile léger en haut : garde le texte blanc lisible même sur une
          // image lumineuse (coucher de soleil, lumière du jour).
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.black45, Colors.transparent],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.55],
              ),
            ),
          ),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cardW = constraints.maxWidth;
                final cardH = constraints.maxHeight;
                // Taille proportionnelle à la largeur de la carte (et non fixe) :
                // lisible aussi bien en plein écran qu'en miniature, et un
                // peu réduite pour les messages longs plutôt que de tout
                // rétrécir en bloc dans une colonne étroite.
                final length = widget.message.runes.length;
                final lengthFactor = length <= 45 ? 1.0 : (length <= 80 ? 0.88 : 0.78);
                final fontSize = (cardW * 0.08 * lengthFactor).clamp(11.0, 36.0);
                final sidePadding = cardW * 0.07;
                final textWidth = math.min(cardW * style.widthFactor, cardW - 2 * sidePadding);
                return Padding(
                  // Départ régulier sous le repère "Battement de cœur".
                  padding: EdgeInsets.fromLTRB(sidePadding, cardH * 0.15, sidePadding, 0),
                  child: Align(
                    alignment: textAlignment,
                    child: SizedBox(
                      width: textWidth,
                      height: cardH * 0.42,
                      child: FittedBox(
                        // Filet de sécurité : ne réduit que si le texte
                        // dépasse vraiment la zone dégagée.
                        fit: BoxFit.scaleDown,
                        alignment: textAlignment,
                        child: SizedBox(
                          width: textWidth,
                          child: Text(
                            _glueTrailingEmoji(widget.message),
                            textAlign: style.textAlign,
                            style: handwrittenFont('dancing_script', color: Colors.white, fontSize: fontSize).copyWith(
                              height: 1.2,
                              shadows: const [Shadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 2))],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Même repère discret que les autres cartes, du côté opposé au texte.
          Positioned(
            top: 12 * scale,
            left: badgeOnLeft ? 12 * scale : null,
            right: badgeOnLeft ? null : 12 * scale,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.28), borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.favorite_rounded, size: 12 * scale, color: Colors.white),
                  SizedBox(width: 4 * scale),
                  Text('Battement de cœur', style: handwrittenFont('caveat', color: Colors.white, fontSize: 15 * scale)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final images = widget.images;

    if (HeartbeatCard.usesFamilyImage(widget.family, images)) {
      return _buildFamilyCard(heartbeatFamilyStyleFor(widget.family)!);
    }

    if (images.isEmpty) {
      // Pas d'image (message personnalisé, ou catalogue sans photo) :
      // `theme.surface` est déjà choisi par chaque thème pour rester
      // lisible avec `textOnBackground`, contrairement à un blanc fixe qui
      // casserait les thèmes sombres.
      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.primary.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 22 * widget.scale, vertical: 28 * widget.scale),
              child: Center(
                child: Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: handwrittenFont('dancing_script', color: theme.textOnBackground, fontSize: 30 * widget.scale),
                ),
              ),
            ),
            // Repère discret "ceci est un battement de cœur", en toutes
            // lettres — même repère que la variante avec photo plus bas.
            Positioned(
              top: 10 * widget.scale,
              right: 14 * widget.scale,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.favorite_rounded, size: 11 * widget.scale, color: theme.primary.withValues(alpha: 0.45)),
                  SizedBox(width: 4 * widget.scale),
                  Text(
                    'Battement de cœur',
                    style: handwrittenFont(
                      'caveat',
                      color: theme.textOnBackgroundMuted.withValues(alpha: 0.75),
                      fontSize: 15 * widget.scale,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // Fond neutre plutôt que transparent : pendant le fondu entre deux
        // images (les deux sont semi-transparentes un court instant), sans
        // lui la couleur derrière transperçait et donnait un effet "flash".
        color: Colors.black,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.primary.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Le fondu masque le petit à-coup du changement d'image toutes
          // les 5 secondes — sans lui, la bascule serait sèche.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            // Le Stack interne par défaut d'AnimatedSwitcher est en
            // StackFit.loose : sans ce layoutBuilder, l'image se
            // dimensionnait à sa taille naturelle au lieu de remplir le
            // cadre, laissant voir le fond derrière sur les bords.
            layoutBuilder: (currentChild, previousChildren) => Stack(
              fit: StackFit.expand,
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            ),
            child: Image.network(
              images[_imageIndex].url,
              key: ValueKey(images[_imageIndex].url),
              fit: BoxFit.cover,
              // Point focal réglé côté admin — garde la zone choisie
              // visible après recadrage, au lieu du centre par défaut.
              alignment: images[_imageIndex].alignment,
              // Sans ça : la petite icône "image cassée" par défaut de
              // Flutter (croix rouge) le temps du chargement — visible en
              // réel dès qu'une image n'a pas encore fini de télécharger.
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                  ),
                );
              },
              // En cas d'échec réel (pas juste en cours de chargement) : le
              // fond noir du Container suffit, pas besoin d'une icône
              // d'erreur en plus qui attirerait l'œil sur une photo ratée.
              errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
            ),
          ),
          // Voile sombre en bas pour garder le message lisible quelle que
          // soit la photo derrière.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Colors.black54],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.45, 1],
              ),
            ),
          ),
          Positioned(
            left: 24 * widget.scale,
            right: 24 * widget.scale,
            // Voir SlideVisualCard.scale : plancher qui garde de la place
            // pour le repère "Battement de cœur" du coin haut-droit même à
            // faible échelle, plutôt qu'un simple 26 * scale qui s'en
            // approchait trop (même correctif que pour les cartes-poèmes).
            bottom: math.max(26 * widget.scale, 22),
            child: Text(
              _glueTrailingEmoji(widget.message),
              textAlign: TextAlign.center,
              maxLines: widget.scale < 1 ? 3 : null,
              overflow: widget.scale < 1 ? TextOverflow.ellipsis : null,
              // Police manuscrite plutôt que l'italique "élégant" des
              // poèmes — un battement de cœur se lit comme un mot glissé à
              // la main sur la photo.
              style: handwrittenFont('dancing_script', color: Colors.white, fontSize: 30 * widget.scale).copyWith(
                shadows: const [
                  Shadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 2)),
                ],
              ),
            ),
          ),
          // Même repère discret que la variante sans photo (icône + mot en
          // manuscrit) — le voile sombre du haut est très léger (le
          // dégradé ne démarre qu'à 45% de la hauteur), donc toujours
          // lisible même sur une photo claire.
          Positioned(
            top: 12 * widget.scale,
            right: 12 * widget.scale,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8 * widget.scale, vertical: 4 * widget.scale),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.favorite_rounded, size: 12 * widget.scale, color: Colors.white),
                  SizedBox(width: 4 * widget.scale),
                  Text(
                    'Battement de cœur',
                    style: handwrittenFont('caveat', color: Colors.white, fontSize: 15 * widget.scale),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
