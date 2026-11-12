import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../core/app_router.dart';
import '../../core/last_seen_label.dart';
import '../../core/realtime_client.dart';
import '../../l10n/locale_scope.dart';
import '../../models/app_user.dart';
import '../../models/emoji_story_send.dart';
import '../../models/emoji_story_stats.dart';
import '../../models/game.dart';
import '../../models/send.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/emoji_compose_bar.dart';
import '../box/box_scope.dart';
import '../box/box_service.dart';
import '../box/couple_profile_screen.dart';
import '../content/content_service.dart';
import '../home/widgets/couple_avatars_badge.dart';
import 'game_service.dart';
import 'widgets/emoji_story_match_scoreboard.dart';

/// "Devine mon émoji" façon vraie discussion (comme À nous deux/Vérité ou
/// Défi) : chaque story composée en émojis est UNE bulle, alignée du côté
/// de qui l'a envoyée — deviner/donner un verdict/redonner une chance se
/// passe directement dans cette même bulle (voir _StoryBubble), qui évolue
/// en place plutôt que de faire apparaître de nouveaux messages (voir
/// EmojiStorySend côté backend, UN SEUL Send par story du début à la fin).
class EmojiStorySessionScreen extends StatefulWidget {
  final Game game;
  final AppUser user;
  // Reprend cette discussion précise (voir EmojiStoryHistoryScreen, qui liste
  // les discussions passées) — null pour un tout nouveau "plan de jeu" : le
  // fil démarre vide, la toute première story envoyée crée la discussion
  // (voir _sendStory/GameService.sendEmojiStory).
  final String? sessionId;

  const EmojiStorySessionScreen({
    super.key,
    required this.game,
    required this.user,
    this.sessionId,
  });

  @override
  State<EmojiStorySessionScreen> createState() =>
      _EmojiStorySessionScreenState();
}

class _EmojiStorySessionScreenState extends State<EmojiStorySessionScreen> {
  final _controller = TextEditingController();
  bool _sendingStory = false;
  bool _pickerOpen = false;
  // Voir demande utilisateur : "on doit avoir la possibilité de mettre du
  // texte ou emoji... par défaut c'est les émoji" — mode par défaut (false)
  // = clavier émoji maison (comportement d'avant, inchangé) ; true = vrai
  // TextField avec clavier système classique. Bascule via l'icône à gauche
  // de la barre de composition (voir EmojiComposeBar, onToggleMode).
  bool _textMode = false;
  final _textFocusNode = FocusNode();
  // Voir demande utilisateur : "du clavier classique à émoji... ça remonte
  // afficher rapidement une erreur de pixel" — en repassant en mode émoji,
  // ouvrir le panneau émoji (hauteur fixe) EN MÊME TEMPS que le clavier
  // système commence à se refermer (lui, animé) faisait dépasser la hauteur
  // disponible le temps de cette fermeture (RenderFlex overflow visible).
  // Ce drapeau fait attendre que l'inset clavier soit revenu à 0 (voir
  // build()) avant d'insérer le panneau, sans ce chevauchement.
  bool _awaitingKeyboardCloseForPicker = false;

  // Plus récente d'abord (même forme que GameBoxHistoryScreen/fetchBoxHistory)
  // — affichée via une ListView `reverse: true`, qui se charge alors de tout
  // le travail d'alignement "façon chat" (la plus récente en bas) sans
  // aucune gymnastique de scroll manuelle.
  List<Send> _sends = [];
  bool _loading = true;
  bool _hasMore = false;
  bool _loadingMore = false;
  final _scrollController = ScrollController();

  // Voir demande utilisateur : "je veux cette entête déjà dans carnet de
  // bord" — même en-tête que SlideDetailScreen (CoupleAvatarsBadge + ligne
  // de présence), même canal presence que le Dashboard/les autres fils.
  bool _partnerPresent = false;

  AppUser? get _partner => BoxScope.of(context).currentBox?.partnerOf(widget.user.id);

  void _onPresenceChange(Set<String> memberIds) {
    if (!mounted) return;
    final partnerId = _partner?.id;
    final present = partnerId != null && memberIds.contains(partnerId);
    if (present != _partnerPresent) setState(() => _partnerPresent = present);
  }

  // Voir demande utilisateur : "position la bulle en haut, les prochains en
  // bas et ainsi de suite comme dans WhatsApp" — liste NON inversée
  // (ancienne en haut, récente en bas, voir _buildList), donc plus de
  // collage automatique au bas comme le faisait `reverse: true` : ces
  // helpers s'en chargent explicitement aux bons moments.
  bool get _isNearBottom =>
      !_scrollController.hasClients ||
      _scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 120;

