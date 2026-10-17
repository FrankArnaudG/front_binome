import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:showcaseview/showcaseview.dart';

import '../../../core/realtime_client.dart';
import '../../../l10n/locale_scope.dart';
import '../game_service.dart';
import '../nearby/nearby_comms.dart';

/// Réactions en direct pendant une partie à deux téléphones (voir demande
/// utilisateur : "à tout moment les deux binômes peuvent écrire un
/// commentaire... uniquement quand on utilise 2 téléphones") — bulle
/// flottante façon TikTok. Deux transports possibles :
/// - mode à distance ([boxId] renseigné) : éphémère côté SERVEUR (jamais
///   persistée, voir GameCommentSent) ;
/// - mode présentiel connecté ([nearbyComms] renseigné) : transite
///   uniquement par la connexion Bluetooth/Wifi Direct du jeu (voir
///   NearbyComms), jamais par le serveur ni la base de données (voir
///   demande utilisateur).
/// Dans les deux cas, façon commentaires en direct de TikTok (voir demande
/// utilisateur : "ca devait defiler vers le haut et disparaitre") : un
/// message apparaît en bas, remonte quand d'autres arrivent, puis s'estompe
/// et disparaît tout seul après [_commentLifetime] (un tap sur la croix
/// vide tout d'un coup). Rien n'est conservé au-delà. N'affiche/n'écoute
/// rien tant que [enabled] est faux (pass-and-play sur un seul appareil :
/// les deux joueurs regardent déjà le même écran).
class GameCommentOverlay extends StatefulWidget {
  final String? boxId;
  // Troisième transport, à côté de [boxId]/[nearbyComms] : une partie
  // d'ami hors-Box (voir demande utilisateur, phase 4 : généraliser le
  // chat en direct aux défis d'ami) — canal privé `{type}-session.{id}`
  // déjà abonné par le transport de jeu (voir RemoteMemoryGameTransport).
  final String? sessionType;
  final String? sessionId;
  final bool enabled;
  final NearbyComms? nearbyComms;
  final String myName;
  final String partnerName;
  // Guide pas-à-pas (voir demande utilisateur : "un guide sur comment
  // envoyer un message") — non-null uniquement pour faire apparaître une
  // bulle sur le bouton qui ouvre le compositeur de message.
  final GlobalKey? guideKey;

  const GameCommentOverlay({
    super.key,
    this.boxId,
    this.sessionType,
    this.sessionId,
    required this.enabled,
    this.nearbyComms,
    this.myName = '',
    this.partnerName = '',
    this.guideKey,
  });

  @override
  State<GameCommentOverlay> createState() => _GameCommentOverlayState();
}

/// Durée pendant laquelle un message reste visible avant de disparaître.
const _commentLifetime = Duration(seconds: 5);

class _LiveComment {
  final int id;
  final String prenom;
  final String text;
  const _LiveComment({required this.id, required this.prenom, required this.text});
}

