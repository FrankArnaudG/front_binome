import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/app_router.dart';
import '../../../core/local_cache.dart';
import '../../../l10n/locale_scope.dart';
import '../../../models/send.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../../games/game_card_inbox_service.dart';
import '../../games/pending_send_helpers.dart';

/// Bulle flottante persistante (voir GameCardInboxService) : apparaît dès
/// qu'une carte-question ou une story en émojis attend une action, visible
/// sur tout l'app (montée dans AppShell) — pas seulement le Dashboard.
/// Utilise [AppRouter.navigatorKey] plutôt que Navigator.of(context) :
/// AppShell vit au-dessus du Navigator dans l'arbre de widgets, pas en
/// dessous. Déplaçable au doigt n'importe où sur l'écran (voir
/// _GameCardBubbleState._position) — pour ne jamais rester coincée
/// au-dessus d'un contenu qu'on veut lire en dessous.
class GameCardBubble extends StatefulWidget {
  const GameCardBubble({super.key});

  @override
  State<GameCardBubble> createState() => _GameCardBubbleState();
}

class _GameCardBubbleState extends State<GameCardBubble> {
  static const _size = 62.0;
  static const _positionCacheKey = 'cache_game_card_bubble_position';

  // Coin haut-gauche de la bulle, `null` tant qu'on ne l'a jamais fait
  // glisser CETTE session (position par défaut recalculée à chaque build
  // pour rester correcte si l'écran change de taille) — voir aussi
  // [_savedFraction], la position sauvegardée d'une session précédente.
  Offset? _position;

  // Dernière position glissée par l'utilisateur·rice, sauvegardée en
  // fraction (0..1) de l'espace disponible plutôt qu'en pixels absolus —
  // reste valide même si la taille d'écran change (rotation, appareil
  // différent). `null` tant qu'aucune position n'a jamais été sauvegardée
  // (ou pas encore relue depuis le disque) : dans ce cas seulement, repli
  // sur la position par défaut codée en dur.
  Offset? _savedFraction;

  // Position (globale) et coin de la bulle au moment du onPointerDown —
  // `null` hors geste en cours. Distance totale parcourue depuis : sert à
  // distinguer un tap d'un glissement à la fin du geste (voir
  // onPointerUp) — GestureDetector (onTap + onPanUpdate) ne fonctionnait
  // pas ici : les deux se marchent dessus dans l'arène de gestes.
  Offset? _dragStartPointer;
  Offset? _dragStartPosition;
  double _dragDistance = 0;

