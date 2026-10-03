import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../core/last_seen_label.dart';
import '../../core/realtime_client.dart';
import '../../l10n/locale_scope.dart';
import '../../models/app_user.dart';
import '../../models/heartbeat_image.dart';
import '../../models/send.dart';
import '../../models/send_reaction.dart';
import '../../models/slide.dart';
import '../../theme/handwritten_fonts.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/composer_actions.dart';
import '../../widgets/send_status_tick.dart';
import '../box/couple_profile_screen.dart';
import '../home/widgets/couple_avatars_badge.dart';
import '../shop/wallet_balance_notifier.dart';
import 'content_service.dart';
import 'unread_timeline_service.dart';
import 'packs_screen.dart';
import 'widgets/eternal_rose.dart';
import 'widgets/heartbeat_card.dart';
import 'widgets/heartbeat_reply_modal.dart';
import 'widgets/pack_reply_modal.dart';
import 'widgets/quantum_love_heart.dart';
import 'widgets/realistic_black_rose.dart';
import 'widgets/sketched_love_heart.dart';
import 'widgets/slide_pack_viewer.dart';
import 'widgets/slide_visual_card.dart';
import 'widgets/word_heart.dart';

/// Vue immersive plein écran d'un envoi (slide/cadeau/heartbeat) — habillée
/// façon en-tête et bulle de chat (verre dépoli, alignée du côté de
/// l'expéditeur) pour une lecture plus organisée, mais SANS saisie de texte
/// libre ni fonctionnalité d'appel : on reste une boîte à souvenirs, pas une
/// messagerie. Réagir se fait via le petit cercle à l'angle de la bulle, qui
/// déploie un set fixe d'émojis.
class SlideDetailScreen extends StatefulWidget {
  final Send send;
  final bool isMine;
  final AppUser user;

  const SlideDetailScreen({
    super.key,
    required this.send,
    required this.isMine,
    required this.user,
  });

  @override
  State<SlideDetailScreen> createState() => _SlideDetailScreenState();
}

class _SlideDetailScreenState extends State<SlideDetailScreen> {
  late Send _send;
  bool _togglingFavorite = false;
  bool _reacting = false;
  bool _reactionPickerOpen = false;
  bool _sendingHeartbeatReply = false;
  bool _composerActionsOpen = false;
  final _messageComposeController = TextEditingController();
  // Messages encore en vol (voir _sendMessage) — jamais mêlés à [_replies]
  // elle-même, seulement pour l'affichage (voir build()).
  List<_PendingReply> _pendingReplies = [];
  List<Slide>? _packSlides;
  bool _loadingPackSlides = false;
  // Poème supprimé ou dépublié depuis l'envoi (le serveur répond 404).
  bool _packUnavailable = false;
  // Plus récente d'abord (voir RepliesPage/SendController::replies) — plus
  // pratique pour la pagination/fusion ci-dessous (le curseur "before" et la
  // comparaison "plus ancien que" s'expriment naturellement sur cet ordre) ;
  // build() les reparcourt à l'envers pour l'affichage (voir _buildReplies).
  List<Send> _replies = [];
  // Messages reçus déjà signalés comme lus (ou en cours de l'être) — évite de
  // rappeler le serveur pour le même message à chaque rechargement du fil.
  final Set<String> _seenRequested = {};
  bool _hasMoreReplies = false;
  bool _loadingMoreReplies = false;
  // Le tout premier remplissage doit amener l'écran sur le dernier échange
  // SI le fil déborde de l'écran — une seule fois, pas à chaque
  // rafraîchissement de polling (sinon impossible de lire l'historique sans
  // se faire ramener en bas toutes les 10s).
  bool _hasDoneInitialScroll = false;
  // Vrai tant que l'utilisateur est au (tout) bas du fil — mis à jour en
  // continu par le ScrollController (voir initState), jamais recalculé à
  // la volée à chaque nouvel échange : un calcul "à peu près en bas" fait
  // seulement au moment d'un nouvel échange se déclenchait à tort sur un
  // fil pas beaucoup plus long qu'un écran, ramenant en bas au polling
  // suivant pendant qu'on lisait l'historique tout en haut (constaté en
  // réel).
  bool _followLatest = true;
  Timer? _pollTimer;
  final ScrollController _scrollController = ScrollController();
  // "Partenaire en ligne" (voir PartnerPresenceBadge) — même canal presence
  // que le Dashboard, juste un écouteur de plus dessus (voir
  // RealtimeClient : plusieurs écrans peuvent suivre le même canal Box en
  // même temps).
  bool _partnerPresent = false;