  void _scrollToBottomSoon({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  // Copie locale mutable de widget.sessionId : reste nulle tant qu'aucune
  // story n'a encore été envoyée dans ce fil vide, puis se fixe à l'id
  // retourné par le tout premier envoi (voir _sendStory) — les envois
  // suivants de ce même écran s'y rattachent alors.
  String? _sessionId;

  // Score "match" propre à CETTE discussion (voir EmojiStoryController::
  // stats, désormais scopé par session — jamais cumulé sur l'ensemble des
  // discussions du couple, voir EmojiStoryMatchStats).
  EmojiStoryMatchStats? _matchStats;

  String? _subscribedBoxId;
  // Voir demande utilisateur : "es ce valable pour tous les autres [écrans]
  // de texte dans cette catégorie de jeu" — même filet de secours que
  // GameCardThreadScreen, absent ici jusqu'alors.
  StreamSubscription<void>? _resyncSub;

  // Sélection façon WhatsApp (voir _buildSelectionAppBar) : appui long sur
  // une bulle entre dedans, appui simple sur une autre bulle ensuite bascule
  // sa coche — la barre "modifier"/"supprimer" ne remplace l'AppBar normale
  // que tant que cet ensemble n'est pas vide.
  final Set<String> _selectedIds = {};
  bool get _selectionMode => _selectedIds.isNotEmpty;
  // Édition en place (voir _StoryBubble.editController) : le clavier émoji
  // reste à sa place habituelle en bas de l'écran (remplace la barre de
  // composition normale, voir build()) plutôt que d'être imbriqué dans la
  // bulle — seul le contrôleur est partagé, pour que la bulle affiche un
  // champ éditable (curseur déplaçable) qui se remplit au même rythme que
  // les émojis tapés en bas.
  String? _editingSendId;
  TextEditingController? _editController;

  bool _savingEdit = false;

  @override
  void initState() {
    super.initState();
    // Écran immersif façon chat (voir TimelineScreen._openSend pour le même
    // principe sur SlideDetailScreen) : la barre de navigation globale de
    // l'AppShell ne doit pas rester visible en dessous.
    AppRouter.showGlobalNavBar.value = false;
    // L'EmojiPicker écrit directement dans ce controller (voir build()) —
    // TextField.onChanged ne se déclenche pas pour une saisie programmatique,
    // d'où cet écouteur pour activer/désactiver le bouton d'envoi.
    _controller.addListener(() => setState(() {}));
    _sessionId = widget.sessionId;
    if (_sessionId != null) {
      _loadCachedThenRefresh();
      _loadStats();
    } else {
      // Fil vide, rien à charger tant qu'aucune story n'a été envoyée (voir
      // _sendStory).
      _loading = false;
    }
    _initRealtime();
    _resyncSub = RealtimeClient.instance.resyncRequests.listen((_) {
      if (_sessionId != null) _load();
    });
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      // Voir demande utilisateur : liste non inversée désormais (ancienne en
      // haut) — scroller VERS LE HAUT (pixels proche de 0) charge les
      // messages plus anciens, pas l'inverse comme avec `reverse: true`.
      if (_hasMore && !_loadingMore && position.pixels <= 200) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    // Différé au frame suivant (voir memory_game_board_screen.dart pour la
    // justification complète) — sans ça, cette mise à jour pouvait planter
    // silencieusement pendant le démontage (arbre de widgets verrouillé) et
    // laisser toute la coquille globale coincée masquée.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppRouter.showGlobalNavBar.value = true;
    });
    _resyncSub?.cancel();
    _controller.dispose();
    _editController?.dispose();
    _textFocusNode.dispose();
    _scrollController.dispose();
    if (_subscribedBoxId != null) {
      RealtimeClient.instance.unsubscribeFromBox(
        _subscribedBoxId!,
        onEvent: _onRealtimeEvent,
        onPresenceChange: _onPresenceChange,
      );
    }
    super.dispose();
  }

