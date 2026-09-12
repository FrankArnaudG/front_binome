import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/app_router.dart';
import '../../models/doodle.dart';
import '../../models/public_profile.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../box/box_scope.dart';
import '../games/game_service.dart';
import '../games/pictionary/pictionary_canvas.dart';
import 'doodle_canvas_shape.dart';
import 'doodle_service.dart';

/// Affiche un doodle reçu du binôme EN PLEIN ÉCRAN, par-dessus l'écran déjà
/// affiché (voir demande utilisateur : "un vrai transparent mais uniquement
/// dans l'application") — poussé via une route NON opaque (voir
/// DoodleOverlay), donc ce widget ne peint volontairement AUCUN fond opaque
/// lui-même : l'écran du dessous reste visible en dessous d'un léger voile
/// sombre (posé par la route elle-même, voir `barrierColor`), pas remplacé
/// par un nouveau décor. Réutilise [PictionaryCanvas] en mode
/// non-interactif, pur rendu des traits déjà reçus.
class DoodleViewScreen extends StatefulWidget {
  final Doodle doodle;
  // Id de la personne qui REGARDE cet écran — permise pour distinguer "tu
  // relis un mot que TU as envoyé" de "on te montre un mot reçu" (voir
  // DoodleHistoryScreen, qui laisse agrandir n'importe quelle bulle de
  // l'historique, y compris les siennes). `null` pour l'arrivée en direct
  // (voir DoodleOverlay) : c'est alors TOUJOURS un mot reçu.
  final String? viewerUserId;
  // `true` pour la relecture depuis l'historique (voir demande utilisateur :
  // "le fond doit exister", contrairement à l'arrivée en direct qui reste
  // transparente sur l'écran du dessous) — peint le fond du thème perso
  // (voir ThemedBackground) au lieu de laisser voir à travers.
  final bool showBackground;

  const DoodleViewScreen({super.key, required this.doodle, this.viewerUserId, this.showBackground = false});

  @override
  State<DoodleViewScreen> createState() => _DoodleViewScreenState();
}

class _DoodleViewScreenState extends State<DoodleViewScreen> {
  String? _senderName;

  bool get _isMine => widget.viewerUserId != null && widget.doodle.fromUserId == widget.viewerUserId;

  @override
  void initState() {
    super.initState();
    // Masquée le temps de l'affichage (voir demande utilisateur : "pour
    // pouvoir faire le rectangle il faut cacher la navbar") — même
    // mécanisme que DoodleComposeScreen, libère la hauteur nécessaire au
    // ratio partagé (voir doodle_canvas_shape.dart), remise au retour.
    AppRouter.showGlobalNavBar.value = false;
    // Marquer "vu" n'a de sens QUE côté destinataire — le backend refuse
    // sinon (403, voir DoodleController::markViewed), donc inutile de
    // l'appeler pour un mot que l'on a soi-même envoyé (voir _isMine, cas
    // de relecture depuis l'historique).
    if (!_isMine) {
      // Best-effort — voir doc de classe : rien à afficher/retenter si ça
      // échoue, le poll de secours de DoodleNotifier ne re-proposera de
      // toute façon pas ce doodle une fois localement affiché.
      DoodleService.instance.markDoodleViewed(widget.doodle.id).ignore();
    }
    _resolveSenderName();
  }

  @override
  void dispose() {
    AppRouter.showGlobalNavBar.value = true;
    super.dispose();
  }

  /// Le/la binôme est presque toujours déjà dans la Box (voir BoxScope) —
  /// repli sur le profil public UNIQUEMENT si jamais absent (ex. Box pas
  /// encore rechargée localement), même filet de sécurité que
  /// game_invite_overlay.dart pour un cas hors-Box.
  Future<void> _resolveSenderName() async {
    final box = BoxScope.of(context).currentBox;
    final fromBox = box?.creator?.id == widget.doodle.fromUserId ? box?.creator : box?.partner;
    if (fromBox != null) {
      setState(() => _senderName = fromBox.prenom);
      return;
    }
    try {
      final PublicProfile profile = await GameService.instance.fetchPublicProfile(widget.doodle.fromUserId);
      if (mounted) setState(() => _senderName = profile.prenom);
    } catch (_) {
      // Repli silencieux sur le libellé générique déjà affiché.
    }
  }