  @override
  void initState() {
    super.initState();
    _send = widget.send;
    if (_send.isPack && _send.pack != null) {
      // Slides déjà connues (cache mémoire) : affichées dès la première image,
      // sans chargement — le rafraîchissement se fait ensuite en silence.
      _packSlides = ContentService.instance.cachedPackSync(_send.pack!.id)?.slides;
      _loadPackSlides();
    }
    _loadCachedRepliesThenRefresh();
    // Nouvelles réponses/réactions en direct pendant que l'écran est ouvert
    // (voir RealtimeClient) — jamais la seule source de vérité, d'où le
    // polling de secours en parallèle (même principe que BoxWaitingScreen).
    RealtimeClient.instance.subscribeToBox(
      _send.boxId,
      onEvent: _onRealtimeEvent,
      onPresenceChange: _onPresenceChange,
    );
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadLatestReplies());
    // Réactive le bouton d'envoi dès que le champ contient du texte (clavier
    // système classique — voir demande utilisateur : "un clavier classique").
    _messageComposeController.addListener(() => setState(() {}));
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      // Approche du haut de l'écran (où vit l'en-tête/les plus anciennes
      // réponses déjà chargées) : charge la page suivante avant d'y
      // arriver vraiment, comme un vrai fil de discussion.
      if (_hasMoreReplies && !_loadingMoreReplies && position.pixels <= 200) {
        _loadMoreReplies();
      }
      // Suit la position réelle en continu (tolérance serrée, juste
      // l'arrondi) plutôt qu'un calcul "à peu près en bas" fait au moment
      // d'un nouvel échange — sinon, sur un fil pas beaucoup plus long
      // qu'un écran, cette approximation pouvait se déclencher même en
      // ayant remonté tout en haut, ramenant en bas au polling suivant
      // pendant qu'on lisait l'historique (constaté en réel).
      _followLatest = position.pixels >= position.maxScrollExtent - 4;
    });
  }

  /// Affiche la dernière page mise en cache tout de suite (voir
  /// ContentService.cachedReplies) au lieu d'un fil vide le temps du
  /// premier fetch, puis lance quand même le vrai chargement réseau
  /// derrière — appelé une seule fois, depuis initState.
  Future<void> _loadCachedRepliesThenRefresh() async {
    final cached = await ContentService.instance.cachedReplies(_send.id);
    if (cached != null && mounted && _replies.isEmpty) {
      setState(() {
        _replies = cached.items;
        _hasMoreReplies = cached.hasMore;
      });
      _scrollToBottomIfOverflowingOnce();
    }
    _loadLatestReplies();
  }

  /// (Re)charge la page la plus récente — chargement initial ET polling de
  /// secours. Fusionne plutôt que remplace : garde les réponses plus
  /// anciennes déjà chargées via [_loadMoreReplies], n'ajoute que celles
  /// réellement nouvelles depuis le dernier chargement.
  Future<void> _loadLatestReplies() async {
    try {
      final page = await ContentService.instance.fetchReplies(_send.id);
      if (!mounted) return;
      final newIds = page.items.map((r) => r.id).toSet();
      // ID le plus ancien de cette page — tout ce qui, dans l'ancien état,
      // était déjà plus ancien que ça vient forcément d'un chargement
      // manuel de page suivante (_loadMoreReplies) et doit être conservé.
      final oldestNewId = page.items.isEmpty ? null : page.items.last.id;
      final olderAlreadyLoaded = oldestNewId == null
          ? const <Send>[]
          : _replies.where((r) => !newIds.contains(r.id) && r.id.compareTo(oldestNewId) < 0).toList();
      setState(() {
        _replies = [...page.items, ...olderAlreadyLoaded];
        // Un fetch sans curseur fait toujours autorité sur "y a-t-il plus
        // ancien" pour la fenêtre qu'il couvre.
        if (olderAlreadyLoaded.isEmpty) _hasMoreReplies = page.hasMore;
      });
      if (_followLatest) _scrollToBottomSoon();
      _scrollToBottomIfOverflowingOnce();
      _markIncomingSeen();
    } catch (_) {
      // best effort
    }
  }

  /// Tant que la discussion est ouverte, tout ce que le binôme nous a envoyé
  /// est sous nos yeux : on le signale comme lu (coches bleues chez lui, via
  /// SendSeen) sans exiger d'appuyer sur chaque message — comme une messagerie
  /// classique. Un message n'est signalé qu'une fois ; en cas d'échec réseau
  /// il sera retenté au prochain rechargement du fil.
  void _markIncomingSeen() {
    final me = widget.user.id;
    final unread = [..._replies, _send]
        .where((s) => s.recipientId == me && !s.isSeen && _seenRequested.add(s.id))
        .toList();
    if (unread.isEmpty) return;
    var marked = 0;
    for (final send in unread) {
      ContentService.instance.markSeen(send.id).then((updated) {
        marked++;
        if (!mounted) return;
        _applySeen(send.id, updated.seenAt ?? DateTime.now());
        if (marked == unread.length) UnreadTimelineService.instance.refresh(me);
      }, onError: (_) => _seenRequested.remove(send.id));
    }
  }

  /// Réponses plus anciennes que celles déjà affichées — déclenché en
  /// approchant le haut de l'écran (voir le ScrollController dans
  /// initState). Ajoutées en FIN de [_replies] (la plus ancienne dans notre
  /// ordre de stockage) ; [_stabilizeScrollAfterPrepend] compense le
  /// décalage visuel que ce nouveau contenu, inséré près du haut de l'écran,
  /// causerait sinon.
  Future<void> _loadMoreReplies() async {
    if (!_hasMoreReplies || _loadingMoreReplies || _replies.isEmpty) return;
    setState(() => _loadingMoreReplies = true);
    final previousExtent = _scrollController.hasClients ? _scrollController.position.maxScrollExtent : null;
    try {
      final page = await ContentService.instance.fetchReplies(_send.id, beforeId: _replies.last.id);
      if (mounted) {
        setState(() {
          _replies = [..._replies, ...page.items];
          _hasMoreReplies = page.hasMore;
        });
        _stabilizeScrollAfterPrepend(previousExtent);
      }
    } catch (_) {
      // best effort — l'utilisateur pourra réessayer en re-scrollant.
    } finally {
      if (mounted) setState(() => _loadingMoreReplies = false);
    }
  }

  /// Après avoir ajouté du contenu plus ancien (donc affiché plus haut à
  /// l'écran, voir _buildReplies), compense le décalage pour que ce que
  /// l'utilisateur était en train de lire reste exactement à l'écran, au
  /// lieu de sauter brutalement plus bas.
  void _stabilizeScrollAfterPrepend(double? previousExtent) {
    if (previousExtent == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final addedHeight = _scrollController.position.maxScrollExtent - previousExtent;
      if (addedHeight > 0) {
        _scrollController.jumpTo(_scrollController.position.pixels + addedHeight);
      }
    });
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  /// Amène sur le dernier échange, UNE SEULE fois, et seulement si le fil
  /// déborde déjà de l'écran — sinon (une poignée de messages) le contenu
  /// reste naturellement ancré en haut, sous la carte d'origine, comme
  /// n'importe quelle liste qui ne remplit pas l'écran.
  void _scrollToBottomIfOverflowingOnce() {
    if (_hasDoneInitialScroll) return;
    _hasDoneInitialScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (_scrollController.position.maxScrollExtent > 0) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _onPresenceChange(Set<String> memberIds) {
    if (!mounted) return;
    final partnerId = _partner?.id;
    final present = partnerId != null && memberIds.contains(partnerId);
    if (present != _partnerPresent) setState(() => _partnerPresent = present);
  }

  /// Une nouvelle réponse ou réaction arrivée en direct (voir
  /// RealtimeClient) pendant que cet écran est ouvert — ne concerne cet
  /// écran que si elle porte sur CET envoi précis, sinon ignorée (les
  /// autres écrans ont leur propre abonnement).
  void _onRealtimeEvent(RealtimeEvent event) {
    if (!mounted) return;
    if (event.event == 'SendCreated') {
      final sendJson = event.data?['send'] as Map<String, dynamic>?;
      if (sendJson == null) return;
      final newSend = Send.fromJson(sendJson);
      if (newSend.replyToSendId != _send.id) return;
      if (_replies.any((r) => r.id == newSend.id)) return;
      setState(() {
        // En tête : la plus récente vient en premier dans notre ordre de
        // stockage (voir _buildReplies pour l'ordre d'affichage réel).
        _replies = [newSend, ..._replies];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _markIncomingSeen();
        });
        // Si CET écho est la confirmation d'un envoi que NOUS venons de
        // faire (voir _sendMessage/_pendingReplies), retire tout de suite
        // sa bulle optimiste plutôt que d'attendre le retour HTTP de
        // _sendPendingReply — sinon les deux bulles (celle en vol et celle
        // tout juste confirmée par le serveur) restent visibles ensemble
        // le temps de cet aller-retour réseau (voir demande utilisateur :
        // "la bulle dur message se duplique un laps de temps et l'une
        // disparait", constaté une seconde fois malgré une comparaison de
        // contenu, sans doute à cause d'une structure de payload temps réel
        // légèrement différente de la réponse HTTP). On retire la PLUS
        // ANCIENNE bulle en vol du même type (texte/émoji) plutôt que de
        // comparer le contenu : les envois d'un même utilisateur arrivent
        // dans l'ordre, donc la plus ancienne encore en vol correspond
        // forcément à cet écho-ci. Restreint au même type pour ne jamais
        // toucher par erreur un envoi en vol d'un tout autre mécanisme
        // (poème/battement de cœur), qui ne passe pas par _pendingReplies.
        if (newSend.senderId == widget.user.id &&
            (newSend.isTextReply || newSend.isEmojiReply) &&
            _pendingReplies.isNotEmpty) {
          _pendingReplies = [..._pendingReplies]..removeAt(0);
        }
      });
      // Un nouvel échange ne doit ramener en bas QUE si on y était déjà —
      // sinon ça arracherait l'utilisateur à l'historique qu'il est en
      // train de lire plus haut.
      if (_followLatest) _scrollToBottomSoon();
    } else if (event.event == 'SendReacted') {
      final reactionJson = event.data?['reaction'] as Map<String, dynamic>?;
      if (reactionJson == null) return;
      final reaction = SendReaction.fromJson(reactionJson);
      if (reaction.sendId != _send.id) return;
      // Remplace SA réaction précédente (même userId) plutôt que de
      // s'accumuler à côté — qui l'a envoyé ET qui l'a reçu peuvent chacun·e
      // avoir la sienne (voir SendReactionController::store), mais un même
      // membre du couple qui change d'avis ne doit en garder qu'une.
      setState(() => _send = _send.copyWith(
            reactions: [..._send.reactions.where((r) => r.userId != reaction.userId), reaction],
          ));
    } else if (event.event == 'SendSeen') {
      final sendId = event.data?['send_id'] as String?;
      if (sendId == null) return;
      final seenAtStr = event.data?['seen_at'] as String?;
      _applySeen(sendId, seenAtStr != null ? DateTime.parse(seenAtStr) : DateTime.now());
    } else if (event.event == 'SendDelivered') {
      final sendIds = (event.data?['send_ids'] as List?)?.map((e) => e as String).toList();
      if (sendIds == null || sendIds.isEmpty) return;
      final deliveredAtStr = event.data?['delivered_at'] as String?;
      _applyDelivered(sendIds, deliveredAtStr != null ? DateTime.parse(deliveredAtStr) : DateTime.now());
    }
  }

  void _applySeen(String sendId, DateTime seenAt) {
    setState(() {
      if (_send.id == sendId) _send = _send.copyWith(status: 'seen', seenAt: seenAt);
      _replies = _replies.map((r) => r.id == sendId ? r.copyWith(status: 'seen', seenAt: seenAt) : r).toList();
    });
  }

  void _applyDelivered(List<String> sendIds, DateTime deliveredAt) {
    setState(() {
      if (sendIds.contains(_send.id) && _send.status == 'sent') {
        _send = _send.copyWith(status: 'delivered', deliveredAt: deliveredAt);
      }
      _replies = _replies
          .map((r) => sendIds.contains(r.id) && r.status == 'sent'
              ? r.copyWith(status: 'delivered', deliveredAt: deliveredAt)
              : r)
          .toList();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    RealtimeClient.instance.unsubscribeFromBox(
      _send.boxId,
      onEvent: _onRealtimeEvent,
      onPresenceChange: _onPresenceChange,
    );
    _messageComposeController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPackSlides() async {
    // Pas de rond de chargement si on a déjà de quoi afficher.
    if (_packSlides == null) setState(() => _loadingPackSlides = true);
    try {
      final pack = await ContentService.instance.fetchPack(_send.pack!.id);
      if (mounted) setState(() => _packSlides = pack.slides);
    } on ApiException catch (e) {
      if (e.statusCode == 404 && mounted) setState(() => _packUnavailable = true);
    } catch (_) {
      // best effort
    } finally {
      if (mounted) setState(() => _loadingPackSlides = false);
    }
  }

  Future<void> _toggleFavorite() async {
    if (_togglingFavorite) return;
    setState(() => _togglingFavorite = true);
    try {
      final updated = await ContentService.instance.toggleFavorite(_send.id);
      if (mounted) setState(() => _send = updated);
    } catch (_) {
      // best effort
    } finally {
      if (mounted) setState(() => _togglingFavorite = false);
    }
  }

  Future<void> _addReaction(String emoji) async {
    if (_reacting) return;
    setState(() {
      _reacting = true;
      _reactionPickerOpen = false;
    });
    try {
      final updated = await ContentService.instance.reactToSend(_send.id, emoji);
      if (mounted) {
        setState(() => _send = updated.copyWith(
              reactions: SendReaction.dedupeByUser(updated.reactions),
            ));
      }
    } catch (_) {
      // best effort
    } finally {
      if (mounted) setState(() => _reacting = false);
    }
  }

  /// La barre de composition toujours visible envoie un NOUVEAU message
  /// (une bulle dans le fil de discussion sous la carte, alignée à droite
  /// ici puisque c'est nous qui l'envoyons) — à distinguer d'une réaction
  /// (le petit cercle sur la bulle), qui s'accroche à CET envoi sans créer
  /// de nouvelle bulle.
  ///
  /// Envoi optimiste façon WhatsApp/Telegram (même principe que
  /// _GameCardThreadScreenState._submitMessage/_pending) : la bulle
  /// apparaît tout de suite avec une horloge, la requête part en arrière-
  /// plan — voir demande utilisateur : "des que je clique ca passe a mon
  /// niveau et en arriere plan l'envoi vers le serveur s'effectue. si ca
  /// reussi ca va et si ca echoue il y aura un petit icone rouge... et si
  /// l'on clique dessus ca relance la soumission". Gardée à part de
  /// [_replies] (plutôt que d'y injecter un faux Send) pour ne jamais
  /// entrer en collision avec l'écho temps réel de SendCreated, qui peut
  /// ajouter la vraie réponse à _replies avant même que cette requête HTTP
  /// ne revienne. Voir _sendMessage plus bas.
  ///
  /// Horodatage local strictement après tout ce qu'on connaît déjà de ce
  /// fil — sans ça, une bulle optimistique calée sur DateTime.now() (horloge
  /// de l'appareil) peut se trier AVANT la dernière bulle confirmée si
  /// l'horloge serveur (utilisée pour Send.createdAt) est un peu en avance,
  /// et sauter visiblement de place une fois la vraie réponse reçue (voir
  /// même correctif déjà en place côté
  /// _GameCardThreadScreenState._nextPendingTime, constaté en réel là-bas
  /// aussi, et demande utilisateur ici : "ca se position instantanement...
  /// et revient rapidement apres a sa place qui est la position la plus bas").
  DateTime _nextPendingTime() {
    var latest = DateTime.now();
    final known = <DateTime>[
      _send.createdAt,
      ..._replies.map((r) => r.createdAt),
      ..._pendingReplies.map((p) => p.send.createdAt),
    ];
    for (final t in known) {
      if (t.isAfter(latest)) latest = t.add(const Duration(milliseconds: 1));
    }
    return latest;
  }

  /// Message libre (texte normal, clavier système) — voir demande
  /// utilisateur : "on doit pouvoir reagir en ecrivant du texte pas
  /// seulement des emoji. un clavier classique". Utilise le même point
  /// d'entrée générique que GameCardThreadScreen (ContentService.
  /// sendTextReply), qui accepte n'importe quel texte, émojis compris.
  Future<void> _sendMessage() async {
    final text = _messageComposeController.text.trim();
    if (text.isEmpty) return;
    _messageComposeController.clear();
    final fakeSend = Send(
      id: 'local-reply-${DateTime.now().microsecondsSinceEpoch}',
      boxId: _send.boxId,
      senderId: widget.user.id,
      recipientId: _send.senderId == widget.user.id ? _send.recipientId : _send.senderId,
      sendableType: 'text_reply',
      replyToSendId: _send.id,
      coinCost: 0,
      status: 'sent',
      createdAt: _nextPendingTime(),
      textReplyText: text,
    );
    final pending = _PendingReply(fakeSend);
    setState(() => _pendingReplies = [..._pendingReplies, pending]);
    if (_followLatest) _scrollToBottomSoon();
    await _sendPendingReply(pending);
  }

  Future<void> _sendPendingReply(_PendingReply pending) async {
    setState(() => pending.failed = false);
    try {
      final reply = await ContentService.instance.sendTextReply(_send.id, pending.send.textReplyText!);
      if (!mounted) return;
      setState(() {
        _pendingReplies = _pendingReplies.where((p) => p != pending).toList();
        // Même protection que _sendPending côté GameCardThreadScreen :
        // l'écho temps réel peut déjà avoir ajouté ce message.
        if (!_replies.any((r) => r.id == reply.id)) {
          _replies = [reply, ..._replies];
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => pending.failed = true);
    }
  }

  Future<void> _reply() async {
    final replied = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'reply-root'),
        builder: (_) => PacksScreen(replyToSendId: _send.id),
      ),
    );
    if (!mounted) return;
    // Voir demande utilisateur : "quand je clique pour envoyer le clavier
    // s'ouvre automatiquement" (même correctif que GameCardThreadScreen) —
    // au retour sur cet écran, Flutter redonnait le focus au champ de
    // texte de ce fil, rouvrant le clavier sans action de l'utilisateur.
    FocusManager.instance.primaryFocus?.unfocus();
    if (replied == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LocaleScope.of(context).t('pack_reply_sent_snackbar'))),
      );
      _loadLatestReplies();
    }
  }

  /// Répondre par un battement de cœur — tap direct sur le bouton, sans
  /// confirmation supplémentaire : choisir une option dans ce menu vaut déjà
  /// confirmation. Un ancien geste "tap simple → carte à double-tapper"
  /// existait, mais peu de gens auraient découvert un appui long caché
  /// derrière un simple bouton ; ce menu explicite le remplace entièrement.
  Future<void> _openHeartbeatReplyOptions() async {
    if (_sendingHeartbeatReply) return;
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;
    HapticFeedback.selectionClick();
    // Un sous-titre différent tiré au hasard parmi 4 à chaque ouverture de
    // la feuille (voir demande utilisateur).
    final randomSubtitleKey = 'heartbeat_reply_random_subtitle_${math.Random().nextInt(4) + 1}';
    final customSubtitleKey = 'heartbeat_reply_custom_subtitle_${math.Random().nextInt(4) + 1}';

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: theme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
                t('heartbeat_reply_sheet_title'),
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: theme.textOnBackground),
              ),
              const SizedBox(height: 4),
              Text(
                t('heartbeat_reply_sheet_subtitle'),
                style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
              ),
              const SizedBox(height: 18),
              _HeartbeatOptionTile(
                theme: theme,
                icon: Icons.auto_awesome_rounded,
                title: t('heartbeat_reply_random_title'),
                subtitle: t(randomSubtitleKey),
                onTap: () => Navigator.of(sheetContext).pop('random'),
              ),
              const SizedBox(height: 10),
              _HeartbeatOptionTile(
                theme: theme,
                icon: Icons.edit_note_rounded,
                title: t('heartbeat_reply_custom_title'),
                subtitle: t(customSubtitleKey),
                onTap: () => Navigator.of(sheetContext).pop('custom'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (choice == null) return;
    if (choice == 'random') {
      _sendHeartbeatReply();
    } else {
      _composeCustomHeartbeatReply();
    }
  }

  Future<void> _composeCustomHeartbeatReply() async {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;
    final controller = TextEditingController();

    final message = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(t('heartbeat_reply_dialog_title'), style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 140,
          maxLines: 3,
          style: GoogleFonts.nunito(color: theme.textOnBackground),
          cursorColor: theme.primary,
          decoration: InputDecoration(
            hintText: t('heartbeat_reply_dialog_hint'),
            hintStyle: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: theme.textOnBackgroundMuted.withValues(alpha: 0.25)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: theme.primary, width: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(t('common_cancel'), style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: theme.primary),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.of(dialogContext).pop(text);
            },
            child: Text(t('heartbeat_reply_send_button')),
          ),
        ],
      ),
    );

    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (message != null && message.isNotEmpty) {
      _sendHeartbeatReply(message: message);
    }
  }

  Future<void> _sendHeartbeatReply({String? message}) async {
    if (_sendingHeartbeatReply) return;
    setState(() => _sendingHeartbeatReply = true);
    try {
      await ContentService.instance.sendHeartbeat(message: message, replyToSendId: _send.id);
      await WalletBalanceNotifier.instance.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LocaleScope.of(context).t('heartbeat_reply_sent_snackbar'))),
      );
      _loadLatestReplies();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LocaleScope.of(context).t('common_network_error'))),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingHeartbeatReply = false);
    }
  }

  Future<void> _openReply(Send reply) async {
    if (reply.recipientId == widget.user.id && !reply.isSeen) {
      try {
        await ContentService.instance.markSeen(reply.id);
      } catch (_) {
        // best effort
      }
    }
    if (!mounted) return;
    // Une réponse-poème ou un battement de cœur s'agrandit par-dessus
    // l'écran de discussion (modale, pas un changement de page) — fermer
    // ramène instantanément au fil, sans navigation à défaire.
    if (reply.isPack && reply.pack != null) {
      await showPackReplyModal(context, packId: reply.pack!.id);
      return;
    }
    if (reply.isHeartbeat) {
      final locale = LocaleScope.of(context);
      await showHeartbeatReplyModal(
        context,
        images: reply.heartbeatImages,
        message: reply.heartbeatMessageFor(locale.current.code) ?? locale.t('heartbeat_default_message'),
        family: reply.heartbeatFamily,
        senderGender: reply.sender?.gender,
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SlideDetailScreen(
          send: reply,
          isMine: reply.senderId == widget.user.id,
          user: widget.user,
        ),
      ),
    );
  }

  AppUser? get _partner => widget.isMine ? _send.recipient : _send.sender;

  /// Carte d'origine (avec sa citation de réponse, ses réactions et son
  /// message) — dernier item de la ListView inversée (voir build()), donc
  /// visible tout en haut une fois qu'on a remonté tout le fil.
  Widget _buildHeader(ThemePalette theme, bool isMine) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (_send.replyTo != null) ...[
          _ReplyToChip(
            text: _mainText(_send.replyTo!),
            color: theme.textOnBackgroundMuted,
          ),
          const SizedBox(height: 14),
        ],
        // Centrée au-dessus de la carte, en pastille translucide — comme
        // les séparateurs de date d'une vraie messagerie, plutôt qu'un
        // simple texte collé au bord. SizedBox(width: infinity) nécessaire
        // pour que Center ait vraiment toute la largeur pour centrer dans
        // — sans lui, la Column (crossAxisAlignment start/end, pas stretch)
        // ne donne que la largeur de son enfant le plus large.
        SizedBox(
          width: double.infinity,
          child: Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _formattedDate(_send.createdAt),
                style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
          ),
        ),
        _ChatBubble(
          isMine: isMine,
          theme: theme,
          // Le battement de cœur avec photo est déjà une carte complète
          // (bordure, ombre, coins arrondis) — le verre dépoli habituel de
          // la bulle en plus par-dessus créait un double cadre disgracieux
          // (marge grisâtre autour de la photo).
          tight: _send.isHeartbeat && _send.heartbeatImages.isNotEmpty,
          // La réaction (ou le "+" tant qu'il n'y en a pas encore) est
          // accrochée au bord de LA carte concernée, pas détachée plus bas
          // — elle porte sur ce pack précis.
          cornerOverlay: _reactionOverlay(theme),
          // Même agrandissement en modale que les réponses-poème du fil —
          // pas de raison que celle-ci, la carte principale, n'en profite
          // pas aussi.
          child: _send.isPack && _send.pack != null
              ? GestureDetector(
                  onTap: () => showPackReplyModal(context, packId: _send.pack!.id),
                  child: _bubbleContent(theme),
                )
              : _bubbleContent(theme),
        ),
        // Le chevauchement du cercle/de la réaction laisse déjà ~16px de
        // creux naturel sous la carte — pas besoin d'en rajouter beaucoup.
        const SizedBox(height: 2),
        // Réactions rapides (un tap) — repliées derrière le petit cercle
        // sur la bulle, juste au-dessus.
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _reactionPickerOpen
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _ReactionBar(
                    enabled: !_reacting,
                    onPick: _addReaction,
                    theme: theme,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (_send.message != null && _send.message!.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '« ${_send.message} »',
            textAlign: isMine ? TextAlign.right : TextAlign.left,
            style: GoogleFonts.nunito(
              color: theme.textOnBackgroundMuted,
              fontSize: 14,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  /// Une seule réaction par envoi, réservée au/à la destinataire — tant
  /// qu'aucune n'est posée, le "+" invite à en choisir une (visible
  /// seulement pour le/la destinataire) ; une fois posée, elle prend sa
  /// place (visible des deux côtés, mais seul·e le/la destinataire peut la
  /// changer en la retapant).
  Widget? _reactionOverlay(ThemePalette theme) {
    final canReact = !widget.isMine;
    final reaction = _send.reactions.isNotEmpty ? _send.reactions.first : null;

    // La barre se referme dès le tap (voir _addReaction), mais le badge ne
    // remplace le cercle qu'une fois la réponse serveur arrivée — sans ce
    // loader, ce délai se lisait comme "le tap n'a rien fait".
    if (_reacting) {
      return const _ReactionLoadingCircle();
    }

    if (reaction == null) {
      if (!canReact) return null;
      return _ReactionTriggerCircle(
        onTap: () => setState(() => _reactionPickerOpen = !_reactionPickerOpen),
      );
    }

    return _SingleReactionBadge(
      emoji: reaction.emoji,
      onTap: canReact
          ? () => setState(() => _reactionPickerOpen = !_reactionPickerOpen)
          : null,
    );
  }

  String _mainText(Send send) {
    final locale = LocaleScope.of(context);
    final localeCode = locale.current.code;
    if (send.isPack) return send.pack?.titleFor(localeCode) ?? locale.t('send_fallback_poem');
    if (send.isGift) return send.gift?.name ?? locale.t('send_fallback_gift');
    if (send.isHeartbeat) return send.heartbeatMessageFor(localeCode) ?? locale.t('heartbeat_default_message');
    if (send.isEmojiReply) return send.emojiReplyText ?? '💬';
    if (send.isTextReply) return send.textReplyText ?? '';
    // "À nous deux" (voir GameBoxSessionScreen) — sans cette branche, une
    // carte-question ouverte depuis le Carnet de bord retombait dans le
    // texte vide par défaut ci-dessous (bulle vide constatée en réel,
    // send.slide étant toujours null pour ce type d'envoi).
    if (send.isGameCard) return send.gameCard?.questionTextFor(localeCode) ?? locale.t('send_fallback_question');
    return send.slide?.textFor(localeCode) ?? '';
  }

  String _formattedDate(DateTime dt) {
    final t = LocaleScope.of(context).t;
    final date = '${dt.day} ${t('month_${dt.month}')} ${dt.year}';
    final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return t('date_full_at_time', {'date': date, 'time': time});
  }

  /// Dernière connexion du binôme la plus récente qu'on connaisse : celle du
  /// profil chargé avec l'envoi, ou celle portée par l'une de ses réponses
  /// (rechargées à chaque ouverture, donc plus fraîches).
  DateTime? get _partnerLastSeenAt {
    final partner = _partner;
    if (partner == null) return null;
    var latest = partner.lastSeenAt;
    for (final reply in _replies) {
      final seen = reply.sender?.id == partner.id ? reply.sender?.lastSeenAt : null;
      if (seen != null && (latest == null || seen.isAfter(latest))) latest = seen;
    }
    return latest;
  }

  /// "En ligne" (canal presence temps réel) ou "Vu il y a X" sous les
  /// avatars — même information que l'en-tête des discussions de jeu.
  Widget _presenceLine(ThemePalette theme) {
    final online = _partnerPresent;
    final label = online
        ? LocaleScope.of(context).t('presence_online')
        : lastSeenLabel(context, _partnerLastSeenAt);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.nunito(
          fontSize: 11.5,
          color: online ? Colors.greenAccent.shade700 : theme.textOnBackgroundMuted,
          fontWeight: online ? FontWeight.w700 : FontWeight.normal,
        ),
      ),
    );
  }

  /// Un envoi ne copie pas le poème, il pointe vers lui : si l'admin l'a
  /// supprimé ou dépublié depuis, il n'y a plus rien à feuilleter — on le dit
  /// plutôt que d'afficher un chargement sans fin.
  Widget _unavailablePoemCard(ThemePalette theme) {
    final t = LocaleScope.of(context).t;
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_stories_rounded, size: 40, color: theme.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              t('send_poem_unavailable'),
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: theme.textOnBackgroundMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubbleContent(ThemePalette theme) {
    if (_send.isPack && (_send.pack == null || _packUnavailable)) {
      return _unavailablePoemCard(theme);
    }
    if (_send.isPack) {
      // Même habillage et même feuilletage que "Envoyer une pensée" (voir
      // PackFeedScreen) : revisionner un poème envoyé en entier depuis le
      // Carnet de bord doit ressembler exactement à l'expérience où il a
      // été choisi et envoyé.
      return AspectRatio(
        aspectRatio: 3 / 4,
        child: _loadingPackSlides || _packSlides == null
            ? Center(child: CircularProgressIndicator(color: theme.primary))
            : SlidePackViewer(
                slides: _packSlides!,
                theme: theme,
                category: _send.pack?.category,
                senderGender: _send.sender?.gender,
                // Même correctif que la modale de réponse : marge
                // horizontale seulement (espace propre entre les cartes en
                // swipant), pas de marge verticale qui laisserait voir le
                // fond de la bulle en haut/bas comme un cadre.
                slideMargin: const EdgeInsets.symmetric(horizontal: 6),
              ),
      );
    }
    if (_send.slide != null) {
      // Même habillage que "Envoyer une pensée" (voir PackFeedScreen).
      return AspectRatio(
        aspectRatio: 3 / 4,
        child: SlideVisualCard(
          slide: _send.slide!,
          theme: theme,
          category: _send.slide!.category,
          senderGender: _send.sender?.gender,
        ),
      );
    }
    if (_send.isHeartbeat) {
      // Widget partagé avec la modale de réponse (voir
      // showHeartbeatReplyModal) — la même carte doit apparaître partout,
      // pas une variante simplifiée ici.
      final card = HeartbeatCard(
        images: _send.heartbeatImages,
        message: _mainText(_send),
        theme: theme,
        family: _send.heartbeatFamily,
        senderGender: _send.sender?.gender,
      );
      if (HeartbeatCard.usesFamilyImage(_send.heartbeatFamily, _send.heartbeatImages)) {
        // Images de famille : portrait 4:5, pour qu'elles ne soient pas rognées.
        return AspectRatio(aspectRatio: 4 / 5, child: card);
      }
      return _send.heartbeatImages.isNotEmpty
          // Plus court que le 3/4 des poèmes/packs (portrait) — un simple
          // aperçu photo n'a pas besoin d'occuper presque tout l'écran.
          ? AspectRatio(aspectRatio: 4 / 3, child: card)
          : card;
    }

    if (_send.isGift && (_send.gift?.isQuantumLoveHeart ?? false)) {
      // Cadeau généré en direct : l'animation elle-même est le cadeau,
      // pas juste une icône qui l'illustre — plein écran comme les autres
      // rendus riches (poème, heartbeat) plutôt que dans la colonne texte.
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Le prénom affiché est toujours celui du destinataire du
            // cadeau (à qui le cœur est dédié) — que je sois en train de
            // revoir un cœur envoyé ou d'ouvrir celui que j'ai reçu.
            QuantumLoveHeart(size: 260, name: _send.recipient?.prenom),
            const SizedBox(height: 20),
            Text(
              _mainText(_send),
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                color: theme.textOnBackground,
                fontSize: 24,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
                height: 1.5,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      );
    }

    if (_send.isGift && (_send.gift?.isSketchedHeart ?? false)) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SketchedLoveHeart(size: 260),
            const SizedBox(height: 20),
            Text(
              _mainText(_send),
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                color: theme.textOnBackground,
                fontSize: 24,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
                height: 1.5,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      );
    }

    if (_send.isGift && (_send.gift?.isEternalRose ?? false)) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EternalRose(size: 260),
            const SizedBox(height: 20),
            Text(
              _mainText(_send),
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                color: theme.textOnBackground,
                fontSize: 24,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
                height: 1.5,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      );
    }

    if (_send.isGift && (_send.gift?.isWordHeart ?? false)) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WordHeart(size: 260, isDark: theme.isDark),
            const SizedBox(height: 8),
            Text(
              LocaleScope.of(context).t('drag_rotate_heart'),
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: theme.textOnBackgroundMuted,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _mainText(_send),
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                color: theme.textOnBackground,
                fontSize: 24,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
                height: 1.5,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      );
    }

    if (_send.isGift && (_send.gift?.isBlackRose ?? false)) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RealisticBlackRose(size: 280),
            const SizedBox(height: 8),
            Text(
              LocaleScope.of(context).t('drag_rotate_rose'),
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: theme.textOnBackgroundMuted,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _mainText(_send),
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                color: theme.textOnBackground,
                fontSize: 24,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
                height: 1.5,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      );
    }

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_send.isGift) ...[
          Icon(Icons.card_giftcard_rounded, color: theme.accent, size: 52),
          const SizedBox(height: 20),
        ],
        Text(
          _mainText(_send),
          textAlign: TextAlign.center,
          style: _send.isEmojiReply
              ? const TextStyle(fontSize: 34, height: 1.3)
              : GoogleFonts.playfairDisplay(
                  color: theme.textOnBackground,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  fontStyle: FontStyle.italic,
                  height: 1.5,
                  letterSpacing: 0.3,
                ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.all(18),
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final isMine = widget.isMine;
    final t = LocaleScope.of(context).t;

    return Scaffold(
        backgroundColor: theme.background,
      // Fond immersif du thème choisi (étoilé, montagnes...) plutôt qu'un
      // fond uni : rouvrir un envoi doit ressembler à retrouver une "photo"
      // de l'émotion passée, pas une simple page de texte.
      body: ThemedBackground(
        child: SafeArea(
          // Ferme la barre de réactions au tap sur un espace vide — un tap
          // sur le petit cercle ou un bouton précis gagne l'arène de geste
          // en premier (recognizer le plus interne) donc ce onTap-ci ne se
          // déclenche QUE quand rien de plus spécifique n'a intercepté le
          // tap ; opaque nécessaire pour que les zones transparentes du
          // fond comptent aussi comme "vide" cliquable.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_reactionPickerOpen) setState(() => _reactionPickerOpen = false);
            },
            child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 20,
                        color: theme.textOnBackground,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    // Centrés dans l'espace disponible plutôt qu'alignés à
                    // gauche à côté d'un nom — la date est descendue dans
                    // la bulle elle-même (voir _buildHeader), comme pour
                    // les autres échanges du fil.
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Les deux avatars superposés disent "c'est votre
                          // conversation à deux" — pas un contact précis,
                          // le couple lui-même. Le point vert "en ligne"
                          // (voir CoupleAvatarsBadge) s'affiche directement
                          // dessus, même canal presence que le Dashboard.
                          // Tap → profil commun du couple (même geste que
                          // depuis Duo).
                          GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => CoupleProfileScreen(user: widget.user)),
                            ),
                            child: CoupleAvatarsBadge(
                              user: widget.user,
                              partner: _partner,
                              partnerPresent: _partnerPresent,
                            ),
                          ),
                          _presenceLine(theme),
                        ],
                      ),
                    ),
                    // Pas de fonctionnalité d'appel dans l'app : à la place
                    // des icônes vidéo/vocal habituelles d'un en-tête de
                    // chat, seules des actions qui existent réellement ici.
                    IconButton(
                      icon: _togglingFavorite
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.primary,
                              ),
                            )
                          : Icon(
                              _send.isFavorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: theme.primary,
                            ),
                      onPressed: _toggleFavorite,
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: theme.textOnBackground,
                      ),
                      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(t('common_coming_soon'))),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                // Liste NON inversée : un fil court reste ancré en haut,
                // sous la carte d'origine (comportement par défaut d'une
                // liste qui ne remplit pas l'écran), un fil qui déborde est
                // amené sur le dernier échange une seule fois à l'ouverture
                // (voir _scrollToBottomIfOverflowingOnce) puis suit les
                // nouveaux échanges si on y était déjà (voir _isNearBottom).
                // Virtualisée (voir _replies) — essentiel pour un fil qui
                // peut compter des centaines de messages. L'en-tête (carte
                // d'origine) est le PREMIER item ; les réponses sont
                // reparcourues à l'envers (stockées plus récente d'abord,
                // affichées plus ancienne d'abord) pour suivre l'ordre de
                // lecture naturel.
                child: Builder(
                  builder: (context) {
                    final repliesOldestFirst = _replies.reversed.toList();
                    // Fusionnés et triés par date : un message émoji encore
                    // en vol (voir _pendingReplies) doit s'insérer à sa
                    // vraie place, même si une réponse du/de la binôme est
                    // arrivée en temps réel entretemps.
                    final combined = <_ThreadDisplayItem>[
                      ...repliesOldestFirst.map((r) => _ThreadDisplayItem(reply: r, time: r.createdAt)),
                      ..._pendingReplies.map((p) => _ThreadDisplayItem(pending: p, time: p.send.createdAt)),
                    ]..sort((a, b) => a.time.compareTo(b.time));
                    final loadingOffset = _loadingMoreReplies ? 1 : 0;
                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      itemCount: 1 + loadingOffset + combined.length,
                      itemBuilder: (context, index) {
                        if (index == 0) return _buildHeader(theme, isMine);
                        if (_loadingMoreReplies && index == 1) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final item = combined[index - 1 - loadingOffset];
                        final pending = item.pending;
                        final reply = item.reply ?? pending!.send;
                        // Fil de discussion : chaque réponse envoyée depuis
                        // la barre du bas (ou "Répondre avec un poème")
                        // apparaît ici comme une bulle de messagerie —
                        // alignée à droite si c'est nous qui l'avons
                        // envoyée, à gauche si c'est le/la partenaire (voir
                        // _ThreadReplyBubble, qui s'aligne lui-même).
                        return Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: _ThreadReplyBubble(
                            reply: reply,
                            isMine: reply.senderId == widget.user.id,
                            fallbackText: _mainText(reply),
                            time: _formattedDate(reply.createdAt),
                            theme: theme,
                            tickOverride: pending == null
                                ? null
                                : (pending.failed ? SendTick.failed : SendTick.sending),
                            onRetry: pending != null && pending.failed
                                ? () => _sendPendingReply(pending)
                                : null,
                            onTap: pending != null ? () {} : () => _openReply(reply),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              // Barre de composition — toujours visible en bas de l'écran
              // (même disposition que le jeu "Devine mon émoji"), pas cachée
              // derrière un tap. Envoie un NOUVEAU message (nouvelle capsule
              // dans le Carnet de bord, en réponse à cet envoi) — différent
              // d'une réaction, qui s'accroche au coin de LA bulle ci-dessus
              // via le petit cercle "+". "Répondre avec un poème"/"battement
              // de cœur" restent repliés derrière un bouton "+" (voir
              // ComposerActionsTrigger, partagé avec GameCardThreadScreen)
              // plutôt qu'affichés en permanence — le champ récupère ainsi
              // toute la largeur qu'occupaient les deux cercles empilés.
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      alignment: Alignment.bottomLeft,
                      child: _composerActionsOpen
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 10, left: 4),
                              child: ComposerActionsDrawer(
                                actions: [
                                  ComposerAction.icon(
                                    tooltip: t('composer_reply_poem_tooltip'),
                                    icon: Icons.auto_stories_rounded,
                                    theme: theme,
                                    onTap: () {
                                      setState(() => _composerActionsOpen = false);
                                      _reply();
                                    },
                                  ),
                                  ComposerAction.icon(
                                    tooltip: t('composer_reply_heartbeat_tooltip'),
                                    icon: Icons.favorite_rounded,
                                    theme: theme,
                                    loading: _sendingHeartbeatReply,
                                    onTap: _sendingHeartbeatReply
                                        ? null
                                        : () {
                                            setState(() => _composerActionsOpen = false);
                                            _openHeartbeatReplyOptions();
                                          },
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        ComposerActionsTrigger(
                          theme: theme,
                          open: _composerActionsOpen,
                          onTap: () => setState(() => _composerActionsOpen = !_composerActionsOpen),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 48),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            decoration: BoxDecoration(
                              color: theme.surface,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(color: theme.primary.withValues(alpha: 0.4)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            // Clavier système classique (voir demande
                            // utilisateur : "on doit pouvoir reagir en
                            // ecrivant du texte pas seulement des emoji. un
                            // clavier classique") — remplace l'ancien
                            // clavier maison émoji-only (EmojiComposeBar/
                            // EmojiPickerPanel), qui ne permettait aucune
                            // saisie de texte libre.
                            child: TextField(
                              controller: _messageComposeController,
                              minLines: 1,
                              maxLines: 4,
                              textCapitalization: TextCapitalization.sentences,
                              style: GoogleFonts.nunito(color: theme.textOnBackground),
                              cursorColor: theme.primary,
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                hintText: t('reaction_compose_placeholder'),
                                hintStyle: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: _messageComposeController.text.trim().isEmpty
                              ? theme.surface
                              : theme.primary,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _messageComposeController.text.trim().isEmpty ? null : _sendMessage,
                            child: Padding(
                              padding: const EdgeInsets.all(13),
                              child: Icon(
                                Icons.send_rounded,
                                size: 20,
                                color: _messageComposeController.text.trim().isEmpty
                                    ? theme.textOnBackgroundMuted
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Petit rappel discret au-dessus de la carte quand cet envoi est lui-même
/// une réponse à un poème précédent — garde le fil visible sans jamais
/// ressembler à une bulle de chat.
class _ReplyToChip extends StatelessWidget {
  final String text;
  final Color color;

  const _ReplyToChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.subdirectory_arrow_right_rounded, size: 14, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'En réponse à « $text »',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.nunito(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// Bulle de chat en verre dépoli, ancrée du côté de l'expéditeur (comme une
/// vraie messagerie), qui enveloppe le contenu de l'envoi (carte poème,
/// cadeau...). Les réactions (cercle + badges, voir [cornerOverlay]) sont
/// accrochées à son bord bas, puisqu'elles portent sur ELLE précisément —
/// le fil de discussion, lui, suit en dessous dans le flux normal.
class _ChatBubble extends StatelessWidget {
  final bool isMine;
  final Widget child;
  final ThemePalette theme;

  /// Accroché au bord bas de la carte (chevauchement), du côté où elle est
  /// ancrée — les réactions concernent CE pack précis, elles doivent se
  /// lire comme rattachées à lui plutôt que détachées plus bas.
  final Widget? cornerOverlay;

  /// true quand [child] est déjà une carte complète et autonome (bordure,
  /// ombre, coins arrondis — ex. le battement de cœur avec photo) : le verre
  /// dépoli habituel (fond blanc 10% + bordure + padding 10) est alors
  /// sauté, sinon les deux cadres se superposent et créent une marge
  /// grisâtre disgracieuse autour de la carte.
  final bool tight;

  const _ChatBubble({
    required this.isMine,
    required this.child,
    required this.theme,
    this.cornerOverlay,
    this.tight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.84,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tight)
              child
            else
              ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(26),
                  topRight: const Radius.circular(26),
                  bottomLeft: Radius.circular(isMine ? 26 : 6),
                  bottomRight: Radius.circular(isMine ? 6 : 26),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    child: child,
                  ),
                ),
              ),
            if (cornerOverlay != null)
              // Transform (pas un Positioned en négatif dans un Stack avec
              // Clip.none) : ça déplace le tap en même temps que le dessin.
              // Avec l'ancienne approche, la moitié débordante du cercle
              // était peinte hors de la zone réellement cliquable — d'où le
              // besoin de taper plusieurs fois pour que ça marche.
              Transform.translate(
                offset: const Offset(0, -16),
                child: Align(
                  alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: isMine ? 0 : 14,
                      right: isMine ? 14 : 0,
                    ),
                    child: cornerOverlay!,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Petit cercle façon avatar, accroché au bord de la carte — pas une vraie
/// photo de profil, un simple "+" qui invite le/la destinataire à réagir.
/// Au tap, déploie la barre de réactions fixes juste en dessous. Disparaît
/// dès qu'une réaction est posée (remplacé par [_SingleReactionBadge]) —
/// voir SlideDetailScreen._reactionOverlay.
class _ReactionTriggerCircle extends StatelessWidget {
  final VoidCallback onTap;

  const _ReactionTriggerCircle({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        // Zone de tap 44x44 (minimum recommandé Material/Android), même si
        // le cercle VISIBLE reste 32x32 — un finger réel manque facilement
        // une cible de 32px accrochée au bord d'une bulle (voir le même
        // correctif côté GameCardThreadScreen, remonté en réel : aucune
        // réaction au tap sur un appareil d'entrée de gamme).
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // Blanc translucide plutôt que gris terne — plus neutre,
                // n'évoque pas un bouton désactivé.
                color: Colors.white.withValues(alpha: 0.85),
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              // Rose (émoji), teintée dans la même couleur neutre que
              // l'ancien "+" — BlendMode.srcIn remplace les couleurs de
              // l'émoji par cette teinte unique, un simple TextStyle.color
              // ne fonctionne pas sur un glyphe emoji.
              child: ColorFiltered(
                colorFilter: const ColorFilter.mode(Colors.black45, BlendMode.srcIn),
                child: const Text('🌹', style: TextStyle(fontSize: 16)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Même cercle que [_ReactionTriggerCircle]/[_SingleReactionBadge] (même
/// taille, même position), mais avec un petit indicateur de chargement à la
/// place — affiché le temps que la réaction choisie arrive côté serveur
/// (voir SlideDetailScreen._reactionOverlay), pour que le tap se lise
/// comme "pris en compte" plutôt que "n'a rien fait" pendant ce court délai.
class _ReactionLoadingCircle extends StatelessWidget {
  const _ReactionLoadingCircle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black45),
      ),
    );
  }
}

/// LA réaction posée sur cet envoi (une seule à la fois) — prend la place
/// de la rose une fois choisie. Retapable par le/la destinataire pour la
/// changer (rouvre la barre de réactions fixes) ; simple affichage, non
/// tapable, pour l'expéditeur·rice (qui ne peut pas réagir à son propre
/// envoi).
class _SingleReactionBadge extends StatelessWidget {
  final String emoji;
  final VoidCallback? onTap;

  const _SingleReactionBadge({required this.emoji, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        // Même zone de tap élargie que _ReactionTriggerCircle (44x44) —
        // seule la coquille blanche visible (32x32, avec l'ombre) reste à
        // sa taille d'origine.
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 3,
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                child: Text(emoji, style: const TextStyle(fontSize: 16)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Barre de réactions rapides à ajouter — un set fixe d'émojis (pas de
/// saisie libre) pour rester fidèle à l'identité "boîte à souvenirs" de
/// l'app plutôt qu'un chat classique. Se déploie au tap du petit cercle sur
/// la bulle plutôt que de rester affichée en permanence.
class _ReactionBar extends StatelessWidget {
  final bool enabled;
  final ValueChanged<String> onPick;
  final ThemePalette theme;

  const _ReactionBar({
    required this.enabled,
    required this.onPick,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    // Défilement horizontal plutôt qu'un Row qui déborderait de l'écran —
    // la liste doit rester sur une seule ligne, jamais passer sur deux
    // (voir kSendReactionEmojis, volontairement court mais assez fourni
    // pour dépasser la largeur disponible sur un petit écran).
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.84),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: kSendReactionEmojis.map((emoji) {
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: enabled ? () => onPick(emoji) : null,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(emoji, style: const TextStyle(fontSize: 22)),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

/// Une bulle du fil de discussion sous la carte — à droite si c'est nous qui
/// l'avons envoyée, à gauche si c'est le/la partenaire, comme une vraie
/// messagerie. Chaque réponse (poème ou message émoji) a la sienne ; un tap
/// ouvre cette réponse en plein écran (pour y réagir/répondre à son tour).
/// Réponse encore en vol (voir _sendMessage) — [failed] bascule sans
/// reconstruire tout l'objet, comme _PendingText côté GameCardThreadScreen.
class _PendingReply {
  final Send send;
  bool failed = false;
  _PendingReply(this.send);
}

/// Élément affichable du fil : soit une réponse confirmée, soit un envoi
/// encore en vol — fusionnés et triés par date (voir leur usage dans
/// _SlideDetailScreenState.build).
class _ThreadDisplayItem {
  final Send? reply;
  final _PendingReply? pending;
  final DateTime time;
  _ThreadDisplayItem({this.reply, this.pending, required this.time});
}

class _ThreadReplyBubble extends StatelessWidget {
  final Send reply;
  final bool isMine;
  final String fallbackText;
  final String time;
  final ThemePalette theme;
  final VoidCallback onTap;
  // Envoi encore en vol/échoué (voir _PendingReply) — remplace le
  // statut déduit de reply.status, qui reste 'sent' par défaut sur le faux
  // Send local tant que rien n'est confirmé côté serveur.
  final SendTick? tickOverride;
  final VoidCallback? onRetry;

  const _ThreadReplyBubble({
    required this.reply,
    required this.isMine,
    required this.fallbackText,
    required this.time,
    required this.theme,
    required this.onTap,
    this.tickOverride,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final previewSlide =
        reply.isPack && (reply.pack?.slides.isNotEmpty ?? false) ? reply.pack!.slides.first : null;
    final previewHeartbeatImage =
        reply.isHeartbeat && reply.heartbeatImages.isNotEmpty ? reply.heartbeatImages.first : null;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: previewSlide != null
              ? _packPreview(previewSlide)
              : previewHeartbeatImage != null
                  ? _heartbeatPreview(previewHeartbeatImage)
                  // Sans image (message du catalogue sans photo), toujours
                  // la carte du battement de cœur — jamais la bulle de
                  // texte plate partagée avec les réponses-émoji.
                  : reply.isHeartbeat
                      ? (HeartbeatCard.usesFamilyImage(reply.heartbeatFamily, reply.heartbeatImages)
                          ? _heartbeatFamilyPreview()
                          : _heartbeatTextCard())
                      : _textBubble(),
        ),
      ),
    );
  }

  // FittedBox : sur une carte étroite (ex. battement de cœur sans photo, 106 px
  // utiles), "11 septembre 2026 à 18:03" + coches dépassait la bulle (bandeau
  // "RIGHT OVERFLOWED") — la ligne rétrécit désormais au lieu de déborder, et
  // reste inchangée quand elle tient.
  Widget _timeLabel(Color color) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(time, style: GoogleFonts.nunito(fontSize: 9, color: color)),
            if (isMine) ...[
              const SizedBox(width: 4),
              SendTickIcon(tick: tickOverride ?? sendTickFor(reply), color: color, onRetry: onRetry),
            ],
          ],
        ),
      );

  // Réponse-poème : la vraie carte (image/dégradé + texte), pas juste le
  // titre du pack — sinon on ne reconnaît pas le poème qu'on a choisi.
  Widget _packPreview(Slide slide) {
    return Container(
      width: 130,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: isMine
            ? theme.primary.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: SlideVisualCard(
              slide: slide,
              theme: theme,
              category: reply.pack?.category,
              senderGender: reply.sender?.gender,
              borderRadius: 12,
              scale: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: _timeLabel(theme.textOnBackgroundMuted),
          ),
        ],
      ),
    );
  }

  // Réponse-battement de cœur avec photo : même esprit que _packPreview
  // (vraie vignette plutôt qu'un simple texte) — l'image garde le même
  // point focal que sur la carte plein écran (voir HeartbeatImage.alignment).
  Widget _heartbeatPreview(HeartbeatImage image) {
    return Container(
      width: 130,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: isMine
            ? theme.primary.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              // Entre le 4/3 initial et le 4/5 essayé ensuite (un peu trop
              // haut) — juste assez de place pour la photo et le texte
              // superposé, sans dominer la bulle.
              aspectRatio: 5 / 6,
              // Texte PAR-DESSUS la photo (même principe que la carte plein
              // écran) plutôt qu'en dessous — un voile dégradé garde la
              // lisibilité, et le FittedBox réduit la police au besoin pour
              // ne jamais déborder de cette petite vignette.
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    image.url,
                    fit: BoxFit.cover,
                    alignment: image.alignment,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Colors.black54],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.4, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 6,
                    right: 6,
                    bottom: 5,
                    // Largeur fixe qui force le retour à la ligne (2 lignes
                    // max) AVANT le FittedBox — sans elle, le texte se
                    // mesurait sur une seule ligne très large puis était
                    // réduit d'autant, ce qui annulait tout changement de
                    // fontSize (la réduction compensait exactement).
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: 106,
                        child: Text(
                          fallbackText,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: handwrittenFont('dancing_script', color: Colors.white, fontSize: 15).copyWith(
                            shadows: const [
                              Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 1)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: _timeLabel(theme.textOnBackgroundMuted),
          ),
        ],
      ),
    );
  }

  // Réponse-battement de cœur habillé d'une image de famille (packagée dans
  // l'app) : même vignette que _packPreview, avec la vraie carte réduite.
  Widget _heartbeatFamilyPreview() {
    return Container(
      width: 130,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: isMine
            ? theme.primary.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AspectRatio(
            aspectRatio: 4 / 5,
            child: HeartbeatCard(
              images: const [],
              message: fallbackText,
              theme: theme,
              family: reply.heartbeatFamily,
              senderGender: reply.sender?.gender,
              scale: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: _timeLabel(theme.textOnBackgroundMuted),
          ),
        ],
      ),
    );
  }

  // Réponse-battement de cœur SANS photo (message du catalogue sans image
  // associée) : même esprit "carte" que HeartbeatCard côté plein écran
  // (theme.surface, bordure, police manuscrite), plutôt que la bulle de
  // texte plate partagée avec les réponses-émoji.
  Widget _heartbeatTextCard() {
    return Container(
      width: 130,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.primary.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: double.infinity,
            child: Text(
              fallbackText,
              textAlign: TextAlign.center,
              style: handwrittenFont('dancing_script', color: theme.textOnBackground, fontSize: 17),
            ),
          ),
          const SizedBox(height: 4),
          _timeLabel(theme.textOnBackgroundMuted),
        ],
      ),
    );
  }

  Widget _textBubble() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMine
              ? theme.primary.withValues(alpha: 0.88)
              : Colors.white.withValues(alpha: 0.14),
          border: isMine
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.22)),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              fallbackText,
              style: reply.isEmojiReply
                  ? const TextStyle(fontSize: 22)
                  : GoogleFonts.nunito(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: isMine ? Colors.white : theme.textOnBackground,
                    ),
            ),
            const SizedBox(height: 3),
            _timeLabel(isMine ? Colors.white.withValues(alpha: 0.8) : theme.textOnBackgroundMuted),
          ],
        ),
      ),
    );
  }
}

/// Même tuile que _HeartbeatOptionTile de dark_quick_actions_grid.dart (bottom
/// sheet ouvert par l'appui long sur la tuile "Faire battre son cœur" du
/// Dashboard) — dupliquée ici plutôt qu'exportée car privée à son fichier
/// d'origine ; garder les deux strictement identiques si l'une des deux change.
class _HeartbeatOptionTile extends StatelessWidget {
  final ThemePalette theme;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HeartbeatOptionTile({
    required this.theme,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: theme.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: theme.textOnBackground),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.textOnBackgroundMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