  // Vrai pendant l'aller-retour réseau (Game/GameBox/user) pour ouvrir la
  // vraie discussion (voir _openSend) — la bulle reste visible avec une
  // roue de chargement à la place de l'avatar au lieu de disparaître
  // instantanément puis laisser un blanc de quelques secondes avant que
  // l'écran s'ouvre, ce qui perdait l'utilisateur·rice (constaté en réel).
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _loadSavedPosition();
  }

  Future<void> _loadSavedPosition() async {
    final cached = await LocalCache.instance.readJson<Map<String, dynamic>>(_positionCacheKey);
    if (cached == null || !mounted) return;
    final fx = (cached['fx'] as num?)?.toDouble();
    final fy = (cached['fy'] as num?)?.toDouble();
    if (fx == null || fy == null) return;
    setState(() => _savedFraction = Offset(fx, fy));
  }

  /// Sauvegarde la position glissée pour qu'elle redevienne le défaut au
  /// prochain lancement de l'app — un simple tap (pas de vrai glissement)
  /// ne doit rien changer à la position mémorisée.
  Future<void> _savePosition(Offset position, double maxX, double maxY) async {
    if (maxX <= 0 || maxY <= 0) return;
    await LocalCache.instance.writeJson(_positionCacheKey, {
      'fx': position.dx / maxX,
      'fy': position.dy / maxY,
    });
  }

  /// Un seul envoi en attente → on l'ouvre directement (comportement
  /// historique). Plusieurs → un choix s'impose, voir _showPendingList.
  /// N'utilise jamais le `context` local de la bulle pour naviguer/ouvrir
  /// une feuille modale : GameCardBubble vit dans AppShell, monté AUTOUR du
  /// Navigator (donc pas un de ses descendants) — `showModalBottomSheet`
  /// avec ce context lève "context does not include a Navigator" (constaté
  /// en réel). [AppRouter.navigatorKey.currentContext] est, lui, toujours
  /// un descendant du Navigator (celui de la route active).
  void _openCard() {
    if (_opening) return;
    final pending = GameCardInboxService.instance.pending;
    if (pending.isEmpty) return;
    if (pending.length == 1) {
      _openSend(pending.first);
      return;
    }
    _showPendingList(pending);
  }

  /// Ouvre la vraie discussion concernée (voir openPendingSend, partagée
  /// avec InboxToast) — la bulle reste visible avec sa roue de chargement
  /// pendant tout l'aller-retour réseau (carte-question : besoin du
  /// Game/GameBox complets) plutôt que de disparaître instantanément puis
  /// laisser un blanc.
  Future<void> _openSend(Send send) async {
    setState(() => _opening = true);
    await openPendingSend(send);
    if (mounted) setState(() => _opening = false);
  }

  /// Feuille listant chaque envoi en attente (avatar + aperçu) — un tap
  /// dessus ouvre directement la conversation concernée, comme si on avait
  /// tapé la bulle alors qu'il n'y en avait qu'une seule.
  Future<void> _showPendingList(List<Send> pending) async {
    final navContext = AppRouter.navigatorKey.currentContext;
    if (navContext == null) return;
    final theme = ThemeScope.paletteOf(navContext);

    final selected = await showModalBottomSheet<Send>(
      context: navContext,
      backgroundColor: theme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: theme.textOnBackgroundMuted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                '${pending.length} en attente',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: theme.textOnBackground),
              ),
              const SizedBox(height: 4),
              Text(
                'Choisis celle que tu veux ouvrir.',
                style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: pending.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final send = pending[index];
                    return _PendingTile(theme: theme, send: send, onTap: () => Navigator.of(sheetContext).pop(send));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selected != null) _openSend(selected);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: GameCardInboxService.instance,
      builder: (context, _) {
        final pending = GameCardInboxService.instance.pending;
        if (pending.isEmpty) return const SizedBox.shrink();

        // Photo de l'expéditeur·rice du tout premier envoi en attente —
        // pour reconnaître tout de suite qui a envoyé, plutôt qu'une simple
        // icône générique.
        final senderAvatar = pending.first.sender?.avatar;
        final hasAvatar = senderAvatar != null && senderAvatar.isNotEmpty;

        // Positioned.fill donne les bornes exactes du Stack parent (voir
        // AppShell) au LayoutBuilder ci-dessous — nécessaire pour borner le
        // glissement (jamais à moitié hors écran) et pour placer la position
        // par défaut en haut-gauche avant tout glissement.
        return Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxX = constraints.maxWidth <= _size ? 0.0 : constraints.maxWidth - _size;
              final maxY = constraints.maxHeight <= _size ? 0.0 : constraints.maxHeight - _size;
              // Position sauvegardée d'une session précédente (voir
              // _loadSavedPosition) si elle existe — sinon repli sur la
              // position par défaut codée en dur (à droite, sous l'en-tête,
              // au niveau du haut de la carte "jours ensemble"),
              // MediaQuery.padding.top pour ne jamais empiéter sur la barre
              // de statut/l'encoche : le Scaffold de AppShell n'a pas de
              // SafeArea propre, contrairement aux écrans qu'il enveloppe.
              final topInset = MediaQuery.of(context).padding.top;
              final defaultPosition = _savedFraction != null
                  ? Offset(_savedFraction!.dx * maxX, _savedFraction!.dy * maxY)
                  : Offset(maxX - 16, topInset + 220);
              final current = _position ?? defaultPosition;
              final clamped = Offset(current.dx.clamp(0, maxX), current.dy.clamp(0, maxY));

              return Stack(
                children: [
                  Positioned(
                    left: clamped.dx,
                    top: clamped.dy,
                    // Listener plutôt que GestureDetector : onPointerDown/Up
                    // reçoivent TOUJOURS l'événement, contrairement à
                    // onPanStart/onPanEnd qui exigent que le doigt dépasse
                    // d'abord un seuil de mouvement (le "touch slop") avant
                    // même de commencer à reconnaître le geste — un vrai tap
                    // immobile ne le dépasse jamais, donc onPanStart/onPanEnd
                    // ne se déclenchaient tout simplement pas.
                    child: Listener(
                      onPointerDown: (event) {
                        _dragStartPointer = event.position;
                        _dragStartPosition = _position ?? clamped;
                        _dragDistance = 0;
                      },
                      onPointerMove: (event) {
                        if (_dragStartPointer == null || _dragStartPosition == null) return;
                        final delta = event.position - _dragStartPointer!;
                        _dragDistance = delta.distance;
                        setState(() {
                          _position = Offset(
                            (_dragStartPosition!.dx + delta.dx).clamp(0, maxX),
                            (_dragStartPosition!.dy + delta.dy).clamp(0, maxY),
                          );
                        });
                      },
                      onPointerUp: (_) {
                        if (_dragDistance < 6) {
                          _openCard();
                        } else if (_position != null) {
                          // Vrai glissement (pas juste un tap) — mémorisé
                          // pour redevenir le défaut au prochain lancement
                          // de l'app (voir _savePosition).
                          _savePosition(_position!, maxX, maxY);
                        }
                        _dragStartPointer = null;
                        _dragStartPosition = null;
                      },
                      onPointerCancel: (_) {
                        _dragStartPointer = null;
                        _dragStartPosition = null;
                      },
                      child: Container(
                        width: _size,
                        height: _size,
                        decoration: BoxDecoration(
                          // "Squircle" (carré très arrondi) plutôt qu'un
                          // cercle classique — se démarque du reste des
                          // avatars ronds de l'app, plus proche d'une puce
                          // de messagerie moderne.
                          borderRadius: BorderRadius.circular(22),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF3B5C), Color(0xFF7B2D8E)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(color: const Color(0xFFFF3B5C).withValues(alpha: 0.45), blurRadius: 18, offset: const Offset(0, 8)),
                            BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 10, offset: const Offset(0, 3)),
                          ],
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: hasAvatar
                                  ? Image.network(
                                      senderAvatar,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                      errorBuilder: (context, error, stackTrace) => const Center(
                                        child: Icon(Icons.style_rounded, color: Colors.white, size: 26),
                                      ),
                                    )
                                  : const ColoredBox(
                                      color: Colors.transparent,
                                      child: Center(child: Icon(Icons.style_rounded, color: Colors.white, size: 26)),
                                    ),
                            ),
                            // Voile + roue de chargement pendant l'aller-
                            // retour réseau (voir _opening) — la bulle
                            // reste visible et donne un retour clair plutôt
                            // que de disparaître instantanément puis
                            // laisser un blanc de quelques secondes.
                            if (_opening)
                              Positioned.fill(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(22),
                                  child: ColoredBox(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    child: const Center(
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            // Petit badge "carte" en coin — sans lui, une
                            // photo de profil seule ne dirait plus "carte de
                            // jeu en attente", juste "quelqu'un" (même
                            // principe que les badges de type sur les
                            // avatars du Carnet de bord).
                            if (hasAvatar)
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(colors: [Color(0xFFFF3B5C), Color(0xFF7B2D8E)]),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(iconForPendingSend(pending.first), color: Colors.white, size: 12),
                                ),
                              ),
                            if (pending.length > 1)
                              Positioned(
                                top: -2,
                                right: -2,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                  alignment: Alignment.center,
                                  child: Text(
                                    '${pending.length}',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFFF3B5C)),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Une ligne de la feuille "plusieurs en attente" (voir
/// _GameCardBubbleState._showPendingList) — avatar de l'expéditeur·rice,
/// aperçu du contenu (question ou émojis), badge de type.
class _PendingTile extends StatelessWidget {
  final ThemePalette theme;
  final Send send;
  final VoidCallback onTap;

  const _PendingTile({required this.theme, required this.send, required this.onTap});

  String get _senderName => send.sender?.prenom ?? send.sender?.name ?? 'Ton binôme';

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: theme.primary.withValues(alpha: 0.15),
                backgroundImage: send.sender?.avatar != null ? NetworkImage(send.sender!.avatar!) : null,
                child: send.sender?.avatar == null ? Text(_senderName.isNotEmpty ? _senderName[0] : '?') : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _senderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.nunito(fontWeight: FontWeight.w800, fontSize: 13, color: theme.textOnBackground),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      previewForPendingSend(send, LocaleScope.of(context).current.code),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.nunito(fontSize: 13, fontStyle: FontStyle.italic, color: theme.textOnBackgroundMuted),
                    ),
                  ],
                ),
              ),
              Icon(iconForPendingSend(send), size: 18, color: theme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