  // Même structure/mêmes marges que DoodleComposeScreen (voir demande
  // utilisateur : "le même espace que pour l'édition") — une vraie AppBar
  // transparente (pas un en-tête maison plus fin), le même padding
  // fromLTRB(20, 8, 20, 12), et un espace réservé en bas (voir
  // doodle_canvas_shape.dart) équivalent aux rangées d'outils absentes ici.
  @override
  Widget build(BuildContext context) {
    final textColor = widget.showBackground ? null : Colors.white;
    final textShadows = widget.showBackground ? null : const [Shadow(color: Colors.black54, blurRadius: 8)];
    final title = _isMine ? 'Ton petit mot 💌' : (_senderName != null ? '$_senderName t\'a écrit 💌' : 'Un mot de ton binôme 💌');

    final theme = widget.showBackground ? ThemeScope.paletteOf(context) : null;
    final resolvedTextColor = textColor ?? theme!.textOnBackground;
    final borderColor = widget.showBackground ? theme!.textOnBackground.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.4);

    // Colonne [espace réservé, cadre extensible, espace réservé] plutôt
    // qu'un ratio deviné — voir doodle_canvas_shape.dart : cet écran n'a
    // pas les rangées d'outils de l'édition, donc on réserve la même
    // hauteur qu'elles occupent là-bas pour que le cadre obtienne
    // EXACTEMENT la même taille des deux côtés sur un même appareil (voir
    // demande utilisateur : "occuper toute la hauteur disponible à
    // l'édition, adapter la réception en fonction"). Répartie en deux
    // moitiés égales (haut/bas) plutôt que toute en bas, pour centrer
    // visuellement la carte (voir demande utilisateur : "centrer").
    final canvas = Column(
      children: [
        const SizedBox(height: kDoodleToolbarReservedHeight / 2),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Container(
              decoration: BoxDecoration(
                // Léger fond clair (voir demande utilisateur) — même
                // couleur que les bulles d'aperçu de DoodleHistoryScreen,
                // pour que le trait reste bien lisible même par-dessus un
                // écran chargé, au lieu de laisser tout transparaître.
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: borderColor),
              ),
              clipBehavior: Clip.antiAlias,
              child: PictionaryCanvas(strokes: widget.doodle.strokes, interactive: false),
            ),
          ),
        ),
        const SizedBox(height: kDoodleToolbarReservedHeight / 2),
      ],
    );

    // Une seule flèche retour (celle par défaut de l'AppBar, voir
    // DoodleComposeScreen qui fait pareil) — un second bouton "X" à droite
    // faisait doublon avec elle pour la même action (voir capture
    // utilisateur : flèche à gauche ET croix à droite, redondant).
    final appBar = AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: resolvedTextColor,
      title: Text(
        title,
        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: resolvedTextColor, shadows: textShadows),
      ),
      iconTheme: IconThemeData(color: resolvedTextColor, shadows: textShadows),
    );

    if (widget.showBackground) {
      return Scaffold(
        backgroundColor: theme!.background,
        appBar: appBar,
        body: ThemedBackground(child: SafeArea(child: canvas)),
      );
    }

    // Scaffold transparent (voir doc de classe) : l'écran du dessous doit
    // rester visible tel quel, seule la route (DoodleOverlay) pose un
    // léger voile sombre par-dessus pour garder le texte/trait lisibles
    // quel que soit ce qu'il y a en dessous.
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: appBar,
      body: SafeArea(child: canvas),
    );
  }
}

/// Route non opaque standard pour afficher un doodle par-dessus l'écran
/// déjà affiché (voir doc de classe [DoodleViewScreen]) — partagée entre
/// DoodleOverlay (arrivée en direct) et DoodleHistoryScreen (relecture
/// d'une bulle de l'historique en plein écran, voir demande utilisateur :
/// "cliquer sur un pour l'agrandir").
PageRouteBuilder<void> doodleViewRoute(Doodle doodle, {String? viewerUserId}) {
  return PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, animation, __) => FadeTransition(
      opacity: animation,
      child: DoodleViewScreen(doodle: doodle, viewerUserId: viewerUserId),
    ),
  );
}