  Future<void> _loadCachedThenRefresh() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    try {
      // Un cache local d'avant la refonte de "Devine mon émoji" (voir
      // EmojiStorySend, désormais un historique de tentatives plutôt qu'un
      // devine/verdict unique) a une forme JSON incompatible avec les
      // modèles actuels — sans ce garde-fou, l'exception de parsing
      // remontait non interceptée et _load() ci-dessous n'était JAMAIS
      // appelé, laissant l'écran bloqué sur son spinner indéfiniment.
      final cached = await GameService.instance.cachedEmojiStoryHistory(
        sessionId,
      );
      if (cached != null && mounted) {
        setState(() {
          _sends = cached.items;
          _hasMore = cached.hasMore;
          _loading = false;
        });
        _markIncomingAsSeen();
        // Voir demande utilisateur : liste non inversée désormais (voir
        // _buildList) — le dernier message n'est plus automatiquement visible
        // à l'écran comme avec `reverse: true`, il faut y scroller soi-même.
        _scrollToBottomSoon();
      }
    } catch (_) {
      // Ignoré — le fetch réseau ci-dessous fait foi et remplacera ce
      // cache obsolète par la bonne forme dès qu'il réussit.
    }
    await _load();
  }

  Future<void> _load() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    try {
      final page = await GameService.instance.fetchEmojiStoryHistory(
        widget.game.id,
        sessionId,
      );
      if (!mounted) return;
      setState(() {
        _sends = page.items;
        _hasMore = page.hasMore;
        _loading = false;
      });
      _markIncomingAsSeen();
      _scrollToBottomSoon();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final sessionId = _sessionId;
    if (sessionId == null || !_hasMore || _loadingMore || _sends.isEmpty)
      return;
    setState(() => _loadingMore = true);
    // Voir demande utilisateur : liste non inversée (ancienne en haut) — les
    // messages plus anciens s'insèrent maintenant AU-DESSUS du contenu déjà
    // visible, ce qui décalerait tout vers le bas sans ce correctif (saut
    // visuel classique). On mesure la hauteur ajoutée après coup et on
    // décale le scroll d'autant, pour que ce qui était visible le reste.
    final extentBefore = _scrollController.hasClients ? _scrollController.position.maxScrollExtent : 0.0;
    try {
      final page = await GameService.instance.fetchEmojiStoryHistory(
        widget.game.id,
        sessionId,
        beforeId: _sends.last.id,
      );
      if (!mounted) return;
      setState(() {
        _sends = [..._sends, ...page.items];
        _hasMore = page.hasMore;
      });
      _markIncomingAsSeen();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final added = _scrollController.position.maxScrollExtent - extentBefore;
        if (added > 0) _scrollController.jumpTo(_scrollController.position.pixels + added);
      });
    } catch (_) {
      // best effort — l'utilisateur pourra réessayer en re-scrollant.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _loadStats() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    final cached = await GameService.instance.cachedEmojiStoryStats(sessionId);
    if (cached != null && mounted) {
      setState(() => _matchStats = cached);
    }
    try {
      final stats = await GameService.instance.fetchEmojiStoryStats(
        widget.game.id,
        sessionId,
      );
      if (!mounted) return;
      setState(() => _matchStats = stats);
    } catch (_) {
      // best effort — le badge garde la dernière valeur connue.
    }
  }

  /// Toute story reçue déjà affichée est marquée lue dès l'ouverture — même
  /// principe que GameBoxHistoryScreen._markIncomingAsSeen : pas d'accusé
  /// "vu mais pas encore lu" séparé, ouvrir l'écran vaut lecture.
  void _markIncomingAsSeen() {
    for (final send in _sends) {
      if (send.recipientId == widget.user.id && send.status != 'seen')
        _markSeen(send);
    }
  }

  Future<void> _markSeen(Send send) async {
    try {
      await ContentService.instance.markSeen(send.id);
      if (!mounted) return;
      _applySeen(send.id, DateTime.now());
    } catch (_) {
      // best effort — pas grave si ça rate, un prochain passage réessaiera.
    }
  }

  void _applySeen(String sendId, DateTime seenAt) {
    if (!mounted) return;
    final index = _sends.indexWhere((s) => s.id == sendId);
    if (index == -1) return;
    setState(() {
      final copy = List<Send>.of(_sends);
      copy[index] = copy[index].copyWith(status: 'seen', seenAt: seenAt);
      _sends = copy;
    });
  }

  void _applyDelivered(List<String> sendIds, DateTime deliveredAt) {
    if (!mounted) return;
    setState(() {
      _sends = _sends
          .map(
            (s) => sendIds.contains(s.id) && s.status == 'sent'
                ? s.copyWith(status: 'delivered', deliveredAt: deliveredAt)
                : s,
          )
          .toList();
    });
  }

  Future<void> _initRealtime() async {
    final coupleBoxId = BoxService.instance.currentBox?.id;
    if (coupleBoxId == null) return;
    _subscribedBoxId = coupleBoxId;
    try {
      await RealtimeClient.instance.subscribeToBox(
        coupleBoxId,
        onEvent: _onRealtimeEvent,
        onPresenceChange: _onPresenceChange,
      );
    } catch (_) {
      // Best effort — l'écran reste utilisable, juste sans mise à jour
      // immédiate des nouvelles stories/devinettes/verdicts.
    }
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.event == 'SendCreated') {
      final sendJson = event.data?['send'] as Map<String, dynamic>?;
      if (sendJson == null) return;
      final send = Send.fromJson(sendJson);
      // Filtré par discussion précise, pas juste par jeu : une Box peut
      // avoir plusieurs "plans de jeu" en parallèle (voir
      // EmojiStoryHistoryScreen), une nouvelle story dans UN AUTRE fil ne
      // doit pas apparaître ici.
      if (send.sendableType != 'emoji_story' ||
          send.emojiStory?.sessionId != _sessionId)
        return;
      if (!mounted) return;
      if (_sends.any((s) => s.id == send.id)) return;
      // Voir demande utilisateur : liste non inversée — ne force le scroll
      // vers le nouveau message QUE si on était déjà en bas (sinon, décidé
      // AVANT d'insérer le nouveau message, sans quoi on serait "déjà en
      // bas" de la liste allongée et on scrollerait même en train de lire
      // l'historique plus haut).
      final wasNearBottom = _isNearBottom;
      setState(() => _sends = [send, ..._sends]);
      if (wasNearBottom) _scrollToBottomSoon(animate: true);
      // L'écran est ouvert : la nouvelle story reçue est immédiatement "vue",
      // pas juste "envoyée" — même principe que GameBoxHistoryScreen.
      if (send.recipientId == widget.user.id) _markSeen(send);
      return;
    }
    if (event.event == 'SendSeen') {
      final sendId = event.data?['send_id'] as String?;
      if (sendId == null) return;
      final seenAtStr = event.data?['seen_at'] as String?;
      _applySeen(
        sendId,
        seenAtStr != null ? DateTime.parse(seenAtStr) : DateTime.now(),
      );
      return;
    }
    if (event.event == 'SendDelivered') {
      final sendIds = (event.data?['send_ids'] as List?)
          ?.map((e) => e as String)
          .toList();
      if (sendIds == null || sendIds.isEmpty) return;
      final deliveredAtStr = event.data?['delivered_at'] as String?;
      _applyDelivered(
        sendIds,
        deliveredAtStr != null
            ? DateTime.parse(deliveredAtStr)
            : DateTime.now(),
      );
      return;
    }
    if (event.event == 'EmojiStoryUpdated') {
      final sendJson = event.data?['send'] as Map<String, dynamic>?;
      if (sendJson == null) return;
      final updated = Send.fromJson(sendJson);
      if (updated.emojiStory?.sessionId != _sessionId) return;
      if (!mounted) return;
      _replaceSend(updated);
      // Une story vient peut-être d'être résolue par l'AUTRE membre du
      // couple — rafraîchit le score de CETTE discussion sans attendre la
      // prochaine ouverture de l'écran.
      _loadStats();
    }
  }

  void _replaceSend(Send updated) {
    final index = _sends.indexWhere((s) => s.id == updated.id);
    if (index == -1) return;
    setState(() {
      final copy = List<Send>.of(_sends);
      copy[index] = updated;
      _sends = copy;
    });
  }

  void _openPicker() => setState(() => _pickerOpen = true);

  /// Icône à gauche de la barre de composition — voir demande utilisateur :
  /// bascule le MODE (émoji <-> texte classique), pas juste l'ouverture du
  /// clavier émoji comme avant. L'icône affichée représente ce que le tap
  /// déclenchera (voir EmojiComposeBar), pas le mode courant.
  ///
  /// Voir demande utilisateur : émoji -> texte : autofocus (voir
  /// EmojiComposeBar) s'en charge, instantané. Texte -> émoji : NE PAS
  /// ouvrir le panneau émoji tout de suite — le clavier système met un
  /// instant à se refermer en s'animant, et l'ouvrir en même temps faisait
  /// dépasser la hauteur disponible le temps de cette fermeture (overflow
  /// visible, voir demande utilisateur) ; _awaitingKeyboardCloseForPicker
  /// fait attendre la fin de cette fermeture (voir build()) avant d'insérer
  /// le panneau.
  void _toggleComposeMode() {
    final enteringTextMode = !_textMode;
    setState(() {
      _textMode = enteringTextMode;
      _pickerOpen = false;
      _awaitingKeyboardCloseForPicker = !enteringTextMode;
    });
    if (!enteringTextMode) _textFocusNode.unfocus();
  }

  Future<void> _sendStory() async {
    final emojis = _controller.text.trim();
    if (emojis.isEmpty || _sendingStory) return;
    setState(() => _sendingStory = true);
    try {
      final send = await GameService.instance.sendEmojiStory(
        widget.game.id,
        emojis,
        sessionId: _sessionId,
      );
      if (!mounted) return;
      _controller.clear();
      final isFirstStoryOfSession = _sessionId == null;
      setState(() {
        // Tout premier envoi d'un fil vide (voir widget.sessionId) : la
        // discussion vient d'être créée côté serveur, les envois suivants de
        // cet écran s'y rattachent désormais.
        _sessionId ??= send.emojiStory?.sessionId;
        if (!_sends.any((s) => s.id == send.id)) _sends = [send, ..._sends];
        _pickerOpen = false;
        // Voir demande utilisateur : "par défaut c'est les émoji" — revient
        // au mode par défaut après l'envoi, plutôt que de garder le clavier
        // système ouvert sur une barre vidée.
        _textMode = false;
      });
      _textFocusNode.unfocus();
      // Voir demande utilisateur : liste non inversée — je veux toujours voir
      // le message que je viens d'envoyer, contrairement à une réception où
      // on ne force le scroll que si on était déjà en bas (voir
      // _onRealtimeEvent).
      _scrollToBottomSoon(animate: true);
      if (isFirstStoryOfSession) _loadStats();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sendingStory = false);
    }
  }

  Future<void> _handleEdit(Send send, String emojis) async {
    final updated = await GameService.instance.editEmojiStory(
      send.emojiStory!.id,
      emojis,
    );
    if (!mounted) return;
    _replaceSend(updated);
  }

  Future<void> _handleDelete(Send send) async {
    final updated = await GameService.instance.deleteEmojiStory(
      send.emojiStory!.id,
    );
    if (!mounted) return;
    _replaceSend(updated);
  }

  bool _canManage(Send send) =>
      send.senderId == widget.user.id && !(send.emojiStory?.isDeleted ?? true);

  // La story ne peut plus être modifiée dès qu'une devinette a été
  // proposée dessus (voir EmojiStoryController::update) — seule la
  // suppression reste possible à tout moment (voir _canManage).
  bool _canEditStory(Send send) =>
      _canManage(send) && (send.emojiStory?.guesses.isEmpty ?? false);

  void _toggleSelect(String sendId) {
    // Pas de sélection pendant une édition en cours — évite un état où les
    // deux flux se marchent dessus (voir _startEditSelected).
    if (_editingSendId != null) return;
    setState(() {
      if (_selectedIds.contains(sendId)) {
        _selectedIds.remove(sendId);
      } else {
        _selectedIds.add(sendId);
      }
    });
  }

  void _clearSelection() => setState(_selectedIds.clear);

  /// Édition en place (voir _StoryBubble.editController) — sélectionner une
  /// seule story modifiable puis taper le crayon dans la barre de sélection
  /// y bascule. Le clavier émoji apparaît alors À SA PLACE HABITUELLE en
  /// bas de l'écran (voir build()), pas imbriqué dans la bulle : seul le
  /// contrôleur de texte est partagé entre les deux.
  void _startEditSelected() {
    if (_selectedIds.length != 1) return;
    final id = _selectedIds.first;
    final send = _sends.firstWhere(
      (s) => s.id == id,
      orElse: () => _sends.first,
    );
    if (!_canEditStory(send)) return;
    setState(() {
      _editingSendId = id;
      _editController = TextEditingController(
        text: send.emojiStory?.emojis ?? '',
      );
      _selectedIds.clear();
    });
  }

  Future<void> _saveInlineEdit() async {
    final id = _editingSendId;
    final controller = _editController;
    if (id == null || controller == null || _savingEdit) return;
    final text = controller.text.trim();
    if (text.isEmpty) return;
    final send = _sends.firstWhere(
      (s) => s.id == id,
      orElse: () => _sends.first,
    );
    setState(() => _savingEdit = true);
    try {
      await _handleEdit(send, text);
      if (!mounted) return;
      _clearInlineEdit();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _savingEdit = false);
    }
  }

  void _cancelInlineEdit() {
    if (_savingEdit) return;
    _clearInlineEdit();
  }

  void _clearInlineEdit() {
    final old = _editController;
    setState(() {
      _editingSendId = null;
      _editController = null;
    });
    old?.dispose();
  }

  Future<void> _confirmDeleteSelected() async {
    final manageable = _sends
        .where((s) => _selectedIds.contains(s.id) && _canManage(s))
        .toList();
    if (manageable.isEmpty) {
      _clearSelection();
      return;
    }
    final t = LocaleScope.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          manageable.length > 1
              ? t('emoji_story_delete_many_title', {
                  'count': '${manageable.length}',
                })
              : t('emoji_story_delete_one_title'),
        ),
        content: Text(t('photo_remove_confirm_content')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t('common_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              t('common_delete'),
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _clearSelection();
    for (final send in manageable) {
      try {
        await _handleDelete(send);
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final partnerName =
        BoxScope.of(context).currentBox?.partnerOf(widget.user.id)?.prenom ??
        'ton/ta partenaire';

    // Voir _toggleComposeMode/_awaitingKeyboardCloseForPicker : MediaQuery
    // se reconstruit à chaque frame de l'animation de fermeture du clavier
    // système, donc ce test revoit bien passer l'inset à 0 progressivement
    // — dès que c'est le cas, le panneau émoji (hauteur fixe) peut enfin
    // s'insérer sans dépasser la hauteur disponible.
    if (_awaitingKeyboardCloseForPicker && MediaQuery.of(context).viewInsets.bottom == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _pickerOpen = true;
          _awaitingKeyboardCloseForPicker = false;
        });
      });
    }

    final pickerOpen = _pickerOpen || _editingSendId != null;
    return PopScope(
      // Le clavier émoji maison n'est pas un vrai clavier système (voir
      // SlideDetailScreen, même correctif) : le bouton/geste retour du
      // téléphone ne le referme pas tout seul. On intercepte donc le
      // premier retour pour le fermer, et seul un second retour (clavier
      // déjà fermé) quitte réellement l'écran.
      canPop: !pickerOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_editingSendId != null) {
          _cancelInlineEdit();
        } else if (_pickerOpen) {
          setState(() => _pickerOpen = false);
        }
      },
      child: Scaffold(
        backgroundColor: theme.background,
        appBar: _selectionMode ? _buildSelectionAppBar(theme) : null,
        body: ThemedBackground(
          child: SafeArea(
            child: Column(
              children: [
                // Voir demande utilisateur : "je veux cette entête déjà dans
                // carnet de bord" — copie conforme de SlideDetailScreen (back
                // + CoupleAvatarsBadge + présence, centrés), remplace le
                // simple titre texte + badge score d'avant (le score reste,
                // juste déplacé à la place du cœur qui n'a pas de sens ici).
                if (!_selectionMode)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: theme.textOnBackground),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
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
                        if (_matchStats != null && _matchStats!.totalResolved > 0)
                          InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => showEmojiStoryMatchScoreboard(
                              context,
                              theme: theme,
                              stats: _matchStats!,
                              myUserId: widget.user.id,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: theme.surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: theme.primary.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('🔮', style: TextStyle(fontSize: 12)),
                                  const SizedBox(width: 5),
                                  Text(
                                    '${_matchStats!.totalFirstTry}/${_matchStats!.totalResolved}',
                                    style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: theme.textOnBackground),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(Icons.chevron_right_rounded, size: 14, color: theme.textOnBackgroundMuted),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                Expanded(child: _buildList(theme, partnerName)),
                // Édition en cours : le clavier émoji reprend sa place
                // habituelle en bas (voir _editController), à la place de la
                // barre de composition normale — jamais imbriqué dans la
                // bulle elle-même (voir _StoryBubble.editController, juste un
                // champ éditable qui partage ce même contrôleur).
                if (_editingSendId != null && _editController != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: _buildEditBar(theme),
                  ),
                  EmojiPickerPanel(
                    theme: theme,
                    controller: _editController!,
                    onClose: _cancelInlineEdit,
                  ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: EmojiComposeBar(
                      theme: theme,
                      controller: _controller,
                      pickerOpen: _pickerOpen,
                      textMode: _textMode,
                      textFocusNode: _textFocusNode,
                      sending: _sendingStory,
                      placeholder: LocaleScope.of(
                        context,
                      ).t('emoji_story_compose_placeholder'),
                      onTapField: _openPicker,
                      onToggleMode: _toggleComposeMode,
                      onSend: _sendStory,
                    ),
                  ),
                  if (_pickerOpen)
                    EmojiPickerPanel(
                      theme: theme,
                      controller: _controller,
                      onClose: () => setState(() => _pickerOpen = false),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "En ligne" (canal presence temps réel) ou "Vu il y a X" sous les
  /// avatars — copie conforme de SlideDetailScreen._presenceLine (voir
  /// demande utilisateur : "je veux cette entête déjà dans carnet de bord").
  Widget _presenceLine(ThemePalette theme) {
    final online = _partnerPresent;
    final label = online ? LocaleScope.of(context).t('presence_online') : lastSeenLabel(context, _partner?.lastSeenAt);
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

  /// Barre "N sélectionné(s)" avec Modifier/Supprimer — remplace l'AppBar
  /// normale tant que la sélection n'est pas vide (voir _selectionMode).
  PreferredSizeWidget _buildSelectionAppBar(ThemePalette theme) {
    final selectedSends = _sends
        .where((s) => _selectedIds.contains(s.id))
        .toList();
    final canEdit =
        selectedSends.length == 1 && _canEditStory(selectedSends.first);
    final canDelete = selectedSends.any(_canManage);
    final t = LocaleScope.of(context).t;
    return AppBar(
      backgroundColor: theme.surface,
      elevation: 1,
      foregroundColor: theme.textOnBackground,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: t('emoji_story_cancel_selection_tooltip'),
        onPressed: _clearSelection,
      ),
      title: Text(
        t('emoji_story_selection_count', {'count': '${_selectedIds.length}'}),
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w700,
          color: theme.textOnBackground,
        ),
      ),
      actions: [
        if (canEdit)
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            tooltip: t('common_edit'),
            onPressed: _startEditSelected,
          ),
        if (canDelete)
          IconButton(
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Colors.redAccent,
            ),
            tooltip: t('common_delete'),
            onPressed: _confirmDeleteSelected,
          ),
      ],
    );
  }

  /// Barre du bas pendant une édition en place — remplace EmojiComposeBar,
  /// le clavier émoji (voir EmojiPickerPanel juste en dessous, voir build())
  /// écrit dans le MÊME contrôleur que le champ éditable affiché dans la
  /// bulle (voir _StoryBubble.editController). Juste les deux actions,
  /// aucune étiquette : le champ éditable dans la bulle suffit à indiquer
  /// qu'on est en train de modifier.
  Widget _buildEditBar(ThemePalette theme) {
    final t = LocaleScope.of(context).t;
    return Row(
      children: [
        Expanded(
          child: _SmallActionButton(
            label: t('common_cancel'),
            color: theme.textOnBackgroundMuted,
            filled: false,
            onTap: _savingEdit ? null : _cancelInlineEdit,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SmallActionButton(
            label: t('common_save'),
            color: theme.primary,
            filled: true,
            loading: _savingEdit,
            onTap: _savingEdit ? null : _saveInlineEdit,
          ),
        ),
      ],
    );
  }

  Widget _buildList(ThemePalette theme, String partnerName) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sends.isEmpty) {
      return _EmptyChatArea(
        theme: theme,
        partnerName: partnerName,
        onTap: _openPicker,
      );
    }

    // Voir demande utilisateur : "position la bulle en haut, les prochains
    // en bas... comme dans WhatsApp" — _sends reste "plus récente d'abord"
    // (voir sa doc, utilisée par _loadMore/beforeId), on inverse juste ici
    // pour l'affichage (la plus ancienne en premier, en haut de la liste).
    final ordered = _sends.reversed.toList();
    final loaderOffset = _loadingMore ? 1 : 0;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: ordered.length + loaderOffset,
      itemBuilder: (context, index) {
        if (_loadingMore && index == 0) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final send = ordered[index - loaderOffset];
        // Clé stable par story (voir son id, jamais l'index) : sans ça, une
        // nouvelle story insérée en tête décale les positions et Flutter
        // réutilise par erreur l'état local (devinette en cours de saisie,
        // etc.) d'UNE bulle pour une AUTRE story.
        return _StoryBubble(
          key: ValueKey(send.id),
          theme: theme,
          send: send,
          myUserId: widget.user.id,
          selectionMode: _selectionMode,
          selected: _selectedIds.contains(send.id),
          onToggleSelect: () => _toggleSelect(send.id),
          editController: _editingSendId == send.id ? _editController : null,
        );
      },
    );
  }
}