class _GameCommentOverlayState extends State<GameCommentOverlay> {
  final List<_LiveComment> _comments = [];
  int _nextId = 0;
  bool _composing = false;
  bool _sending = false;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  StreamSubscription<NearbyChatMessage>? _nearbySubscription;
  final Map<int, Timer> _expiryTimers = {};

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    final nearbyComms = widget.nearbyComms;
    if (nearbyComms != null) {
      _nearbySubscription = nearbyComms.messages.listen(_onNearbyMessage);
    } else if (widget.boxId != null) {
      RealtimeClient.instance.subscribeToBox(widget.boxId!, onEvent: _onRealtimeEvent);
    } else if (_friendChannelName != null) {
      RealtimeClient.instance.subscribePrivate(_friendChannelName!, onEvent: _onRealtimeEvent);
    }
  }

  // Voir doc de classe : canal privé d'une partie d'ami hors-Box, null si
  // ni [sessionType]/[sessionId] ne sont fournis (mode binôme/présentiel).
  String? get _friendChannelName {
    final type = widget.sessionType;
    final id = widget.sessionId;
    return (type != null && id != null) ? '${type.replaceAll('_', '-')}-session.$id' : null;
  }

  @override
  void dispose() {
    if (widget.enabled) {
      if (widget.nearbyComms != null) {
        _nearbySubscription?.cancel();
      } else if (widget.boxId != null) {
        RealtimeClient.instance.unsubscribeFromBox(widget.boxId!, onEvent: _onRealtimeEvent);
      } else if (_friendChannelName != null) {
        RealtimeClient.instance.unsubscribePrivate(_friendChannelName!, onEvent: _onRealtimeEvent);
      }
    }
    for (final timer in _expiryTimers.values) {
      timer.cancel();
    }
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.event != 'GameCommentSent') return;
    final data = event.data;
    if (data == null) return;
    final prenom = data['prenom'] as String? ?? '';
    final text = data['text'] as String?;
    if (text == null || text.trim().isEmpty) return;
    _appendComment(prenom, text);
  }

  void _onNearbyMessage(NearbyChatMessage message) {
    // Mes propres messages sont déjà affichés immédiatement à l'envoi
    // (voir _send) — pas d'écho serveur à attendre ici, contrairement au
    // mode à distance.
    if (message.fromMe) return;
    _appendComment(widget.partnerName, message.text);
  }

  void _appendComment(String prenom, String text) {
    if (!mounted) return;
    final id = _nextId++;
    setState(() {
      _comments.add(_LiveComment(id: id, prenom: prenom, text: text));
    });
    // Disparaît tout seul (la bulle s'estompe elle-même juste avant, voir
    // _CommentBubble) — retirée de la liste une fois complètement invisible.
    _expiryTimers[id] = Timer(_commentLifetime, () {
      _expiryTimers.remove(id);
      if (!mounted) return;
      setState(() => _comments.removeWhere((c) => c.id == id));
    });
    // La zone défilante est en `reverse: true` (voir _buildBubbleLog) :
    // l'offset 0 correspond déjà au dernier message (visuellement en bas),
    // donc y revenir fait remonter les bulles précédentes au fur et à
    // mesure que le contenu déborde du cadre visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    });
  }

  void _clearAll() {
    if (!mounted) return;
    for (final timer in _expiryTimers.values) {
      timer.cancel();
    }
    _expiryTimers.clear();
    setState(() => _comments.clear());
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _controller.clear();
    final nearbyComms = widget.nearbyComms;
    if (nearbyComms != null) {
      // Aucun aller-retour serveur en présentiel connecté — envoi direct
      // sur la connexion Nearby et affichage immédiat (voir doc de classe).
      nearbyComms.sendText(text);
      _appendComment(widget.myName, text);
    } else {
      try {
        await GameService.instance.sendGameComment(text, sessionType: widget.sessionType, sessionId: widget.sessionId);
      } catch (_) {
        // Éphémère et non critique : un envoi raté n'affecte pas la partie,
        // on se contente de ne pas relancer l'utilisateur avec une erreur.
      }
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      _composing = false;
    });
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();

    // Le clavier doit se superposer au jeu, jamais le pousser (voir demande
    // utilisateur — le Scaffold porteur passe `resizeToAvoidBottomInset:
    // false`) : on remonte donc nous-mêmes la zone de saisie/les bulles de
    // la hauteur du clavier pour qu'elles restent visibles au-dessus.
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Stack(
          children: [
            Positioned(
              left: 12,
              right: 72,
              bottom: 96 + keyboardInset,
              child: _buildBubbleLog(context),
            ),
            Positioned(
              right: 16,
              bottom: 24 + keyboardInset,
              child: _composing ? _buildComposer(context) : _buildFab(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubbleLog(BuildContext context) {
    if (_comments.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Nettement au-dessus du journal, à gauche (voir demande
        // utilisateur) — jamais superposée au message le plus haut.
        GestureDetector(
          onTap: _clearAll,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            width: 22,
            height: 22,
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
            child: const Icon(Icons.close_rounded, color: Colors.white70, size: 14),
          ),
        ),
        // NeverScrollable : c'est le widget qui pilote le défilement
        // (auto-scroll vers le bas à chaque nouveau commentaire), pas le
        // doigt — les commentaires les plus anciens sortent juste du cadre
        // visible au fur et à mesure (voir doc de classe), rien à faire
        // glisser manuellement.
        SizedBox(
          height: 220,
          child: IgnorePointer(
            child: ClipRect(
              // `reverse: true` avec les commentaires dans l'ordre
              // chronologique normal (le plus récent en dernier enfant) :
              // tant que le contenu tient dans les 220px, il reste ancré
              // EN BAS du cadre (voir demande utilisateur : "il doit
              // apparaître en bas") ; une fois qu'il déborde, l'offset 0
              // montre justement le dernier message, les plus anciens
              // sortant par le haut.
              child: SingleChildScrollView(
                controller: _scrollController,
                reverse: true,
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final comment in _comments)
                      _CommentBubble(key: ValueKey(comment.id), prenom: comment.prenom, text: comment.text),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFab(BuildContext context) {
    final fab = FloatingActionButton.small(
      heroTag: 'game_comment_fab_${widget.boxId ?? widget.nearbyComms?.endpointId ?? 'local'}',
      backgroundColor: Colors.black.withValues(alpha: 0.55),
      elevation: 0,
      onPressed: () {
        setState(() => _composing = true);
        WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
      },
      child: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white),
    );
    final guideKey = widget.guideKey;
    if (guideKey == null) return fab;
    return Showcase(
      key: guideKey,
      title: 'Envoie un message',
      description: 'Tape ici pour écrire un petit mot à ton binôme pendant la partie.',
      targetShapeBorder: const CircleBorder(),
      child: fab,
    );
  }

  Widget _buildComposer(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                maxLength: 140,
                style: GoogleFonts.nunito(color: Colors.white, fontSize: 14),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  counterText: '',
                  hintText: LocaleScope.t(context, 'game_comment_hint'),
                  hintStyle: GoogleFonts.nunito(color: Colors.white70, fontSize: 14),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              tooltip: LocaleScope.t(context, 'game_comment_send'),
              onPressed: _sending ? null : _send,
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
              onPressed: () {
                _controller.clear();
                _focusNode.unfocus();
                setState(() => _composing = false);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Une bulle de commentaire — apparaît EN BAS puis remonte en s'estompant
/// vers son opacité finale, glisse lentement vers le haut pendant toute sa
/// durée de vie, s'estompe sur la fin et disparaît (voir demande utilisateur : "comme les
/// commentaires live de TikTok" ; retrait de la liste par
/// [_GameCommentOverlayState] à [_commentLifetime]).
class _CommentBubble extends StatefulWidget {
  final String prenom;
  final String text;

  const _CommentBubble({super.key, required this.prenom, required this.text});

  @override
  State<_CommentBubble> createState() => _CommentBubbleState();
}

class _CommentBubbleState extends State<_CommentBubble> with TickerProviderStateMixin {
  // Décalage en PIXELS fixes (pas relatif à la taille de la bulle, voir
  // demande utilisateur : "j'ai testé, pas de défilement" — un décalage
  // relatif type SlideTransition(begin: Offset(0, 0.6)) donnait un
  // mouvement de quelques pixels à peine pour un message court, donc
  // quasi invisible) : ici toujours 42px de remontée, quel que soit le
  // texte.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();
  late final Animation<double> _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<double> _rise = Tween<double>(
    begin: 42,
    end: 0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  // Sortie : dans la dernière seconde et demie avant le retrait, la bulle
  // s'estompe (elle glisse déjà vers le haut, voir [_drift]).
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  // Glissement continu vers le haut pendant toute la durée de vie (voir
  // demande utilisateur : "il va glisser vers le haut pendant 5 secondes").
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: _commentLifetime,
  )..forward();
  Timer? _exitTimer;

  @override
  void initState() {
    super.initState();
    _exitTimer = Timer(_commentLifetime - const Duration(milliseconds: 1500), () {
      if (mounted) _exit.forward();
    });
  }

  @override
  void dispose() {
    _exitTimer?.cancel();
    _exit.dispose();
    _drift.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_controller, _exit, _drift]),
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _rise.value - 70 * _drift.value),
        child: Opacity(opacity: (_fade.value * (1 - _exit.value)).clamp(0.0, 1.0), child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(18),
        ),
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '${widget.prenom}  ',
                style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              TextSpan(text: widget.text, style: GoogleFonts.nunito(fontSize: 13, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}
