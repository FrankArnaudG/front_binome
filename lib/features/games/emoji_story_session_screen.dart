import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../core/app_router.dart';
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
import '../../widgets/send_status_tick.dart';
import '../../widgets/waiting_dots.dart';
import '../box/box_scope.dart';
import '../box/box_service.dart';
import '../content/content_service.dart';
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

  // Un champ classique (deviner/révéler/corriger une devinette, voir
  // _StoryBubble.onGuessFieldFocusChanged) a le focus dans au moins une
  // bulle — sert à cacher la barre de composition normale pendant ce
  // temps : suivi explicite par focus plutôt que MediaQuery.viewInsets
  // (peu fiable ici, Scaffold retire déjà l'inset clavier pour le corps
  // avant qu'on ait pu le lire dans certains cas constatés en réel).
  final Set<String> _focusedGuessFieldIds = {};
  bool get _keyboardOpen => _focusedGuessFieldIds.isNotEmpty;

  void _setGuessFieldFocus(String sendId, bool focused) {
    setState(() {
      if (focused) {
        _focusedGuessFieldIds.add(sendId);
      } else {
        _focusedGuessFieldIds.remove(sendId);
      }
    });
  }

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
      if (_hasMore &&
          !_loadingMore &&
          position.pixels >= position.maxScrollExtent - 200) {
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
      setState(() => _sends = [send, ..._sends]);
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

  Future<void> _handleGuess(Send send, String guess) async {
    final updated = await GameService.instance.guessEmojiStory(
      send.emojiStory!.id,
      guess,
    );
    if (!mounted) return;
    _replaceSend(updated);
  }

  Future<void> _handleVerdict(
    Send send, {
    required bool correct,
    bool? retry,
    String? reveal,
  }) async {
    final updated = await GameService.instance.submitEmojiStoryVerdict(
      send.emojiStory!.id,
      correct: correct,
      retry: retry,
      reveal: reveal,
    );
    if (!mounted) return;
    _replaceSend(updated);
    if (correct || retry == false) _loadStats();
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

  Future<void> _handleEditGuess(String guessId, String guess) async {
    final updated = await GameService.instance.editEmojiGuess(guessId, guess);
    if (!mounted) return;
    _replaceSend(updated);
  }

  Future<void> _handleDeleteGuess(String guessId) async {
    final updated = await GameService.instance.deleteEmojiGuess(guessId);
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

  /// Voir demande utilisateur : "es-ce possible de mettre des exemples de
  /// tout type" — un exemple par grande catégorie de story (film, humeur,
  /// nourriture, sortie, activité, animal), pour inspirer sans imposer un
  /// genre en particulier. Contenu statique (pas de source admin pour ça
  /// pour l'instant), ouvert via l'icône ajoutée en haut à droite.
  static const _emojiStoryExamples = [
    (category: '🎬 Film ou série', emojis: '🦁👑🌅', meaning: 'Le Roi Lion'),
    (category: '😌 Humeur du moment', emojis: '😴🛌☕', meaning: 'Je suis crevé(e) ce matin'),
    (category: '🍽️ Nourriture', emojis: '🍝🧄🫒', meaning: 'Spaghetti à l\'ail'),
    (category: '📍 Sortie ou lieu', emojis: '🏖️🍹☀️', meaning: 'Vacances à la plage'),
    (category: '⚽ Activité', emojis: '⚽👟🏃', meaning: 'Partie de foot entre potes'),
    (category: '🐾 Animal', emojis: '🐱😻🧶', meaning: 'Mon chat joue avec une pelote'),
  ];

  void _showEmojiStoryExamples() {
    final theme = ThemeScope.paletteOf(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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
                'Exemples d\'émoji-récits',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: theme.textOnBackground),
              ),
              const SizedBox(height: 4),
              Text(
                'Un peu d\'inspiration, quel que soit le type de story',
                style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
              ),
              const SizedBox(height: 16),
              for (final example in _emojiStoryExamples)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              example.category,
                              style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: theme.textOnBackgroundMuted),
                            ),
                            const SizedBox(height: 2),
                            Text(example.emojis, style: const TextStyle(fontSize: 22)),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_rounded, size: 16, color: theme.textOnBackgroundMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: Text(
                          example.meaning,
                          style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: theme.textOnBackground),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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
        appBar: _selectionMode
            ? _buildSelectionAppBar(theme)
            : AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                systemOverlayStyle: theme.statusBarOverlayStyle,
                foregroundColor: theme.textOnBackground,
                title: Text(
                  widget.game.nameFor(LocaleScope.of(context).current.code),
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    color: theme.textOnBackground,
                  ),
                ),
                actions: [
                  if (_matchStats != null && _matchStats!.totalResolved > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Center(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => showEmojiStoryMatchScoreboard(
                            context,
                            theme: theme,
                            stats: _matchStats!,
                            myUserId: widget.user.id,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: theme.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: theme.primary.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  '🔮',
                                  style: TextStyle(fontSize: 12),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '${_matchStats!.totalFirstTry}/${_matchStats!.totalResolved}',
                                  style: GoogleFonts.nunito(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: theme.textOnBackground,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 14,
                                  color: theme.textOnBackgroundMuted,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.lightbulb_outline_rounded),
                    tooltip: 'Exemples',
                    onPressed: _showEmojiStoryExamples,
                  ),
                ],
              ),
        body: ThemedBackground(
          child: SafeArea(
            child: Column(
              children: [
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
                ] else if (!_keyboardOpen) ...[
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

    return ListView.builder(
      reverse: true,
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: _sends.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _sends.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final send = _sends[index];
        // Clé stable par story (voir son id, jamais l'index) : sans ça, une
        // nouvelle story insérée en tête décale les positions et Flutter
        // réutilise par erreur l'état local (devinette en cours de saisie,
        // etc.) d'UNE bulle pour une AUTRE story.
        return _StoryBubble(
          key: ValueKey(send.id),
          theme: theme,
          send: send,
          myUserId: widget.user.id,
          onGuess: (guess) => _handleGuess(send, guess),
          onVerdict: ({required correct, retry, reveal}) => _handleVerdict(
            send,
            correct: correct,
            retry: retry,
            reveal: reveal,
          ),
          onEditGuess: _handleEditGuess,
          onDeleteGuess: _handleDeleteGuess,
          onGuessFieldFocusChanged: (focused) =>
              _setGuessFieldFocus(send.id, focused),
          selectionMode: _selectionMode,
          selected: _selectedIds.contains(send.id),
          onToggleSelect: () => _toggleSelect(send.id),
          editController: _editingSendId == send.id ? _editController : null,
          isFirstMessage: !_hasMore && index == _sends.length - 1,
          partnerName: partnerName,
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
  final Future<void> Function(String guess) onGuess;
  final Future<void> Function({
    required bool correct,
    bool? retry,
    String? reveal,
  })
  onVerdict;
  // Modifier/supprimer MA PROPRE devinette tant qu'elle attend un verdict
  // (voir _buildPendingGuessBlock) — jamais celle du/de la partenaire.
  final Future<void> Function(String guessId, String guess) onEditGuess;
  final Future<void> Function(String guessId) onDeleteGuess;
  // Un champ classique de CETTE bulle (deviner/révéler/corriger une
  // devinette) a le focus ou vient de le perdre — remonté au parent pour
  // cacher la barre de composition normale pendant ce temps (voir
  // _EmojiStorySessionScreenState._keyboardOpen).
  final ValueChanged<bool> onGuessFieldFocusChanged;
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
  // Vrai UNIQUEMENT pour le tout premier message de la discussion entière
  // (le plus ancien, une fois tout l'historique chargé — voir
  // _EmojiStorySessionScreenState._buildList) — affiche une invitation à
  // jouer en citation au-dessus du contenu (voir demande utilisateur),
  // jamais sur les messages suivants.
  final bool isFirstMessage;
  final String partnerName;

  const _StoryBubble({
    super.key,
    required this.theme,
    required this.send,
    required this.myUserId,
    required this.onGuess,
    required this.onVerdict,
    required this.onEditGuess,
    required this.onDeleteGuess,
    required this.onGuessFieldFocusChanged,
    required this.selectionMode,
    required this.selected,
    required this.onToggleSelect,
    required this.editController,
    required this.isFirstMessage,
    required this.partnerName,
  });

  @override
  State<_StoryBubble> createState() => _StoryBubbleState();
}

class _StoryBubbleState extends State<_StoryBubble> {
  final _guessController = TextEditingController();
  final _revealController = TextEditingController();
  bool _guessing = false;
  bool _closingWithReveal = false;
  bool _submitting = false;
  // Quel bouton précis de verdict est en cours d'envoi (voir
  // _submitVerdict) — _submitting seul désactive bien les 3 boutons
  // pendant l'envoi, mais ne dit pas LEQUEL afficher en chargement ;
  // sans lui, taper "Retenter" faisait tourner le loader sur "Juste"
  // (constaté en réel, voir demande utilisateur).
  String? _verdictAction;

  // Une des 3 phrases côté expéditeur·rice tirée une seule fois à la
  // construction de CETTE bulle (jamais re-tirée au rebuild, sinon elle
  // clignoterait) — voir demande utilisateur, même principe que les
  // sous-titres du battement de cœur.
  late final int _senderPhraseIndex = math.Random().nextInt(3) + 1;

  // Modifier/supprimer MA propre devinette en attente de verdict (voir
  // _buildPendingGuessBlock) — état purement local à cette bulle, pas de
  // clavier spécial ici (devinette = clavier classique, voir _guessing) ni
  // de coordination avec le parent, contrairement à l'édition de la story.
  bool _guessMenuOpen = false;
  bool _editingGuess = false;
  bool _confirmingGuessDelete = false;
  TextEditingController? _guessEditController;
  bool _guessActionSubmitting = false;

  // Tout champ classique de CETTE bulle (deviner/révéler/corriger une
  // devinette) prévient le parent quand il prend/perd le focus, pour qu'il
  // cache la barre de composition normale pendant ce temps (voir
  // widget.onGuessFieldFocusChanged) — plus fiable qu'un simple
  // MediaQuery.viewInsets, constaté en réel.
  late final _guessFocusNode = FocusNode()..addListener(_notifyFocus);
  late final _revealFocusNode = FocusNode()..addListener(_notifyFocus);
  FocusNode? _guessEditFocusNode;

  void _notifyFocus() {
    final focused =
        _guessFocusNode.hasFocus ||
        _revealFocusNode.hasFocus ||
        (_guessEditFocusNode?.hasFocus ?? false);
    widget.onGuessFieldFocusChanged(focused);
  }

  // Utilisé quand ON SAIT que plus aucun champ ne doit rester actif (juste
  // après un envoi réussi) : unfocus() explicite d'abord, PUIS notification
  // directe à `false`, plutôt que de relire `.hasFocus` juste après le
  // setState qui masque le champ (voir _submitGuess/_submitVerdict) — le
  // détachement du FocusNode par le framework se fait sur la frame
  // suivante, donc relire `.hasFocus` à cet instant précis pouvait encore
  // renvoyer `true` et reconfirmer par erreur le champ comme "toujours
  // focus", laissant la barre de composition normale masquée en
  // permanence (voir widget.onGuessFieldFocusChanged).
  void _clearGuessFocus() {
    _guessFocusNode.unfocus();
    _revealFocusNode.unfocus();
    _guessEditFocusNode?.unfocus();
    widget.onGuessFieldFocusChanged(false);
  }

  @override
  void dispose() {
    // Filet de sécurité (même raison que _submitGuess/_submitVerdict) : si
    // cette bulle disparaît (défilement, recyclage de la liste) pendant
    // qu'un de ses champs a encore le focus, le parent ne doit pas rester
    // bloqué à croire un champ ouvert.
    widget.onGuessFieldFocusChanged(false);
    _guessController.dispose();
    _revealController.dispose();
    _guessEditController?.dispose();
    _guessFocusNode.dispose();
    _revealFocusNode.dispose();
    _guessEditFocusNode?.dispose();
    super.dispose();
  }

  void _toggleGuessMenu() {
    setState(() {
      _guessMenuOpen = !_guessMenuOpen;
      _editingGuess = false;
      _confirmingGuessDelete = false;
    });
  }

  void _startEditGuess(String currentText) {
    setState(() {
      _editingGuess = true;
      _guessMenuOpen = false;
      _guessEditController = TextEditingController(text: currentText);
      _guessEditFocusNode = FocusNode()..addListener(_notifyFocus);
    });
  }

  void _cancelEditGuess() {
    final old = _guessEditController;
    final oldNode = _guessEditFocusNode;
    setState(() {
      _editingGuess = false;
      _guessEditController = null;
      _guessEditFocusNode = null;
    });
    old?.dispose();
    oldNode?.dispose();
    _notifyFocus();
  }

  Future<void> _saveEditGuess(String guessId) async {
    final text = _guessEditController?.text.trim() ?? '';
    if (text.isEmpty || _guessActionSubmitting) return;
    setState(() => _guessActionSubmitting = true);
    try {
      await widget.onEditGuess(guessId, text);
      if (!mounted) return;
      final old = _guessEditController;
      final oldNode = _guessEditFocusNode;
      setState(() {
        _editingGuess = false;
        _guessEditController = null;
        _guessEditFocusNode = null;
      });
      old?.dispose();
      oldNode?.dispose();
      _notifyFocus();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _guessActionSubmitting = false);
    }
  }

  void _startConfirmDeleteGuess() {
    setState(() {
      _confirmingGuessDelete = true;
      _guessMenuOpen = false;
    });
  }

  void _cancelConfirmDeleteGuess() {
    setState(() => _confirmingGuessDelete = false);
  }

  Future<void> _confirmDeleteGuess(String guessId) async {
    if (_guessActionSubmitting) return;
    setState(() => _guessActionSubmitting = true);
    try {
      await widget.onDeleteGuess(guessId);
      // Le Send remplacé par le parent redonne needsGuess = true — cette
      // bulle se reconstruit toute seule dans son état par défaut.
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() {
          _guessActionSubmitting = false;
          _confirmingGuessDelete = false;
        });
      }
    }
  }

  Future<void> _submitGuess() async {
    final text = _guessController.text.trim();
    if (text.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onGuess(text);
      if (!mounted) return;
      _guessController.clear();
      setState(() => _guessing = false);
      _clearGuessFocus();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitVerdict({
    required bool correct,
    bool? retry,
    String? reveal,
  }) async {
    if (_submitting) return;
    final action = reveal != null
        ? 'reveal'
        : (retry == true ? 'retry' : 'correct');
    setState(() {
      _submitting = true;
      _verdictAction = action;
    });
    try {
      await widget.onVerdict(correct: correct, retry: retry, reveal: reveal);
      if (!mounted) return;
      setState(() {
        _closingWithReveal = false;
        _revealController.clear();
      });
      _clearGuessFocus();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _verdictAction = null;
        });
      }
    }
  }

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

    if (story.needsVerdict) {
      blocks.add(
        _buildPendingGuessBlock(
          theme,
          story,
          guesserId,
          guesserName,
          mine,
          onColor,
          mutedColor,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.isFirstMessage)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _replyBlock(
              bubbleMine: mine,
              label: LocaleScope.of(context).t('emoji_story_invite_label'),
              content: Text(
                LocaleScope.of(context).t(
                  mine
                      ? 'emoji_story_invite_sender_$_senderPhraseIndex'
                      : 'emoji_story_invite_recipient',
                  {'name': widget.partnerName},
                ),
                style: TextStyle(color: onColor),
              ),
            ),
          ),
        Text(
          story.emojis,
          style: const TextStyle(fontSize: 26, height: 1.3),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        ...blocks,
        _buildStatusArea(
          theme,
          story,
          guesserId,
          composerId,
          mine,
          onColor,
          mutedColor,
          guesserName,
          composerName,
        ),
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

  /// La devinette en attente de verdict — tapable UNIQUEMENT si c'est MA
  /// propre devinette (voir widget.onEditGuess/onDeleteGuess), pour
  /// afficher Modifier/Supprimer sans passer par un menu contextuel modal
  /// (voir la note de _showOptions retirée plus haut — évite la même classe
  /// de plantage) : tout se passe en place, dans la bulle.
  Widget _buildPendingGuessBlock(
    ThemePalette theme,
    EmojiStorySend story,
    String guesserId,
    String guesserName,
    bool mine,
    Color onColor,
    Color mutedColor,
  ) {
    final pending = story.latestGuess!;
    final isMyGuess = guesserId == widget.myUserId;
    final t = LocaleScope.of(context).t;

    Widget body;
    if (isMyGuess && _editingGuess) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _guessEditController,
            focusNode: _guessEditFocusNode,
            autofocus: true,
            maxLines: 3,
            style: TextStyle(fontSize: 13, color: onColor),
            cursorColor: onColor,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: onColor.withValues(alpha: 0.08),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _SmallActionButton(
                  label: t('common_cancel'),
                  color: mutedColor,
                  filled: false,
                  small: true,
                  onTap: _guessActionSubmitting ? null : _cancelEditGuess,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _SmallActionButton(
                  label: t('common_save'),
                  color: theme.primary,
                  filled: true,
                  small: true,
                  loading: _guessActionSubmitting,
                  onTap: _guessActionSubmitting
                      ? null
                      : () => _saveEditGuess(pending.id),
                ),
              ),
            ],
          ),
        ],
      );
    } else if (isMyGuess && _confirmingGuessDelete) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_empty_rounded, size: 14, color: mutedColor),
              const SizedBox(width: 5),
              Flexible(child: Text(pending.guess)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            t('emoji_story_delete_guess_confirm'),
            style: TextStyle(fontSize: 11.5, color: mutedColor),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _SmallActionButton(
                  label: t('common_cancel'),
                  color: mutedColor,
                  filled: false,
                  small: true,
                  onTap: _guessActionSubmitting
                      ? null
                      : _cancelConfirmDeleteGuess,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _SmallActionButton(
                  label: t('common_confirm'),
                  color: Colors.redAccent,
                  filled: true,
                  small: true,
                  loading: _guessActionSubmitting,
                  onTap: _guessActionSubmitting
                      ? null
                      : () => _confirmDeleteGuess(pending.id),
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_empty_rounded, size: 14, color: mutedColor),
              const SizedBox(width: 5),
              Flexible(child: Text(pending.guess)),
            ],
          ),
          if (isMyGuess && _guessMenuOpen) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _SmallActionButton(
                    label: t('common_edit'),
                    icon: Icons.edit_rounded,
                    // theme.primary se fond dans le dégradé rose→violet
                    // d'une bulle "mine" (voir _buildBubbleShell) — onColor
                    // (blanc côté "mine") reste lisible dans les deux cas.
                    color: mine ? onColor : theme.primary,
                    filled: false,
                    small: true,
                    onTap: () => _startEditGuess(pending.guess),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _SmallActionButton(
                    label: t('common_delete'),
                    icon: Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                    filled: false,
                    small: true,
                    onTap: _startConfirmDeleteGuess,
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    }

    final block = _replyBlock(
      bubbleMine: mine,
      label: LocaleScope.of(
        context,
      ).t('emoji_story_guess_label', {'name': guesserName}),
      content: body,
    );
    // Appui long (pas un simple tap, façon WhatsApp) pour ouvrir le menu
    // Modifier/Supprimer — désactivé pendant l'édition/la confirmation (les
    // boutons internes gèrent déjà tout) et pour la devinette du/de la
    // partenaire (rien à modifier ici).
    if (!isMyGuess || _editingGuess || _confirmingGuessDelete) return block;
    return GestureDetector(onLongPress: _toggleGuessMenu, child: block);
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
            child: child,
          ),
        ),
      ),
    );
  }

  /// Ce qui reste à faire pour CETTE story, sous la citation de la
  /// dernière devinette — verdict à rendre, invitation/formulaire à
  /// deviner, résultat final, ou simple attente de l'autre.
  Widget _buildStatusArea(
    ThemePalette theme,
    EmojiStorySend story,
    String guesserId,
    String composerId,
    bool mine,
    Color onColor,
    Color mutedColor,
    String guesserName,
    String composerName,
  ) {
    final myTurnToVerdict = story.needsVerdict && mine;
    final myTurnToGuess = story.needsGuess && guesserId == widget.myUserId;
    final t = LocaleScope.of(context).t;

    if (story.isResolved) {
      // Le verdict (trouvé/raté) est déjà visible dans la citation de la
      // devinette elle-même (voir emoji_story_guess_correct/_missed) —
      // ce badge supplémentaire était redondant.
      return const SizedBox.shrink();
    }

    if (myTurnToVerdict) {
      if (_closingWithReveal) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _revealController,
              focusNode: _revealFocusNode,
              maxLines: 2,
              autofocus: true,
              style: GoogleFonts.nunito(fontSize: 13, color: onColor),
              decoration: InputDecoration(
                filled: true,
                fillColor: mine
                    ? onColor.withValues(alpha: 0.12)
                    : theme.background,
                hintText: t('emoji_story_reveal_hint'),
                hintStyle: GoogleFonts.nunito(
                  fontSize: 12.5,
                  color: mutedColor,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _SmallActionButton(
                    label: t('emoji_story_back_button'),
                    color: mutedColor,
                    filled: false,
                    onTap: _submitting
                        ? null
                        : () => setState(() => _closingWithReveal = false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SmallActionButton(
                    label: t('emoji_story_reveal_button'),
                    color: theme.primary,
                    filled: true,
                    loading: _submitting && _verdictAction == 'reveal',
                    onTap: _submitting
                        ? null
                        : () => _submitVerdict(
                            correct: false,
                            retry: false,
                            reveal: _revealController.text.trim(),
                          ),
                  ),
                ),
              ],
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _SmallActionButton(
                  label: t('emoji_story_verdict_correct_button'),
                  color: Colors.green,
                  filled: true,
                  loading: _submitting && _verdictAction == 'correct',
                  onTap: _submitting
                      ? null
                      : () => _submitVerdict(correct: true),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _SmallActionButton(
                  label: t('emoji_story_verdict_retry_button'),
                  // theme.primary se fond dans le dégradé rose→violet d'une
                  // bulle "mine" (voir _buildBubbleShell) — onColor (blanc
                  // côté "mine") reste lisible dans les deux cas.
                  color: mine ? onColor : theme.primary,
                  filled: false,
                  loading: _submitting && _verdictAction == 'retry',
                  onTap: _submitting
                      ? null
                      : () => _submitVerdict(correct: false, retry: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _SmallActionButton(
            label: t('emoji_story_finish_reveal_button'),
            color: mutedColor,
            filled: false,
            small: true,
            onTap: _submitting
                ? null
                : () => setState(() => _closingWithReveal = true),
          ),
        ],
      );
    }

    if (story.needsVerdict) {
      // C'est à l'AUTRE de rendre son verdict — pas de statut lu/pas lu
      // disponible pour cette devinette précise (contrairement au Send
      // racine de la story, voir plus bas), juste l'indicateur d'attente.
      // Colonne plutôt que Row : le texte peut être long (prénom compris)
      // et doit pouvoir revenir à la ligne plutôt que d'être coupé — les
      // points d'attente passent alors sur leur propre ligne en dessous.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            t('emoji_story_status_waiting_verdict', {'name': composerName}),
            style: GoogleFonts.nunito(
              fontSize: 12.5,
              fontStyle: FontStyle.italic,
              color: mutedColor,
            ),
          ),
          const SizedBox(height: 4),
          WaitingDots(color: mutedColor),
        ],
      );
    }

    if (myTurnToGuess) {
      if (!_guessing) {
        return _SmallActionButton(
          label: story.guesses.isNotEmpty
              ? t('emoji_story_guess_again_button')
              : t('emoji_story_guess_button'),
          icon: Icons.psychology_alt_rounded,
          color: theme.primary,
          filled: true,
          onTap: () => setState(() => _guessing = true),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _guessController,
            focusNode: _guessFocusNode,
            autofocus: true,
            maxLines: 3,
            style: GoogleFonts.nunito(fontSize: 13, color: onColor),
            decoration: InputDecoration(
              filled: true,
              fillColor: mine
                  ? onColor.withValues(alpha: 0.12)
                  : theme.background,
              hintText: t('emoji_story_guess_hint'),
              hintStyle: GoogleFonts.nunito(fontSize: 12.5, color: mutedColor),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _SmallActionButton(
            label: t('emoji_story_send_guess_button'),
            color: theme.primary,
            filled: true,
            loading: _submitting,
            onTap: _submitting ? null : _submitGuess,
          ),
        ],
      );
    }

    // needsGuess côté de qui a composé : c'est à l'AUTRE de deviner — le
    // tick reflète si CETTE story (le Send racine) a déjà été vue par
    // guesserName, comme dans les fils À nous deux/Vérité ou Défi.
    final tick = sendTickFor(widget.send);
    // Colonne plutôt que Row, même raison que ci-dessus : le texte (avec le
    // prénom) revient à la ligne au lieu d'être coupé, points et coche sur
    // leur propre ligne en dessous.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.send.emojiStory?.guesses.isNotEmpty ?? false
              ? t('emoji_story_waiting_guess_again', {'name': guesserName})
              : t('emoji_story_status_waiting_guess', {'name': guesserName}),
          style: GoogleFonts.nunito(
            fontSize: 12.5,
            fontStyle: FontStyle.italic,
            color: mutedColor,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            WaitingDots(color: mutedColor),
            const SizedBox(width: 6),
            SendTickIcon(tick: tick, color: mutedColor),
          ],
        ),
      ],
    );
  }
}

/// Petit bouton compact réutilisé partout dans _StoryBubble (juste/retenter/
/// terminer/deviner/envoyer) — pleine couleur ou juste contourné, avec un
/// mini spinner intégré pendant l'envoi.
class _SmallActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final bool filled;
  final bool small;
  final bool loading;
  final VoidCallback? onTap;

  const _SmallActionButton({
    required this.label,
    this.icon,
    required this.color,
    required this.filled,
    this.small = false,
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
            padding: EdgeInsets.symmetric(
              horizontal: 10,
              vertical: small ? 6 : 9,
            ),
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
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 14, color: fg),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        label,
                        style: GoogleFonts.nunito(
                          fontSize: small ? 11 : 12.5,
                          fontWeight: FontWeight.w700,
                          color: fg,
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

/// Trois petits points qui rebondissent l'un après l'autre — purement
/// décoratif (ce n'est PAS une détection de frappe en direct côté
/// partenaire, juste un signal visuel "c'est en attente", façon indicateur
/// de saisie des messageries classiques).