/// Zone haute quand aucune story n'a encore été échangée — invite visuelle
/// cohérente avec l'habillage "tchat" de l'écran.
class _EmptyChatArea extends StatelessWidget {
  final ThemePalette theme;
  final String partnerName;
  final VoidCallback onTap;

  const _EmptyChatArea({
    required this.theme,
    required this.partnerName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.translucent,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      theme.primary.withValues(alpha: 0.25),
                      theme.secondary.withValues(alpha: 0.15),
                    ],
                  ),
                ),
                child: const Text('🔮', style: TextStyle(fontSize: 32)),
              ),
              const SizedBox(height: 16),
              Text(
                LocaleScope.of(
                  context,
                ).t('emoji_story_empty_title', {'name': partnerName}),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.textOnBackground,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                LocaleScope.of(context).t('emoji_story_empty_subtitle'),
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  color: theme.textOnBackgroundMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une story = UNE bulle, alignée du côté de qui l'a composée — qui évolue
/// en place au fil des devinettes/verdicts (voir EmojiStorySend), jamais
/// remplacée par de nouveaux messages. Porte son propre état local éphémère
/// (saisie de devinette en cours, révélation en cours) via [StatefulWidget].
class _StoryBubble extends StatefulWidget {
  final ThemePalette theme;
  final Send send;
  final String myUserId;
  // Sélection façon WhatsApp (voir _EmojiStorySessionScreenState) : appui
  // long entre en sélection, appui simple (tant qu'elle est active) bascule
  // la coche de CETTE bulle.
  final bool selectionMode;
  final bool selected;
  final VoidCallback onToggleSelect;
  // Édition en place (voir _buildInlineEditor) — non-null uniquement pour
  // LA bulle en cours d'édition (voir _EmojiStorySessionScreenState), avec
  // le MÊME contrôleur que le clavier émoji affiché en bas de l'écran (voir
  // build()) : ce n'est jamais la bulle elle-même qui porte le clavier.
  final TextEditingController? editController;

  const _StoryBubble({
    super.key,
    required this.theme,
    required this.send,
    required this.myUserId,
    required this.selectionMode,
    required this.selected,
    required this.onToggleSelect,
    required this.editController,
  });

  @override
  State<_StoryBubble> createState() => _StoryBubbleState();
}

class _StoryBubbleState extends State<_StoryBubble> {
  /// Coche de sélection façon WhatsApp — toujours à gauche de la bulle,
  /// quel que soit le côté d'alignement de celle-ci.
  Widget _buildCheckbox(ThemePalette theme) {
    return Container(
      width: 22,
      height: 22,
      margin: const EdgeInsets.only(right: 8, top: 14),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.selected ? theme.primary : Colors.transparent,
        border: Border.all(
          color: widget.selected
              ? theme.primary
              : theme.textOnBackgroundMuted.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: widget.selected
          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
          : null,
    );
  }

  /// Édition EN PLACE dans la bulle — un vrai champ éditable (curseur
  /// déplaçable à la souris/au doigt) lié au MÊME contrôleur que le clavier
  /// émoji affiché à sa place habituelle en bas de l'écran (voir
  /// _EmojiStorySessionScreenState.build) : la bulle ne porte jamais le
  /// clavier elle-même, juste ce champ.
  Widget _buildInlineEditor(
    ThemePalette theme,
    Color onColor,
    Color mutedColor,
    TextEditingController controller,
  ) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onColor.withValues(alpha: 0.5), width: 1.5),
      ),
      child: TextField(
        controller: controller,
        autofocus: true,
        // Curseur/sélection réels (pour pouvoir déplacer le point
        // d'insertion) mais SANS le clavier natif — seul le clavier émoji
        // affiché en bas doit pouvoir écrire ici, comme pour la composition
        // normale (voir EmojiComposeBar, qui évite le clavier classique de
        // la même façon).
        keyboardType: TextInputType.none,
        minLines: 1,
        maxLines: 3,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 24, color: onColor),
        cursorColor: onColor,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        ),
      ),
    );
  }

  String _time(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  /// Couleur de texte sur la bulle "mine" — toujours blanc, même convention
  /// que le reste de l'app pour ses bulles en dégradé (voir _ChatBubble
  /// dans game_box_history_screen.dart), depuis que la bulle "mine" utilise
  /// elle aussi le dégradé rose→violet plutôt qu'un fond plein.
  Color get _onColor => Colors.white;

  /// Petit bloc imbriqué DANS la bulle — façon citation de réponse
  /// (Telegram/WhatsApp) : une fine bordure gauche + un fond très légèrement
  /// teinté distinguent la devinette/révélation du message principal, mais
  /// TOUJOURS dans la MÊME famille de couleur que la bulle (juste une
  /// variation d'opacité de [_onColor]/[theme.textOnBackground], jamais une
  /// couleur qui jure) — le contraste rejeté était entre couleurs
  /// différentes, pas entre nuances d'une même couleur.
  Widget _replyBlock({
    required bool bubbleMine,
    required String label,
    required Widget content,
  }) {
    final onColor = bubbleMine ? _onColor : widget.theme.textOnBackground;
    final labelColor = onColor.withValues(alpha: 0.7);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
      decoration: BoxDecoration(
        color: onColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: onColor.withValues(alpha: 0.35), width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: labelColor,
            ),
          ),
          const SizedBox(height: 2),
          DefaultTextStyle(
            style: GoogleFonts.nunito(fontSize: 13, color: onColor),
            child: content,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final story = widget.send.emojiStory;
    if (story == null) return const SizedBox.shrink();

    final composerId = widget.send.senderId;
    final guesserId = widget.send.recipientId;
    // La bulle ENTIÈRE est alignée du côté de qui a composé la story — la
    // devinette/le verdict vivent DANS cette même bulle (voir _replyBlock),
    // pas dans des bulles séparées de l'autre côté de l'écran.
    final mine = composerId == widget.myUserId;
    final onColor = mine ? _onColor : theme.textOnBackground;
    final mutedColor = onColor.withValues(alpha: 0.7);
    final t = LocaleScope.of(context).t;
    final guesserName = guesserId == widget.myUserId
        ? t('common_you')
        : (widget.send.recipient?.prenom ?? t('common_partner_fallback'));
    final composerName = mine
        ? t('common_you')
        : (widget.send.sender?.prenom ?? t('common_partner_fallback'));

    final isEditing = widget.editController != null;

    late final Widget content;
    if (isEditing) {
      // Édition en place — remplace tout le reste (voir _buildInlineEditor),
      // aucune autre action possible tant qu'on édite.
      content = _buildInlineEditor(
        theme,
        onColor,
        mutedColor,
        widget.editController!,
      );
    } else if (story.isDeleted) {
      // Story supprimée (voir onDelete) : plus rien d'autre à afficher que
      // le repli, façon WhatsApp — ni émojis, ni devinettes, ni actions.
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block_rounded, size: 14, color: mutedColor),
          const SizedBox(width: 6),
          Text(
            LocaleScope.of(context).t('emoji_story_deleted_message'),
            style: GoogleFonts.nunito(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: mutedColor,
            ),
          ),
        ],
      );
    } else {
      content = _buildNormalContent(
        theme,
        story,
        composerId,
        guesserId,
        mine,
        onColor,
        mutedColor,
        guesserName,
        composerName,
      );
    }

    final shell = _buildBubbleShell(
      theme: theme,
      mine: mine,
      // Appui long : entre en sélection (ou y ajoute cette bulle) — jamais
      // pendant qu'on édite. Appui simple : ne bascule la coche que si la
      // sélection est déjà active (sinon la bulle n'a pas d'action normale).
      onLongPress: isEditing ? null : widget.onToggleSelect,
      onTap: (!isEditing && widget.selectionMode)
          ? widget.onToggleSelect
          : null,
      child: content,
    );

    if (!widget.selectionMode) return shell;

    // Coche toujours à gauche, quel que soit le côté de la bulle — même
    // geste que la sélection multiple de WhatsApp.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCheckbox(theme),
        Expanded(child: shell),
      ],
    );
  }

  Widget _buildNormalContent(
    ThemePalette theme,
    EmojiStorySend story,

    String composerId,
    String guesserId,
    bool mine,
    Color onColor,
    Color mutedColor,
    String guesserName,
    String composerName,
  ) {
    final blocks = <Widget>[];
    for (final g in story.guesses) {
      if (g.isCorrect == null) continue;
      blocks.add(
        _replyBlock(
          bubbleMine: mine,
          label: LocaleScope.of(
            context,
          ).t('emoji_story_guess_label', {'name': guesserName}),
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                g.isCorrect! ? Icons.check_rounded : Icons.close_rounded,
                size: 14,
                color: g.isCorrect! ? onColor : mutedColor,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: LocaleScope.of(context).t(
                          g.isCorrect!
                              ? 'emoji_story_guess_correct'
                              : 'emoji_story_guess_missed',
                        ),
                        style: const TextStyle(decoration: TextDecoration.none),
                      ),
                      TextSpan(text: g.guess),
                    ],
                  ),
                  style: TextStyle(
                    color: g.isCorrect! ? onColor : mutedColor,
                    decoration: g.isCorrect!
                        ? null
                        : TextDecoration.lineThrough,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      if (g.reveal != null && g.reveal!.isNotEmpty) {
        blocks.add(
          _replyBlock(
            bubbleMine: mine,
            label: composerName,
            content: Text(
              g.reveal!,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
        );
      }
    }

    // Voir demande utilisateur : "conversation classique... sans demande de
    // deviner, donner le verdict" — plus aucune nouvelle story n'invite à
    // deviner (ni _buildPendingGuessBlock ni _buildStatusArea, qui ne
    // couvraient QUE les prompts "à toi de deviner"/"verdict à donner").
    // Les devinettes/verdicts DÉJÀ donnés avant ce changement restent
    // affichés ci-dessus (voir `blocks`) — historique en lecture seule,
    // jamais un nouveau message n'en recrée.

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          story.emojis,
          // Voir demande utilisateur : du texte libre peut maintenant être
          // envoyé (pas seulement des émojis, voir EmojiComposeBar) — sans
          // `color: onColor`, du texte classique (contrairement aux glyphes
          // émoji, qui ignorent TextStyle.color) pouvait devenir illisible
          // sur le dégradé d'une bulle "mine".
          style: TextStyle(fontSize: 20, height: 1.3, color: onColor),
          textAlign: TextAlign.left,
        ),
        const SizedBox(height: 6),
        ...blocks,
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (story.isEdited) ...[
                Text(
                  LocaleScope.of(context).t('emoji_story_edited_tag'),
                  style: GoogleFonts.nunito(
                    fontSize: 10.5,
                    fontStyle: FontStyle.italic,
                    color: mutedColor,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                _time(widget.send.createdAt),
                style: GoogleFonts.nunito(fontSize: 10.5, color: mutedColor),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Le conteneur de la bulle (fond plein + coin pointu côté expéditeur·rice,
  /// voir le commentaire d'origine) — partagé entre le contenu normal et le
  /// repli "Story supprimée", pour que les deux gardent exactement le même
  /// gabarit visuel.
  Widget _buildBubbleShell({
    required ThemePalette theme,
    required bool mine,
    required VoidCallback? onLongPress,
    required VoidCallback? onTap,
    required Widget child,
  }) {
    return GestureDetector(
      onLongPress: onLongPress,
      onTap: onTap,
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              // Dégradé rose→violet côté "moi", comme partout ailleurs dans
              // l'app (voir _ChatBubble dans game_box_history_screen.dart) —
              // aligné pour que cet écran ne détonne plus visuellement (voir
              // demande utilisateur).
              gradient: mine
                  ? LinearGradient(colors: [theme.primary, theme.secondary])
                  : null,
              color: mine ? null : theme.surface,
              // Coin "pointu" du côté de l'expéditeur·rice (même traitement
              // que les bulles de texte du Carnet de bord/discussions de jeu).
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(mine ? 18 : 4),
                bottomRight: Radius.circular(mine ? 4 : 18),
              ),
              border: mine
                  ? null
                  : Border.all(color: theme.primary.withValues(alpha: 0.15)),
            ),
            // Voir demande utilisateur : "la bulle est trop grande pour ce
            // message" — le contenu se termine par un Align(centerRight)
            // pour l'horodatage (voir _buildNormalContent), qui sans
            // IntrinsicWidth force toute la colonne (et donc la bulle) à
            // s'étirer jusqu'à maxWidth même pour un texte très court, un
            // Align sans widthFactor "remplissant" par défaut toute la
            // largeur disponible dès qu'il sert à déterminer la largeur
            // préférée de son ancêtre Column.
            child: IntrinsicWidth(child: child),
          ),
        ),
      ),
    );
  }
}

/// Petit bouton compact réutilisé par la barre de sélection (Modifier/
/// Supprimer, voir _buildSelectionAppBar) — pleine couleur ou juste
/// contourné, avec un mini spinner intégré pendant l'envoi.
class _SmallActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;
  final bool loading;
  final VoidCallback? onTap;

  const _SmallActionButton({
    required this.label,
    required this.color,
    required this.filled,
    this.loading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final fg = filled ? Colors.white : color;

    return Opacity(
      opacity: disabled && !loading ? 0.5 : 1,
      child: Material(
        color: filled ? color : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: filled
                  ? null
                  : Border.all(color: fg.withValues(alpha: 0.5)),
            ),
            child: loading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                : Text(
                    label,
                    style: GoogleFonts.nunito(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Trois petits points qui rebondissent l'un après l'autre — purement
/// décoratif (ce n'est PAS une détection de frappe en direct côté
/// partenaire, juste un signal visuel "c'est en attente", façon indicateur
/// de saisie des messageries classiques).
