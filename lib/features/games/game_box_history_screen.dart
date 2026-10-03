import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/last_seen_label.dart';
import '../../core/api_client.dart';
import '../../core/app_router.dart';
import '../../core/realtime_client.dart';
import '../../l10n/locale_scope.dart';
import '../../models/app_user.dart';
import '../../models/game.dart';
import '../../models/game_box.dart';
import '../../models/game_card_send.dart';
import '../../models/replies_page.dart';
import '../../models/send.dart';
import '../../models/send_reaction.dart';
import '../../models/slide.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/coin_icon.dart';
import '../../widgets/composer_actions.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/send_status_tick.dart';
import '../../widgets/waiting_dots.dart';
import '../box/box_service.dart';
import '../content/content_service.dart';
import '../content/packs_screen.dart';
import '../content/widgets/heartbeat_card.dart';
import '../content/widgets/heartbeat_reply_modal.dart';
import '../content/widgets/pack_reply_modal.dart';
import '../content/widgets/slide_pack_viewer.dart';
import '../shop/subscription_status_notifier.dart';
import '../shop/wallet_balance_notifier.dart';
import 'game_box_session_screen.dart';
import 'game_card_inbox_service.dart';
import 'game_service.dart';
import 'truth_or_dare_session_screen.dart';
import 'widgets/blind_poll_match_scoreboard.dart';
import 'widgets/game_box_icon.dart';
import 'widgets/game_card_widgets.dart';

const _weekdayKeys = [
  'weekday_monday',
  'weekday_tuesday',
  'weekday_wednesday',
  'weekday_thursday',
  'weekday_friday',
  'weekday_saturday',
  'weekday_sunday',
];
const _monthKeys = [
  'month_january',
  'month_february',
  'month_march',
  'month_april',
  'month_may',
  'month_june',
  'month_july',
  'month_august',
  'month_september',
  'month_october',
  'month_november',
  'month_december',
];

/// Même étiquette de séparateur de date que le Carnet de bord (voir
/// TimelineScreen._dateHeaderFor) — même vocabulaire ("Aujourd'hui", "Hier"...)
/// pour que tous les écrans de discussion se lisent comme un seul système.
/// Partagée entre GameBoxHistoryScreen (liste des discussions) et
/// GameCardThreadScreen (fil d'UNE discussion, voir _ThreadDateHeader) —
/// avant, seule la liste l'avait, jamais le fil lui-même (voir demande
/// utilisateur : "ça n'apparaît pas" en comparant à une capture WhatsApp).
String dateHeaderLabel(BuildContext context, DateTime dt) {
  final t = LocaleScope.of(context).t;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(dt.year, dt.month, dt.day);
  final diff = today.difference(date).inDays;
  if (diff == 0) return t('date_today');
  if (diff == 1) return t('date_yesterday');
  if (diff < 7) return t(_weekdayKeys[dt.weekday - 1]);
  return '${dt.day} ${t(_monthKeys[dt.month - 1])} ${dt.year}';
}

/// Liste des cartes déjà jouées d'une boîte (voir GameCardController::history)
/// — ouverte depuis GameArchiveTray dans l'éventail de cartes. Chaque carte
/// envoyée a sa PROPRE petite discussion séparée (voir GameCardThreadScreen),
/// pas un flux unique mélangeant toutes les cartes : cette liste n'affiche
/// donc qu'un aperçu par carte, à ouvrir individuellement. Remplace l'ancien
/// affichage des cartes-questions dans le Carnet de bord général (retiré
/// côté backend, voir SendController::index).
class GameBoxHistoryScreen extends StatefulWidget {
  final Game game;
  final GameBox box;
  final AppUser user;

  const GameBoxHistoryScreen({super.key, required this.game, required this.box, required this.user});

  @override
  State<GameBoxHistoryScreen> createState() => _GameBoxHistoryScreenState();
}

class _GameBoxHistoryScreenState extends State<GameBoxHistoryScreen> {
  List<Send>? _sends;
  bool _loading = true;
  bool _error = false;
  // Plus anciennes que la première page (20 par défaut, voir
  // GameCardController::history) restant à charger en scrollant — un tirer-
  // pour-rafraîchir/rouvrir ne recharge toujours que cette première page,
  // remonter plus loin nécessite déjà une connexion (voir _loadMore).
  bool _hasMore = false;
  bool _loadingMore = false;
  final _scrollController = ScrollController();

  String? _subscribedBoxId;

  @override
  void initState() {
    super.initState();
    _loadCachedThenRefresh();
    _initRealtime();
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      // Approche du bas de la liste (les plus anciennes, vu que c'est une
      // liste "plus récente en premier") : charge la page suivante avant
      // d'y arriver vraiment.
      if (_hasMore && !_loadingMore && position.pixels >= position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    if (_subscribedBoxId != null) {
      RealtimeClient.instance.unsubscribeFromBox(_subscribedBoxId!, onEvent: _onRealtimeEvent);
    }
    super.dispose();
  }

  /// Affiche la dernière page connue tout de suite (voir
  /// GameService.cachedBoxHistory), avant même la réponse réseau, comme
  /// TimelineScreen/SlideDetailScreen pour le Carnet de bord.
  Future<void> _loadCachedThenRefresh() async {
    final cached = await GameService.instance.cachedBoxHistory(widget.box.id);
    if (cached != null && mounted) {
      setState(() {
        _sends = cached.items;
        _hasMore = cached.hasMore;
        _loading = false;
      });
    }
    await _load();
  }

  Future<void> _load() async {
    try {
      final page = await GameService.instance.fetchBoxHistory(widget.game.id, widget.box.id);
      if (!mounted) return;
      setState(() {
        // Plus récente en premier — une liste de conversations se lit du
        // haut vers le bas, contrairement au fil unique d'une conversation.
        _sends = page.items;
        _hasMore = page.hasMore;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Ne bascule en erreur que si on n'a vraiment rien à montrer (ni
        // cache, ni fetch précédent) — sinon la liste déjà affichée reste,
        // le prochain rafraîchissement réessaiera.
        if (_sends == null) _error = true;
      });
    }
  }

  /// Discussions plus anciennes que celles déjà affichées — déclenché en
  /// approchant le bas de la liste (voir le ScrollController dans
  /// initState). Ajoutées en FIN de [_sends] (les plus anciennes),
  /// jamais mises en cache (voir GameService.fetchBoxHistory : seule la
  /// première page l'est).
  Future<void> _loadMore() async {
    final sends = _sends;
    if (!_hasMore || _loadingMore || sends == null || sends.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await GameService.instance.fetchBoxHistory(widget.game.id, widget.box.id, beforeId: sends.last.id);
      if (!mounted) return;
      setState(() {
        _sends = [...sends, ...page.items];
        _hasMore = page.hasMore;
      });
    } catch (_) {
      // best effort — l'utilisateur pourra réessayer en re-scrollant.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Nouvelle carte-question envoyée dans cette boîte pendant que la liste
  /// est ouverte — apparaît en direct sans attendre un rafraîchissement
  /// manuel (même canal que GameCardThreadScreen/GameCardBubble).
  Future<void> _initRealtime() async {
    final coupleBoxId = BoxService.instance.currentBox?.id;
    if (coupleBoxId == null) return;
    _subscribedBoxId = coupleBoxId;
    try {
      await RealtimeClient.instance.subscribeToBox(coupleBoxId, onEvent: _onRealtimeEvent);
    } catch (_) {
      // Best effort — la liste reste utilisable, juste sans mise à jour
      // immédiate des nouvelles cartes.
    }
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    // Coches envoyé/reçu/lu du DERNIER message de chaque discussion (voir
    // GameHistoryRow.tick) — sans ça, elles ne se mettaient à jour qu'au
    // prochain rechargement complet de la liste, jamais en direct pendant
    // qu'elle reste ouverte (voir demande utilisateur, même trou déjà
    // corrigé sur TimelineScreen).
    if (event.event == 'SendSeen') {
      final sendId = event.data?['send_id'] as String?;
      if (sendId == null) return;
      final seenAtStr = event.data?['seen_at'] as String?;
      _applySeen(sendId, seenAtStr != null ? DateTime.parse(seenAtStr) : DateTime.now());
      return;
    }
    if (event.event == 'SendDelivered') {
      final sendIds = (event.data?['send_ids'] as List?)?.map((e) => e as String).toList();
      if (sendIds == null || sendIds.isEmpty) return;
      final deliveredAtStr = event.data?['delivered_at'] as String?;
      _applyDelivered(sendIds, deliveredAtStr != null ? DateTime.parse(deliveredAtStr) : DateTime.now());
      return;
    }
    // Réponse/devinette/verdict sur une carte déjà listée ici (voir
    // GameCardController::answer/guess/verdict, réservé aux jeux
    // `session_type = 'quiz'`) — met à jour son aperçu en place, comme les
    // réponses au fil ci-dessous.
    if (event.event == 'GameCardUpdated') {
      final sendJson = event.data?['send'] as Map<String, dynamic>?;
      if (sendJson == null) return;
      final updated = Send.fromJson(sendJson);
      if (!mounted) return;
      final current = _sends ?? [];
      final index = current.indexWhere((s) => s.id == updated.id);
      if (index == -1) return;
      final refreshed = List<Send>.of(current);
      refreshed[index] = updated;
      setState(() => _sends = refreshed);
      return;
    }
    if (event.event != 'SendCreated') return;
    final sendJson = event.data?['send'] as Map<String, dynamic>?;
    if (sendJson == null) return;

    final send = Send.fromJson(sendJson);
    if (!mounted) return;
    final current = _sends ?? [];

    // Réponse à une discussion déjà listée ici (nouvelle carte envoyée via
    // "envoyer une autre carte", message texte/emoji...) : met à jour son
    // aperçu en direct (voir Send.lastMessage) au lieu de créer une
    // nouvelle entrée — quel que soit le type de CETTE réponse.
    if (send.replyToSendId != null) {
      final index = current.indexWhere((s) => s.id == send.replyToSendId);
      if (index == -1) return;
      final updated = List<Send>.of(current);
      updated[index] = updated[index].copyWith(latestReply: send);
      setState(() => _sends = updated);
      return;
    }

    // Seules les cartes RACINES de CETTE boîte rejoignent la liste comme
    // nouvelle entrée — même filtre que GameCardController::history côté
    // backend.
    if (send.sendableType != 'game_card') return;
    if (send.gameCard?.gameBoxId != widget.box.id) return;
    if (current.any((s) => s.id == send.id)) return;
    setState(() => _sends = [send, ...current]);
  }

  /// Met à jour la coche "lu" du DERNIER message de la discussion concernée
  /// (voir Send.lastMessage = latestReply ?? this) — le message vu peut être
  /// aussi bien la carte racine qu'une réponse plus récente.
  void _applySeen(String sendId, DateTime seenAt) {
    if (!mounted) return;
    final current = _sends ?? [];
    final index = current.indexWhere((s) => s.id == sendId || s.latestReply?.id == sendId);
    if (index == -1) return;
    final updated = List<Send>.of(current);
    final target = updated[index];
    updated[index] = target.latestReply?.id == sendId
        ? target.copyWith(latestReply: target.latestReply!.copyWith(status: 'seen', seenAt: seenAt))
        : target.copyWith(status: 'seen', seenAt: seenAt);
    setState(() => _sends = updated);
  }

  void _applyDelivered(List<String> sendIds, DateTime deliveredAt) {
    if (!mounted) return;
    final current = _sends ?? [];
    var changed = false;
    final updated = current.map((s) {
      if (s.latestReply != null && sendIds.contains(s.latestReply!.id) && s.latestReply!.status == 'sent') {
        changed = true;
        return s.copyWith(latestReply: s.latestReply!.copyWith(status: 'delivered', deliveredAt: deliveredAt));
      }
      if (s.latestReply == null && sendIds.contains(s.id) && s.status == 'sent') {
        changed = true;
        return s.copyWith(status: 'delivered', deliveredAt: deliveredAt);
      }
      return s;
    }).toList();
    if (changed) setState(() => _sends = updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(
          widget.box.titleFor(LocaleScope.of(context).current.code),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
      ),
      body: ThemedBackground(
        child: SafeArea(child: _buildBody(theme)),
      ),
    );
  }

  /// Voir dateHeaderLabel (fonction partagée en tête de fichier).
  String _dateHeaderFor(DateTime dt) => dateHeaderLabel(context, dt);

  /// Même aplatissement en-têtes + éléments que TimelineScreen._groupByDate
  /// — les discussions d'une même date sont ainsi reliées par le même fil
  /// vertical fin entre leurs avatars (voir GameHistoryRow).
  List<_HistoryEntry> _groupByDate(List<Send> sends) {
    final entries = <_HistoryEntry>[];
    for (var i = 0; i < sends.length; i++) {
      final send = sends[i];
      final header = _dateHeaderFor(send.createdAt);
      final prevHeader = i == 0 ? null : _dateHeaderFor(sends[i - 1].createdAt);
      final nextHeader = i == sends.length - 1 ? null : _dateHeaderFor(sends[i + 1].createdAt);
      final isFirstInGroup = header != prevHeader;
      final isLastInGroup = header != nextHeader;
      if (isFirstInGroup) entries.add(_HistoryEntry.header(header));
      entries.add(_HistoryEntry.send(send, isFirstInGroup: isFirstInGroup, isLastInGroup: isLastInGroup));
    }
    return entries;
  }

  Widget _buildBody(ThemePalette theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error) {
      return Center(
        child: EmptyState(
          icon: Icons.wifi_off_rounded,
          message: LocaleScope.of(context).t('game_history_load_error'),
        ),
      );
    }
    final sends = _sends ?? [];
    if (sends.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyState(
              icon: Icons.style_rounded,
              message: LocaleScope.of(context).t('game_history_empty'),
            ),
            // Cet écran est toujours ouvert depuis l'éventail de cartes
            // (voir la docstring de la classe) — "ouvrir l'éventail" est
            // donc simplement un retour en arrière, pas une nouvelle
            // navigation, l'éventail est déjà la page juste en dessous.
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(LocaleScope.of(context).t('game_history_open_fan')),
            ),
          ],
        ),
      );
    }

    final entries = _groupByDate(sends);
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      itemCount: entries.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == entries.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final entry = entries[index];
        if (entry.isHeader) {
          return GameHistoryDateHeader(label: entry.header!, theme: theme);
        }

        final send = entry.send!;
        final card = send.gameCard;
        if (card == null) return const SizedBox.shrink();

        // Le DERNIER message de cette discussion (voir Send.lastMessage) —
        // pas la carte d'ouverture figée — pour que la liste ressemble à
        // une vraie liste de conversations : aperçu, auteur et horodatage
        // reflètent toujours le tout dernier échange.
        final lastMessage = send.lastMessage;
        final isMine = lastMessage.senderId == widget.user.id;
        final senderName = lastMessage.sender?.prenom ?? lastMessage.sender?.name ?? LocaleScope.of(context).t('game_partner_name_fallback');

        return GameHistoryRow(
          theme: theme,
          send: send,
          isFirstInGroup: entry.isFirstInGroup,
          isLastInGroup: entry.isLastInGroup,
          questionText: lastMessage.shortPreview(LocaleScope.of(context).current.code),
          subtitle: LocaleScope.of(context).t(
            'game_sent_by',
            {'sender': isMine ? LocaleScope.of(context).t('game_sent_by_you') : senderName},
          ),
          time: _formattedTime(lastMessage.createdAt),
          // Même système de coches que dans le fil (voir SendTickIcon),
          // basé sur le dernier message de la discussion — pas un statut
          // "répondu au jeu" (voir demande utilisateur : ce symbole doit
          // suivre "les mêmes conditions que ce qui est défini à
          // l'intérieur d'une discussion"). Comme dans le fil, jamais
          // affiché sur un message REÇU (voir SendTickIcon, "jamais sur
          // celles reçues").
          tick: isMine ? sendTickFor(lastMessage) : null,
          // Le dernier message m'a été envoyé (pas par moi) ET je ne l'ai
          // pas encore ouvert — voir Send.isSeen, mis à jour dès l'ouverture
          // de la discussion (GameCardThreadScreen._markIncomingAsSeen).
          unread: lastMessage.recipientId == widget.user.id && !lastMessage.isSeen,
          // Ouvrir la discussion la marque comme vue côté serveur (voir
          // GameCardThreadScreen._markIncomingAsSeen) — sans ce await +
          // _refresh(), la pastille "non lu" restait affichée ici après
          // être revenu de la discussion, jusqu'au prochain tirer-pour-
          // rafraîchir manuel.
          onTap: () async {
            // Renforce le masquage fait dans GameCardThreadScreen.initState
            // (voir TimelineScreen._openSend pour le même principe côté
            // SlideDetailScreen) — appartient au call-site, pas seulement à
            // l'écran poussé.
            AppRouter.showGlobalNavBar.value = false;
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GameCardThreadScreen(
                  send: send,
                  user: widget.user,
                  game: widget.game,
                  box: widget.box,
                ),
              ),
            );
            AppRouter.showGlobalNavBar.value = true;
            _load();
          },
        );
      },
    );
  }

  String _formattedTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

/// Un élément de la liste aplatie : soit un en-tête de date, soit une
/// discussion avec sa position dans son groupe (première/dernière) — même
/// principe que TimelineScreen._TimelineEntry.
class _HistoryEntry {
  final String? header;
  final Send? send;
  final bool isFirstInGroup;
  final bool isLastInGroup;

  const _HistoryEntry.header(this.header) : send = null, isFirstInGroup = false, isLastInGroup = false;

  const _HistoryEntry.send(this.send, {required this.isFirstInGroup, required this.isLastInGroup}) : header = null;

  bool get isHeader => header != null;
}

/// Même étiquette que TimelineScreen._DateHeaderLabel.
class GameHistoryDateHeader extends StatelessWidget {
  final String label;
  final ThemePalette theme;

  const GameHistoryDateHeader({super.key, required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10, left: 4),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: theme.textOnBackgroundMuted),
      ),
    );
  }
}

/// Séparateur de date DANS un fil de discussion (voir GameCardThreadScreen)
/// — pastille centrée, pas l'étiquette alignée à gauche de GameHistoryDateHeader
/// (celle-ci sert à la LISTE des discussions, un contexte différent) : même
/// forme que la capture de référence WhatsApp fournie par l'utilisateur.
class _ThreadDateHeader extends StatelessWidget {
  final String label;
  final ThemePalette theme;

  const _ThreadDateHeader({required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 1))],
          ),
          child: Text(
            label,
            style: GoogleFonts.nunito(fontSize: 11.5, fontWeight: FontWeight.w700, color: theme.textOnBackgroundMuted),
          ),
        ),
      ),
    );
  }
}

/// Une ligne de la liste des discussions : l'avatar est relié au
/// précédent/suivant par un fil vertical fin quand ils partagent la même
/// date — même traitement que TimelineScreen._TimelineRow, pour que les
/// deux écrans se lisent comme un seul système visuel.
class GameHistoryRow extends StatelessWidget {
  final ThemePalette theme;
  final Send send;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final String questionText;
  final String subtitle;
  final String time;
  // Coche d'envoi/réception/lecture du DERNIER message (voir SendTickIcon)
  // — `null` quand ce dernier message a été reçu (pas envoyé par moi),
  // jamais affichée dans ce cas, même règle que dans le fil.
  final SendTick? tick;
  // Le DERNIER message de cette discussion (voir Send.lastMessage) m'a été
  // envoyé ET je ne l'ai pas encore vu (voir Send.isSeen) — même logique
  // que TimelineScreen/EmojiStoryHistoryScreen, pour un langage visuel
  // cohérent partout où l'app liste des discussions.
  final bool unread;
  final VoidCallback onTap;
  // Voir demande utilisateur : "dès que je clique pour ouvrir une
  // conversation, colorier légèrement pour montrer que l'on a cliqué en
  // attendant que ça s'ouvre" — vrai UNIQUEMENT sur la ligne tapée, le
  // temps de la résolution réseau (voir GameConversationsScreen._open).
  // `false` partout ailleurs (comportement inchangé, voir
  // GameBoxHistoryScreen qui ne le distingue pas par ligne).
  final bool opening;

  const GameHistoryRow({
    super.key,
    required this.theme,
    required this.send,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    required this.questionText,
    required this.subtitle,
    required this.time,
    required this.tick,
    required this.unread,
    required this.onTap,
    this.opening = false,
  });

  @override
  Widget build(BuildContext context) {
    final lineColor = (theme.isDark ? Colors.white : Colors.black).withValues(alpha: 0.14);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Expanded(child: isFirstInGroup ? const SizedBox() : Container(width: 2, color: lineColor)),
                CircleAvatar(
                  radius: 20,
                  backgroundColor: theme.primary.withValues(alpha: 0.15),
                  backgroundImage: send.sender?.avatar != null ? NetworkImage(send.sender!.avatar!) : null,
                  child: send.sender?.avatar == null
                      ? Text(send.sender != null && send.sender!.prenom.isNotEmpty ? send.sender!.prenom[0] : '?')
                      : null,
                ),
                Expanded(child: isLastInGroup ? const SizedBox() : Container(width: 2, color: lineColor)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Material(
                color: opening ? theme.primary.withValues(alpha: 0.1) : theme.surface,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: opening ? null : onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                questionText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.nunito(fontWeight: FontWeight.w800, fontSize: 14, color: theme.textOnBackground),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.nunito(
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                  letterSpacing: 0.2,
                                  color: theme.textOnBackgroundMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(time, style: GoogleFonts.nunito(fontSize: 11, color: theme.textOnBackgroundMuted)),
                            // Pastille "non lu" — même repère que
                            // TimelineScreen (Carnet de bord), pour que
                            // toutes les listes de discussions de l'app
                            // parlent le même langage visuel.
                            if (unread) ...[
                              const SizedBox(height: 6),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(shape: BoxShape.circle, color: theme.primary),
                              ),
                            ],
                            if (tick != null) ...[
                              const SizedBox(height: 6),
                              SendTickIcon(tick: tick!, color: theme.textOnBackgroundMuted),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Petite discussion dédiée à UNE SEULE carte envoyée — la question puis sa
/// réponse (le cas échéant), sous forme de bulles de chat. Chaque envoi a la
/// sienne, jamais mélangée avec les autres cartes de la boîte (voir
/// GameBoxHistoryScreen, qui liste ces discussions plutôt que de les fondre
/// en un flux unique). Si c'est à l'utilisateur·rice courant·e de répondre
/// (destinataire, pas encore répondu), un clavier classique apparaît en bas
/// — même mécanisme que GameCardReceivedScreen (bulle de notification),
/// pour pouvoir répondre aussi depuis ce fil, pas seulement depuis la bulle.
class GameCardThreadScreen extends StatefulWidget {
  final Send send;
  final AppUser user;
  final Game game;
  final GameBox box;

  const GameCardThreadScreen({
    super.key,
    required this.send,
    required this.user,
    required this.game,
    required this.box,
  });

  @override
  State<GameCardThreadScreen> createState() => _GameCardThreadScreenState();
}

class _GameCardThreadScreenState extends State<GameCardThreadScreen> {
  final _composeController = TextEditingController();
  final _composeFocusNode = FocusNode();
  final _scrollController = ScrollController();
  // Message précisément cité par un clic-maintenu → "Répondre" (voir
  // _showMessageActionsMenu) — N'IMPORTE QUEL message du fil, y compris le
  // sien propre, et autant de fois que voulu (voir demande utilisateur) :
  // ce n'est PLUS "répondre à une carte" (mécanisme historique à coup
  // unique, voir _pendingSpecialAnswerSend/GameCardSend.answer) mais un
  // vrai message de chat normal qui EMBARQUE la citation (voir
  // _quoteMarker), donc jamais limité à une seule réponse par carte.
  // `null` = pas de citation en cours, comportement de chat libre normal.
  String? _replyQuoteText;
  // Pour le scroll-retour (voir _scrollToCard) uniquement — `null` si le
  // message cité n'a pas d'ancre connue (ex. un message en attente
  // d'envoi), auquel cas on cite quand même le texte mais sans lien
  // cliquable pour y remonter.
  String? _replyQuoteSendId;
  // Ancres pour remonter jusqu'à une carte-question précise (racine OU
  // relance) depuis sa bulle de réponse (voir _scrollToCard) — utile dès
  // qu'il y a plusieurs cartes/échanges dans le fil, une réponse Oui/Non ou
  // un court texte ne suffit plus à lui seul à savoir à quelle carte elle
  // se rapporte. Une clé par Send (jamais nettoyée : le fil entier reste en
  // mémoire tant que l'écran est ouvert, coût négligeable).
  final Map<String, GlobalKey> _cardKeys = {};
  GlobalKey _keyFor(String sendId) => _cardKeys.putIfAbsent(sendId, () => GlobalKey());
  // Même principe, mais ancrée sur la bulle de RÉPONSE elle-même (Oui/Non
  // ou révélation façon Sondage Surprise) plutôt que sur la carte-question
  // — après avoir répondu (voir _scrollToAnswer/_submitSpecialAnswer/
  // _submitSenderAnswer), on veut remonter jusqu'à CETTE bulle précise, pas
  // seulement jusqu'à la carte au-dessus d'elle (qui peut rester visible
  // sans que la réponse/révélation, plus bas, le soit).
  final Map<String, GlobalKey> _answerKeys = {};
  GlobalKey _answerKeyFor(String sendId) => _answerKeys.putIfAbsent(sendId, () => GlobalKey());
  // Même principe, pour un simple message de chat (voir _decodeQuoted) —
  // ni carte ni bulle de réponse, mais un message cité via "Répondre" doit
  // pouvoir remonter jusqu'à lui aussi (voir _scrollToQuoted, demande
  // utilisateur : "si on clique sur la réponse ça doit remonter à la carte
  // en question", vrai aussi pour un message cité tout court).
  final Map<String, GlobalKey> _messageKeys = {};
  GlobalKey _messageKeyFor(String sendId) => _messageKeys.putIfAbsent(sendId, () => GlobalKey());
  // Même principe, pour le panneau de réactions déployé sous une carte/un
  // message (voir _reactionPanel) — permet de le faire défiler jusqu'à
  // rester visible dès son ouverture (voir _reactionOverlay).
  final Map<String, GlobalKey> _reactionPanelKeys = {};
  GlobalKey _reactionPanelKeyFor(String sendId) => _reactionPanelKeys.putIfAbsent(sendId, () => GlobalKey());
  String? _localAnswer;
  // Quelle carte + quel bouton (Oui/Non) est en train d'envoyer (voir
  // _buildYesNoAnswerBar), sous la forme "<sendId>|<choix>" — plusieurs
  // cartes non répondues peuvent désormais afficher leur propre picker en
  // même temps dans le fil (voir demande utilisateur), donc un simple
  // "Oui"/"Non" ne suffit plus à lui seul à savoir QUELLE carte est
  // concernée : sans la carte dans la clé, taper "Oui" sur une carte
  // faisait tourner l'animation de chargement sur le bouton "Oui" de
  // TOUTES les cartes affichées, pas seulement celle tapée.
  String? _submittingYesNoChoice;
  // Même principe que _submittingYesNoChoice, pour le verdict Défi de
  // "Vérité ou Défi" (voir _buildDefiVerdictBar) — clé "sendId|verdict"
  // pour que seul le bouton précis tapé, sur la carte précise, affiche son
  // loader.
  String? _submittingDefiVerdict;
  List<Send> _replies = [];
  // État du mini-flux deviner/verdict pour les jeux `session_type = 'quiz'`
  // (voir Game.isQuiz) — inutilisés pour tous les autres jeux à boîtes.
  bool _retryGuessing = false;
  bool _submittingGuess = false;
  bool _submittingVerdict = false;
  final _retryGuessController = TextEditingController();
  // Messages en cours d'envoi côté client, pas encore confirmés par le
  // serveur (voir _submitMessage) — affichés tout de suite (façon
  // WhatsApp/Telegram) avec une horloge, puis remplacés par le vrai Send une
  // fois la réponse serveur arrivée, ou marqués en échec pour pouvoir
  // réessayer d'un tap.
  List<_PendingText> _pending = [];
  bool _loadingReplies = true;
  bool _submitting = false;
  bool _sendingHeartbeatReply = false;
  // Coût affiché dans la feuille "Faire battre son cœur en retour" (voir
  // _openHeartbeatReplyOptions) — même prix affiché sur la tuile Duo (voir
  // DarkQuickActionsGrid._heartbeatPrice). Chargé une fois au montage,
  // échec silencieux : sans lui, la feuille s'affiche juste sans badge de
  // prix plutôt que de bloquer l'écran.
  int? _heartbeatPrice;
  // Réaction rapide accrochée à N'IMPORTE QUELLE carte-jeu de la discussion
  // (la racine ET toute carte relancée via "envoyer une autre carte", voir
  // _replies) — même principe que SlideDetailScreen (un seul cercle par
  // carte, la barre se déploie au tap), voir _reactionOverlay/_addReaction.
  // L'id du Send dont le panneau est ouvert/dont une réaction est en cours
  // d'envoi, jamais deux à la fois.
  String? _reactionPickerOpenForSendId;
  String? _reactingSendId;

  // Copie mutable locale de l'envoi racine — son statut/date de lecture
  // évolue en direct (voir _applySeen), contrairement au reste de
  // widget.send qui ne change jamais.
  late Send _rootSend = widget.send;

  String? _subscribedBoxId;
  Set<String> _presentMemberIds = {};
  // Voir demande utilisateur : "des fois le message échappe au temps réel
  // et ne vient jamais, mais si je sors et reviens il apparaît" — cet
  // écran n'avait aucun filet de secours après une coupure/reconnexion du
  // websocket (contrairement à GameConversationsScreen et consorts, voir
  // RealtimeClient.resyncRequests : "émise après une reconnexion... moments
  // où des messages ont pu être manqués"), un SendCreated manqué pendant
  // cette fenêtre restait donc invisible jusqu'à rouvrir l'écran à la main.
  StreamSubscription<void>? _resyncSub;

  bool get _isMine => widget.send.senderId == widget.user.id;
  AppUser? get _partner => _isMine ? widget.send.recipient : widget.send.sender;
  String get _partnerId => _isMine ? widget.send.recipientId : widget.send.senderId;

  @override
  void initState() {
    super.initState();
    // Écran immersif façon chat (voir TimelineScreen._openSend pour le même
    // principe sur SlideDetailScreen) : la barre de navigation globale de
    // l'AppShell ne doit pas rester visible en dessous.
    AppRouter.showGlobalNavBar.value = false;
    _loadReplies().then((_) => _markIncomingAsSeen());
    _initRealtime();
    _loadHeartbeatPrice();
    _resyncSub = RealtimeClient.instance.resyncRequests.listen((_) => _loadReplies());
  }

  Future<void> _loadHeartbeatPrice() async {
    try {
      final price = await ContentService.instance.fetchHeartbeatPrice();
      if (mounted) setState(() => _heartbeatPrice = price);
    } catch (_) {
      // Échec silencieux — voir doc du champ _heartbeatPrice.
    }
  }

  @override
  void dispose() {
    // Différé au frame suivant (voir memory_game_board_screen.dart pour la
    // justification complète) — assigné en direct ici, cette mise à jour
    // plantait silencieusement pendant le démontage (arbre de widgets
    // verrouillé), ce qui laissait TOUTE la coquille globale (barre de
    // navigation, bulle de commentaires, pop-up d'invitation) coincée
    // masquée jusqu'au relancement complet de l'app.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppRouter.showGlobalNavBar.value = true;
    });
    _composeController.dispose();
    _composeFocusNode.dispose();
    _scrollController.dispose();
    _retryGuessController.dispose();
    _resyncSub?.cancel();
    if (_subscribedBoxId != null) {
      RealtimeClient.instance.unsubscribeFromBox(
        _subscribedBoxId!,
        onEvent: _onRealtimeEvent,
        onPresenceChange: _onPresenceChange,
      );
    }
    super.dispose();
  }

  Future<void> _loadReplies() async {
    // Affiche la dernière page mise en cache tout de suite (voir
    // ContentService.cachedReplies), avant même la réponse réseau — même
    // principe que SlideDetailScreen._loadCachedRepliesThenRefresh pour le
    // Carnet de bord.
    final cached = await ContentService.instance.cachedReplies(widget.send.id);
    if (cached != null && mounted) {
      setState(() {
        _replies = cached.items.reversed.toList();
        _loadingReplies = false;
      });
      _scrollToBottom();
    }
    try {
      final page = await ContentService.instance.fetchReplies(widget.send.id, limit: 100);
      if (!mounted) return;
      setState(() {
        // Les plus récentes d'abord côté serveur — on veut l'ordre
        // chronologique pour un fil de discussion.
        _replies = page.items.reversed.toList();
        _loadingReplies = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingReplies = false);
    }
  }

  Future<void> _initRealtime() async {
    _subscribedBoxId = widget.send.boxId;
    try {
      await RealtimeClient.instance.subscribeToBox(
        widget.send.boxId,
        onEvent: _onRealtimeEvent,
        onPresenceChange: _onPresenceChange,
      );
    } catch (_) {
      // Best effort : sans temps réel, la discussion reste utilisable, juste
      // sans "en ligne" ni mise à jour immédiate des nouveaux messages.
    }
  }

  void _onPresenceChange(Set<String> memberIds) {
    if (!mounted) return;
    setState(() => _presentMemberIds = memberIds);
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.event == 'SendSeen') {
      final sendId = event.data?['send_id'] as String?;
      if (sendId == null) return;
      final seenAtStr = event.data?['seen_at'] as String?;
      _applySeen(sendId, seenAtStr != null ? DateTime.parse(seenAtStr) : DateTime.now());
      return;
    }
    if (event.event == 'SendDelivered') {
      final sendIds = (event.data?['send_ids'] as List?)?.map((e) => e as String).toList();
      if (sendIds == null || sendIds.isEmpty) return;
      final deliveredAtStr = event.data?['delivered_at'] as String?;
      _applyDelivered(sendIds, deliveredAtStr != null ? DateTime.parse(deliveredAtStr) : DateTime.now());
      return;
    }
    // Réponse/devinette/verdict pour la carte RACINE ou une carte relancée
    // de cette discussion (voir GameCardController::answer/guess/verdict) —
    // la bulle évolue en place, jamais un nouveau message (contrairement à
    // SendCreated ci-dessous), même principe que
    // EmojiStorySessionScreen._onRealtimeEvent (EmojiStoryUpdated). Avant,
    // seule la carte racine était mise à jour ici : la révélation d'un
    // "Sondage Surprise" relancé (voir _sendAnotherCard) n'apparaissait
    // qu'à la réouverture de l'écran — l'option "Modifier" restait
    // affichée alors que le binôme avait déjà répondu (voir demande
    // utilisateur : ça doit être du temps réel).
    if (event.event == 'GameCardUpdated') {
      final sendJson = event.data?['send'] as Map<String, dynamic>?;
      if (sendJson == null) return;
      final updated = Send.fromJson(sendJson);
      if (updated.id != _rootSend.id && !_replies.any((r) => r.id == updated.id)) return;
      if (!mounted) return;
      setState(() => _updateSend(updated));
      return;
    }
    // Le binôme vient de répondre à une demande "choisis Vérité ou Défi"
    // (voir TruthOrDareRequestController::answer) — même principe que
    // GameCardUpdated juste au-dessus : la bulle existante se met à jour en
    // place, jamais une nouvelle bulle.
    if (event.event == 'TruthOrDareRequestUpdated') {
      final sendJson = event.data?['send'] as Map<String, dynamic>?;
      if (sendJson == null) return;
      final updated = Send.fromJson(sendJson);
      if (updated.id != _rootSend.id && !_replies.any((r) => r.id == updated.id)) return;
      if (!mounted) return;
      setState(() => _updateSend(updated));
      return;
    }
    // Réaction posée par l'un OU l'autre membre du couple sur N'IMPORTE
    // QUELLE carte du fil — la racine ET toute carte relancée via "envoyer
    // une autre carte" (voir SendReactionController::store, maintenant
    // ouvert aux deux côtés) — met à jour la bulle concernée en direct sans
    // attendre une réouverture de l'écran, même principe que
    // SlideDetailScreen.
    if (event.event == 'SendReacted') {
      final reactionJson = event.data?['reaction'] as Map<String, dynamic>?;
      if (reactionJson == null) return;
      final reaction = SendReaction.fromJson(reactionJson);
      if (!mounted) return;
      if (reaction.sendId == _rootSend.id) {
        setState(() {
          _rootSend = _rootSend.copyWith(
            reactions: [..._rootSend.reactions.where((r) => r.userId != reaction.userId), reaction],
          );
        });
      } else if (_replies.any((r) => r.id == reaction.sendId)) {
        setState(() {
          _replies = _replies
              .map((r) => r.id == reaction.sendId
                  ? r.copyWith(reactions: [...r.reactions.where((rx) => rx.userId != reaction.userId), reaction])
                  : r)
              .toList();
        });
      }
      return;
    }
    if (event.event != 'SendCreated') return;
    final sendJson = event.data?['send'] as Map<String, dynamic>?;
    if (sendJson == null) return;

    final reply = Send.fromJson(sendJson);
    if (reply.replyToSendId != widget.send.id) return;
    // Déjà ajouté localement par notre propre envoi (voir _submitMessage) —
    // évite un doublon quand l'écho du serveur nous revient.
    if (_replies.any((r) => r.id == reply.id)) return;

    if (!mounted) return;
    setState(() => _replies = [..._replies, reply]);
    _scrollToBottom();
    // Le fil est ouvert : le nouveau message reçu est immédiatement "lu",
    // pas juste "envoyé" — l'expéditeur·rice voit son double-check passer
    // au bleu tout de suite, sans qu'on ait besoin de quitter puis rouvrir
    // l'écran.
    if (reply.recipientId == widget.user.id) _markSeen(reply);
  }

  /// Toute réponse reçue (racine + fil) déjà affichée à l'écran est marquée
  /// lue dès l'ouverture — pas d'accusé de réception séparé pour "vu mais
  /// pas encore lu", ce fil se comporte comme une vraie conversation qu'on
  /// consulte en l'ouvrant.
  Future<void> _markIncomingAsSeen() async {
    if (!mounted) return;
    if (_rootSend.recipientId == widget.user.id && _rootSend.status != 'seen') {
      _markSeen(_rootSend);
    }
    for (final reply in _replies) {
      if (reply.recipientId == widget.user.id && reply.status != 'seen') _markSeen(reply);
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
    setState(() {
      if (_rootSend.id == sendId) _rootSend = _rootSend.copyWith(status: 'seen', seenAt: seenAt);
      _replies = _replies.map((r) => r.id == sendId ? r.copyWith(status: 'seen', seenAt: seenAt) : r).toList();
    });
  }

  void _applyDelivered(List<String> sendIds, DateTime deliveredAt) {
    if (!mounted) return;
    setState(() {
      if (sendIds.contains(_rootSend.id) && _rootSend.status == 'sent') {
        _rootSend = _rootSend.copyWith(status: 'delivered', deliveredAt: deliveredAt);
      }
      _replies = _replies
          .map((r) => sendIds.contains(r.id) && r.status == 'sent'
              ? r.copyWith(status: 'delivered', deliveredAt: deliveredAt)
              : r)
          .toList();
    });
  }

  /// Set d'émojis proposé dans la barre de réactions — thématisé pour "Le
  /// Portrait Chinois" (jeu de révélation par métaphores), le set générique
  /// (cœurs/roses) pour tous les autres jeux à boîtes partageant ce même
  /// écran (voir kPortraitChinoisReactionEmojis).
  List<String> get _reactionEmojis =>
      widget.game.nameFor('fr') == 'Le Portrait Chinois' ? kPortraitChinoisReactionEmojis : kSendReactionEmojis;

  /// MA réaction sur UNE carte de la discussion — qui a envoyé ET qui a
  /// reçu peuvent chacun·e avoir la sienne (voir
  /// SendReactionController::store), jusqu'à une par membre du couple, sur
  /// N'IMPORTE QUELLE carte du fil (la racine ET toute carte relancée via
  /// "envoyer une autre carte" — avant, seule la racine pouvait recevoir
  /// une réaction, ce qui la faisait purement et simplement disparaître dès
  /// la deuxième carte envoyée dans la même discussion).
  SendReaction? _myReactionOn(Send send) => _findReactionOn(send, (r) => r.userId == widget.user.id);

  SendReaction? _partnerReactionOn(Send send) => _findReactionOn(send, (r) => r.userId != widget.user.id);

  SendReaction? _findReactionOn(Send send, bool Function(SendReaction) test) {
    for (final r in send.reactions) {
      if (test(r)) return r;
    }
    return null;
  }

  /// Cercle accroché au bord de [send] : ma réaction si j'en ai posé une,
  /// sinon celle de mon binôme, sinon un cercle "vide" qui invite à réagir —
  /// les deux côtés peuvent toujours taper dessus pour ouvrir le panneau
  /// (résumé + choix d'émoji, voir _reactionPanel).
  Widget? _reactionOverlay(ThemePalette theme, Send send) {
    final mine = _myReactionOn(send);
    final partner = _partnerReactionOn(send);
    void onTap() {
      final opening = _reactionPickerOpenForSendId != send.id;
      setState(() => _reactionPickerOpenForSendId = opening ? send.id : null);
      // Le panneau s'ouvre EN PLACE, juste sous [send] (voir _reactionPanel)
      // — sans ça, une carte proche du bas de l'écran fait apparaître le
      // panneau hors du cadre visible, juste au-dessus de la barre de
      // saisie fixe, donnant l'impression qu'il reste "caché derrière le
      // bouton +" (voir demande utilisateur). Il est déployé par un
      // AnimatedSize (220ms, voir _buildMessageList) : le mesurer dès la
      // frame suivante (comme _scrollToAnswer) donnait une hauteur encore
      // proche de zéro, donc un calcul de défilement correct la première
      // fois (peu de distance à parcourir) mais insuffisant les fois
      // suivantes (davantage de contenu déjà accumulé au-dessus, voir
      // demande utilisateur : "la seconde ou troisième fois ça reste
      // caché") — attendre la fin de l'animation avant de mesurer donne un
      // résultat fiable à chaque fois.
      if (opening) {
        // alignment: 1 (pas 0.8) — colle le BAS du panneau au bas du
        // cadre visible, la révélation la plus complète possible plutôt
        // qu'une simple approximation (voir demande utilisateur : "même
        // au premier clic" — 0.8 laissait apparemment encore le bas du
        // panneau hors champ selon la hauteur exacte du contenu déjà
        // affiché). 300ms (pas 230) : marge de sécurité au-delà des 220ms
        // de l'AnimatedSize, pour ne jamais mesurer une hauteur encore en
        // cours d'animation sur un appareil plus lent.
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          final ctx = _reactionPanelKeyFor(send.id).currentContext;
          if (ctx == null) return;
          Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250), curve: Curves.easeOut, alignment: 1);
        });
      }
    }

    if (mine == null && partner == null) {
      return _ReactionTriggerCircle(emoji: _reactionEmojis.first, onTap: onTap);
    }
    if (mine != null && partner != null) {
      return _DualReactionBadge(mineEmoji: mine.emoji, partnerEmoji: partner.emoji, onTap: onTap);
    }
    return _SingleReactionBadge(emoji: (mine ?? partner)!.emoji, onTap: onTap);
  }

  /// Panneau déployé sous [send] au tap sur son cercle de réaction : d'abord
  /// la "bande" listant qui a réagi avec quoi (si au moins une réaction
  /// existe), puis la rangée d'émojis pour poser/changer la mienne — jamais
  /// celle de mon binôme, chacun·e ne modifie que la sienne.
  Widget _reactionPanel(ThemePalette theme, Send send) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (send.reactions.isNotEmpty) ...[
          _ReactionSummaryStrip(theme: theme, reactions: send.reactions, myUserId: widget.user.id),
          const SizedBox(height: 8),
        ],
        _ReactionBar(
          enabled: _reactingSendId == null,
          onPick: (emoji) => _addReaction(send, emoji),
          theme: theme,
          emojiOptions: _reactionEmojis,
        ),
      ],
    );
  }

  /// Remplace [send] (racine ou une des réponses du fil) par sa version à
  /// jour — même mécanique que _applySeen/_applyDelivered, généralisée à
  /// n'importe quel champ.
  void _updateSend(Send updated) {
    if (updated.id == _rootSend.id) {
      _rootSend = updated;
    } else {
      _replies = _replies.map((r) => r.id == updated.id ? updated : r).toList();
    }
  }

  /// Pose ma réaction sur [send] TOUT DE SUITE côté écran (optimiste, comme
  /// les messages libres du fil, voir _submitMessage/_pending) — la requête
  /// part en arrière-plan, remplacée par la version confirmée du serveur à
  /// son retour ; en cas d'échec, ma réaction revient en arrière et un
  /// message prévient qu'il faut réessayer. Le/la binôme la voit apparaître
  /// de son côté en temps réel dès l'écho de SendReacted, sans avoir à
  /// avoir déjà réagi lui/elle-même.
  Future<void> _addReaction(Send send, String emoji) async {
    if (_reactingSendId != null) return;
    final previousReactions = send.reactions;
    final optimistic = SendReaction(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      sendId: send.id,
      userId: widget.user.id,
      emoji: emoji,
      createdAt: DateTime.now(),
    );
    setState(() {
      _reactingSendId = send.id;
      _reactionPickerOpenForSendId = null;
      _updateSend(send.copyWith(
        reactions: [...previousReactions.where((r) => r.userId != widget.user.id), optimistic],
      ));
    });
    try {
      final updated = await ContentService.instance.reactToSend(send.id, emoji);
      if (mounted) {
        setState(() => _updateSend(updated.copyWith(
              reactions: SendReaction.dedupeByUser(updated.reactions),
            )));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _updateSend(send.copyWith(reactions: previousReactions)));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LocaleScope.of(context).t('game_reaction_send_failed'))),
      );
    } finally {
      if (mounted) setState(() => _reactingSendId = null);
    }
  }

  /// Remonte jusqu'à la carte-question [sendId] (racine ou une relance) —
  /// tapée depuis la citation en tête de sa bulle de réponse (voir
  /// _ChatBubble.replyPreview), pour clarifier à quelle carte une réponse
  /// Oui/Non ou texte se rapporte quand d'autres échanges se sont
  /// accumulés depuis.
  void _scrollToCard(String sendId) {
    final ctx = _cardKeys[sendId]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeOut, alignment: 0.1);
  }

  /// Remonte jusqu'au message cité — carte, bulle de réponse OU simple
  /// message de chat, selon ce qui a été cité (voir _replyQuoteSendId pour
  /// la bannière "Tu réponds à...", et _decodeQuoted pour une citation déjà
  /// affichée dans une bulle envoyée/reçue, voir demande utilisateur). Ne
  /// fait rien si la clé n'existe plus (ex. citation d'un message trop
  /// ancien, pas encore chargé dans ce fil) plutôt que de planter.
  void _scrollToQuoted(String sendId) {
    final ctx = _cardKeys[sendId]?.currentContext ??
        _answerKeys[sendId]?.currentContext ??
        _messageKeys[sendId]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeOut, alignment: 0.1);
  }

  /// Remonte jusqu'à la bulle de RÉPONSE de [sendId] (Oui/Non ou
  /// révélation, voir _answerKeyFor) — utilisée juste après avoir répondu
  /// (voir _submitSpecialAnswer/_submitSenderAnswer), pour que ce soit bien
  /// la réponse/révélation qui vient d'apparaître qui reste visible à
  /// l'écran, pas seulement la carte-question au-dessus d'elle.
  void _scrollToAnswer(String sendId) {
    // Reporté à la frame suivante : juste après le setState() qui fait
    // apparaître CETTE bulle de réponse pour la toute première fois, elle
    // n'existe pas encore dans l'arbre reconstruit — currentContext était
    // alors toujours `null` et la fonction ne faisait rien, laissant le
    // premier message visuellement coincé derrière la carte-question (voir
    // demande utilisateur, constaté en réel). _scrollToBottom fait déjà ce
    // report, pas celle-ci jusqu'ici.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _answerKeys[sendId]?.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeOut, alignment: 0.2);
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  /// Le texte libre ne route encore automatiquement vers le mécanisme
  /// historique (GameCardSend.answer, voir GameCardController) QUE pour
  /// "Qui nous connaît le mieux ?" (Quiz) — c'est là le mécanisme de jeu
  /// lui-même (la devinette), pas une simple marque "répondu". Pour tous
  /// les autres jeux, ce routage automatique a été retiré (voir demande
  /// utilisateur : un message tapé sans passer par "Répondre" ne doit plus
  /// être pris pour LA réponse officielle à la carte-question) — Oui/Non
  /// garde son mécanisme dédié (_submitYesNoAnswer), et les jeux
  /// "classiques" (À Nous Deux, Vérité ou Défi...) restent un vrai chat
  /// libre dès le premier message.
  Send? get _pendingSpecialAnswerSend {
    if (!widget.game.isQuiz) return null;
    final card = _rootSend.gameCard;
    if (card == null || _rootSend.recipientId != widget.user.id || card.answer != null || _replies.isNotEmpty) {
      return null;
    }
    return _rootSend;
  }

  /// Id du Send (racine OU une relance, voir _replies) dont la carte de ce
  /// jeu est EN COURS d'envoi de ma réponse — null si aucune. Chaque carte
  /// "Le Sondage Surprise" en attente garde son propre picker collé sous
  /// elle (voir _buildBlindPollAnswerBar, appelé une fois par carte non
  /// répondue dans _buildMessageList) plutôt qu'un seul picker partagé dans
  /// la barre de saisie qui ne pouvait répondre qu'à UNE carte à la fois —
  /// avant, une deuxième carte reçue dans la même discussion avant d'avoir
  /// répondu à la première restait bloquée sans aucun moyen d'y répondre
  /// (voir demande utilisateur : "on doit pouvoir répondre à chacune").
  String? _submittingBlindAnswer;

  Future<void> _submitBlindPollAnswer(Send target, String answer) async {
    final card = target.gameCard;
    if (card == null || _submittingBlindAnswer != null) return;
    setState(() => _submittingBlindAnswer = target.id);
    try {
      final updated = await GameService.instance.answerBlindPoll(card.id, answer);
      if (!mounted) return;
      // Pas de _scrollToBottom() ici, contrairement aux autres envois du
      // fil : la révélation apparaît directement à la place du picker,
      // là où l'œil est déjà posé — un saut vers le bas déplacerait la vue
      // sans raison (voir demande utilisateur : "l'écran ne me renvoie
      // plus en bas").
      setState(() {
        if (target.id == _rootSend.id) _localAnswer = answer;
        _updateSend(target.copyWith(gameCard: updated));
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submittingBlindAnswer = null);
    }
  }

  /// Id de la carte "Le Sondage Surprise" dont je suis en train de modifier
  /// MA réponse (voir _buildPollWaitingBubble) — un seul picker de
  /// modification ouvert à la fois, comme pour l'envoi initial.
  String? _editingBlindPollAnswerFor;

  Future<void> _updateBlindPollSenderAnswer(GameCardSend card, String answer) async {
    if (_submittingBlindAnswer != null) return;
    setState(() => _submittingBlindAnswer = card.id);
    try {
      final updated = await GameService.instance.updateBlindPollSenderAnswer(card.id, answer);
      if (!mounted) return;
      setState(() {
        _editingBlindPollAnswerFor = null;
        final target = [_rootSend, ..._replies].firstWhere((s) => s.gameCard?.id == card.id);
        _updateSend(target.copyWith(gameCard: updated));
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submittingBlindAnswer = null);
    }
  }

  /// Horodatage à donner à un message optimiste (voir _PendingText) —
  /// jamais un simple DateTime.now() brut : si l'horloge du serveur avance
  /// ne serait-ce que de quelques secondes sur celle de l'appareil, un
  /// message qu'on vient de taper (donc plus récent que tout le reste)
  /// pouvait se trier AVANT le dernier message déjà confirmé (horodaté par
  /// le serveur), le temps de l'envoi — avant de "sauter" à sa bonne place
  /// une fois la réponse serveur reçue et son vrai timestamp appliqué (voir
  /// demande utilisateur, constaté en réel). En le calant toujours après le
  /// plus récent horodatage déjà connu dans ce fil (racine, réponses,
  /// autres messages en attente), il reste visuellement à la bonne place
  /// dès l'affichage optimiste, quel que soit l'écart d'horloge.
  DateTime _nextPendingTime() {
    var latest = DateTime.now();
    final known = <DateTime>[
      widget.send.createdAt,
      _rootSend.gameCard?.answeredAt ?? _rootSend.createdAt,
      ..._replies.map((r) => r.createdAt),
      ..._pending.map((p) => p.time),
    ];
    for (final t in known) {
      if (t.isAfter(latest)) latest = t.add(const Duration(milliseconds: 1));
    }
    return latest;
  }

  Future<void> _submitMessage() async {
    final rawText = _composeController.text.trim();
    if (rawText.isEmpty || _submitting) return;
    _composeController.clear();

    // Citation explicite via clic-maintenu → "Répondre" (voir
    // _showMessageActionsMenu) — TOUJOURS un message de chat normal,
    // jamais le mécanisme à coup unique GameCardSend.answer (voir
    // _submitSpecialAnswer) : contrairement à "répondre à la carte", citer
    // un message doit pouvoir se faire sur n'importe quel message (y
    // compris le sien propre) et autant de fois que voulu (voir demande
    // utilisateur) — un champ à coup unique ne le permettrait pas.
    final quote = _replyQuoteText;
    if (quote != null) {
      final quoteId = _replyQuoteSendId;
      setState(() {
        _replyQuoteText = null;
        _replyQuoteSendId = null;
      });
      final pending = _PendingText(
        text: _encodeQuoted(quote, rawText, quoteSendId: quoteId),
        time: _nextPendingTime(),
      );
      setState(() => _pending = [..._pending, pending]);
      _scrollToBottom();
      await _sendPending(pending);
      return;
    }

    // Pour "Qui nous connaît le mieux ?" (Quiz), le texte libre EST le
    // mécanisme de jeu (la devinette, voir GameCardController::answer) —
    // conservé tel quel. Pour tous les autres jeux "classiques", écrire
    // dans la barre de saisie n'est PLUS jamais considéré comme LA réponse
    // officielle à la carte-question : seul un "Répondre" explicite (clic-
    // maintenu, voir _showMessageActionsMenu) cite un message précis (voir
    // demande utilisateur : un "Ok" tapé au hasard ne doit plus se
    // retrouver affiché comme LA réponse à la question, voir
    // _pendingSpecialAnswerSend qui ne couvre plus que ce cas Quiz).
    final pendingSpecial = _pendingSpecialAnswerSend;
    if (pendingSpecial != null) {
      await _submitSpecialAnswer(pendingSpecial, rawText);
      return;
    }

    // Chat libre : le message apparaît tout de suite (horloge) plutôt que
    // d'attendre la confirmation serveur, façon WhatsApp/Telegram — voir
    // _sendPending pour la bascule vers "envoyé"/"échec".
    final pending = _PendingText(text: rawText, time: _nextPendingTime());
    setState(() => _pending = [..._pending, pending]);
    _scrollToBottom();
    await _sendPending(pending);
  }

  // STX/ETX (caractères de contrôle qu'aucun clavier/IME ne produit
  // jamais) plutôt qu'un champ serveur dédié — citer N'IMPORTE QUEL
  // message (voir demande utilisateur) sans devoir faire évoluer le
  // schéma `Send` : la citation voyage simplement AVEC le texte du
  // message, dans le même champ `message` déjà utilisé pour un chat libre
  // normal (voir ContentService.sendTextReply).
  static const _quoteStart = '\u0002';
  static const _quoteEnd = '\u0003';
  static const _quoteIdSeparator = '\u0004';
  // Sépare l'id du message cité de son texte, À L'INTÉRIEUR de la citation
  // (voir _encodeQuoted) — permet de remonter au message cité en tapant
  // dessus (voir _scrollToQuoted), tout en restant lisible pour les
  // messages déjà envoyés AVANT cet ajout (quoteId reste `null` pour
  // ceux-là plutôt que de planter, voir _decodeQuoted).

  String _encodeQuoted(String quote, String text, {String? quoteSendId}) {
    final quotePart = quoteSendId != null ? '$quoteSendId$_quoteIdSeparator$quote' : quote;
    return '$_quoteStart$quotePart$_quoteEnd$text';
  }

  /// Sépare un texte de message éventuellement cité en (id du message cité,
  /// citation, texte réel) — `quote` reste `null` pour un message de chat
  /// normal (l'énorme majorité), aucun risque de faux positif : `_quoteStart`
  /// n'apparaît jamais dans un texte tapé au clavier.
  ({String? quoteId, String? quote, String text}) _decodeQuoted(String raw) {
    if (raw.startsWith(_quoteStart)) {
      final endIndex = raw.indexOf(_quoteEnd);
      if (endIndex != -1) {
        final quotePart = raw.substring(1, endIndex);
        final text = raw.substring(endIndex + 1);
        final sepIndex = quotePart.indexOf(_quoteIdSeparator);
        if (sepIndex != -1) {
          return (quoteId: quotePart.substring(0, sepIndex), quote: quotePart.substring(sepIndex + 1), text: text);
        }
        return (quoteId: null, quote: quotePart, text: text);
      }
    }
    return (quoteId: null, quote: null, text: raw);
  }

  /// Menu générique de clic-maintenu — sur N'IMPORTE QUEL message du fil
  /// (carte, réponse, message libre, y compris le sien propre), autant de
  /// fois que voulu (voir demande utilisateur). "Répondre" cite
  /// [quoteText] dans le prochain message envoyé (voir
  /// _encodeQuoted/_submitMessage). "Envoyer une pensée"/"un poème"
  /// rejoignent CETTE discussion (voir _reply/_openHeartbeatReplyOptions,
  /// déjà utilisés par _buildAnswerActionsMenu) mais pas CE message précis
  /// — un poème/une pensée n'a pas de notion de "message visé" côté
  /// backend, contrairement à une citation. Regroupés ici par confort (un
  /// seul geste, clic-maintenu) plutôt que par lien réel au message.
  Future<void> _showMessageActionsMenu(
    BuildContext context,
    Offset globalPosition, {
    required String quoteText,
    String? quoteSendId,
    // Une carte "défi" (voir GameCardSend.isDefi) n'a pas de réponse écrite
    // — son verdict passe par _buildDefiVerdictBar, jamais par une citation
    // en chat — donc "Répondre" n'a pas de sens pour elle (voir demande
    // utilisateur).
    bool hideReply = false,
  }) async {
    // Petit retour tactile au moment où le menu apparaît — même geste que
    // le clic-maintenu d'un vrai clavier/chat natif, confirme que le
    // clic-maintenu a bien été reconnu avant même de voir le menu.
    HapticFeedback.mediumImpact();
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    // "Sans Détour" (voir Game.isYesNoOnly) n'a JAMAIS de zone de texte
    // libre — le Oui/Non brut EST la réponse finale, sans justification
    // possible (voir _buildActionsOnlyComposer). "Répondre" permettrait de
    // contourner ça en citant n'importe quel message avec un texte libre :
    // masqué pour CE jeu uniquement, quel que soit ce qui est cité (carte,
    // poème, battement de cœur...), pas seulement pour les cartes "défi"
    // (voir demande utilisateur : "uniquement pour ce jeu").
    final effectiveHideReply = hideReply || widget.game.isYesNoOnly;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      color: theme.surface,
      items: [
        if (!effectiveHideReply)
          PopupMenuItem(
            value: 'reply',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.reply_rounded, size: 18, color: theme.primary),
                const SizedBox(width: 10),
                Text(t('game_action_reply'), style: GoogleFonts.nunito(color: theme.textOnBackground)),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'new_card',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.style_rounded, size: 18, color: theme.primary),
              const SizedBox(width: 10),
              Text(t('game_action_send_new_card'), style: GoogleFonts.nunito(color: theme.textOnBackground)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'heartbeat',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_rounded, size: 18, color: theme.primary),
              const SizedBox(width: 10),
              Text(t('game_action_send_heartbeat'), style: GoogleFonts.nunito(color: theme.textOnBackground)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'poem',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_stories_rounded, size: 18, color: theme.primary),
              const SizedBox(width: 10),
              Text(t('game_action_send_poem'), style: GoogleFonts.nunito(color: theme.textOnBackground)),
            ],
          ),
        ),
      ],
    );
    if (!mounted) return;
    switch (selected) {
      case 'reply':
        setState(() {
          _replyQuoteText = quoteText;
          _replyQuoteSendId = quoteSendId;
        });
        _composeFocusNode.requestFocus();
        break;
      case 'heartbeat':
        _openHeartbeatReplyOptions();
        break;
      case 'poem':
        _reply();
        break;
      case 'new_card':
        _sendAnotherCard();
        break;
    }
  }

  /// Enrobe _submitSpecialAnswer pour les boutons Oui/Non — mémorise
  /// QUELLE carte ET LEQUEL des deux boutons est tapé (voir
  /// _submittingYesNoChoice) pour que seul ce bouton précis, sur cette
  /// carte précise, affiche l'animation de chargement.
  Future<void> _submitYesNoAnswer(Send target, String choice) async {
    setState(() => _submittingYesNoChoice = '${target.id}|$choice');
    try {
      await _submitSpecialAnswer(target, choice);
    } finally {
      if (mounted) setState(() => _submittingYesNoChoice = null);
    }
  }

  /// Même principe que _submitYesNoAnswer, pour le verdict d'une carte
  /// "défi" de "Vérité ou Défi" (voir _buildDefiVerdictBar) — un champ de
  /// texte libre n'a pas de sens pour un défi, seul un verdict binaire
  /// compte (voir demande utilisateur).
  Future<void> _submitDefiVerdict(Send target, String verdict) async {
    setState(() => _submittingDefiVerdict = '${target.id}|$verdict');
    try {
      await _submitSpecialAnswer(target, verdict);
    } finally {
      if (mounted) setState(() => _submittingDefiVerdict = null);
    }
  }

  /// Toute première réponse à [target] (la racine OU une carte relancée) —
  /// pour les jeux classiques/quiz (voir _pendingSpecialAnswerSend), vient
  /// du champ de saisie libre ; pour `session_type = 'yes_no'`/
  /// `'yes_no_only'` (voir Game.isYesNo/isYesNoOnly), vient du picker
  /// Oui/Non affiché EN LIGNE sous [target] (voir _buildYesNoAnswerBar,
  /// appelé via _submitYesNoAnswer). Met à jour [target] en place via
  /// _updateSend plutôt qu'un champ optimiste séparé : `card.answer`
  /// reflète directement la réponse, racine ou relance, sans distinction
  /// dans le rendu.
  Future<void> _submitSpecialAnswer(Send target, String text) async {
    setState(() => _submitting = true);
    try {
      final card = target.gameCard!;
      await GameService.instance.answerCard(card.id, text);
      if (!mounted) return;
      setState(() {
        // Pour un jeu `session_type = 'quiz'`, cette réponse compte AUSSI
        // comme la première devinette côté backend (voir
        // GameCardController::answer) — on simule ici cette devinette en
        // attente de verdict pour que la bulle bascule tout de suite en
        // "en attente du verdict", sans attendre un aller-retour réseau
        // (le prochain GameCardUpdated, déclenché par le verdict, la
        // remplacera par la version exacte du serveur).
        _updateSend(target.copyWith(
          gameCard: GameCardSend(
            id: card.id,
            gameId: card.gameId,
            gameBoxId: card.gameBoxId,
            gameBoxQuestionId: card.gameBoxQuestionId,
            questionText: card.questionText,
            gameBoxTitle: card.gameBoxTitle,
            answer: text,
            answeredAt: DateTime.now(),
            bouncedFromId: card.bouncedFromId,
            category: card.category,
            resolvedAt: card.resolvedAt,
            won: card.won,
            guesses: widget.game.isQuiz
                ? [
                    ...card.guesses,
                    GameCardGuess(id: 'local-${DateTime.now().microsecondsSinceEpoch}', guess: text, createdAt: DateTime.now()),
                  ]
                : card.guesses,
            senderAnswer: card.senderAnswer,
            options: card.options,
          ),
        ));
      });
      // Remonte vers LA BULLE DE RÉPONSE elle-même, pas vers le bas du fil
      // ni juste vers la carte-question au-dessus (voir demande
      // utilisateur) — pour un jeu comme "Sans Détour", le picker Oui/Non
      // répondu est collé à sa propre carte, potentiellement loin du bas
      // si d'autres cartes ont été envoyées depuis.
      _scrollToAnswer(target.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _invitingSenderForSendId;
  // "<sendId>|<choix>" en cours d'envoi (voir _submittingYesNoChoice pour
  // le même besoin côté picker du/de la destinataire) — plusieurs cartes
  // peuvent m'attendre en tant qu'expéditeur·rice invité·e en même temps
  // (voir demande utilisateur), donc un simple bool bloquerait/animerait
  // TOUS les pickers sender-answer affichés à la fois au lieu d'un seul.
  String? _submittingSenderAnswerKey;

  /// Invite qui a envoyé [target] à répondre lui/elle aussi à la même
  /// question (voir GameCardSend.needsSenderAnswer côté binôme, affiché en
  /// ligne sous SA carte via _buildSenderAnswerBar) — déclenché depuis le
  /// menu accroché à ma propre bulle de réponse (voir
  /// _buildAnswerActionsMenu), jamais visible si je suis moi-même qui a
  /// envoyé la carte.
  Future<void> _inviteSenderToAnswer(Send target) async {
    final card = target.gameCard;
    if (card == null || _invitingSenderForSendId == target.id) return;
    setState(() => _invitingSenderForSendId = target.id);
    try {
      final updated = await GameService.instance.inviteSenderToAnswer(card.id);
      if (!mounted) return;
      setState(() => _updateSend(target.copyWith(gameCard: updated)));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LocaleScope.of(context).t('game_invite_sent_snackbar'))),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _invitingSenderForSendId = null);
    }
  }

  /// Ma réponse à [target], après avoir été invité·e par mon binôme (voir
  /// GameCardSend.needsSenderAnswer/_buildSenderAnswerBar) — une fois
  /// envoyée, les deux réponses sont réunies et la bulle bascule automatiquement en
  /// révélation façon Sondage Surprise (voir GameCardSend.isPollRevealed).
  Future<void> _submitSenderAnswer(Send target, String answer) async {
    final card = target.gameCard;
    final key = '${target.id}|$answer';
    if (card == null || _submittingSenderAnswerKey != null) return;
    setState(() => _submittingSenderAnswerKey = key);
    try {
      final updated = await GameService.instance.answerAsSender(card.id, answer);
      if (!mounted) return;
      setState(() => _updateSend(target.copyWith(gameCard: updated)));
      // Remonte vers LA BULLE DE RÉVÉLATION elle-même, pas vers le bas du
      // fil ni juste vers la carte-question (voir demande utilisateur) —
      // sinon elle peut rester hors écran si d'autres cartes ont été
      // envoyées depuis.
      _scrollToAnswer(target.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submittingSenderAnswerKey = null);
    }
  }

  Future<void> _sendPending(_PendingText pending) async {
    setState(() => pending.failed = false);
    try {
      final reply = await ContentService.instance.sendTextReply(widget.send.id, pending.text);
      if (!mounted) return;
      // Meme protection que _sendHeartbeatReply : l'echo temps reel peut
      // deja avoir ajoute ce message avant que cette reponse HTTP revienne.
      setState(() {
        _pending = _pending.where((p) => p != pending).toList();
        if (!_replies.any((r) => r.id == reply.id)) {
          _replies = [..._replies, reply];
        }
      });
      _syncRepliesCacheSilently();
    } catch (_) {
      if (!mounted) return;
      setState(() => pending.failed = true);
    }
  }

  /// Resynchronise le cache local du fil en arrière-plan (voir
  /// ContentService.fetchReplies, qui l'écrit en effet de bord dès qu'il
  /// réussit) — à appeler après tout envoi optimiste qui ajoute directement
  /// à [_replies] sans repasser par _loadReplies(). Sans ça, le cache
  /// restait figé sur l'état d'AVANT cet envoi, et la prochaine ouverture
  /// de cette discussion montrait d'abord les anciens messages avant de
  /// sauter brusquement vers les récents une fois le réseau répondu
  /// (constaté en réel, voir demande utilisateur). Résultat ignoré : l'UI
  /// affiche déjà la bonne version via l'ajout optimiste, ce n'est QUE pour
  /// garder le cache à jour pour la prochaine fois.
  void _syncRepliesCacheSilently() {
    ContentService.instance
        .fetchReplies(widget.send.id, limit: 100)
        .catchError((_) => const RepliesPage(items: [], hasMore: false));
  }

  /// Texte à afficher pour une réponse du fil qui n'est ni une carte ni un
  /// message texte libre (poème/battement de cœur, voir _reply et
  /// _sendHeartbeatReply) — même repli que SlideDetailScreen._mainText,
  /// simple texte plutôt que la mini-carte visuelle de ce dernier : ce fil
  /// reste un chat classique.
  String _replyText(Send reply) {
    final localeCode = LocaleScope.of(context).current.code;
    final t = LocaleScope.of(context).t;
    if (reply.isPack) return reply.pack?.titleFor(localeCode) ?? t('send_fallback_poem');
    if (reply.isHeartbeat) return reply.heartbeatMessageFor(localeCode) ?? t('heartbeat_default_message');
    return reply.textReplyText ?? reply.emojiReplyText ?? reply.message ?? '';
  }

  /// Répondre avec un poème — même geste que dans le Carnet de bord (voir
  /// SlideDetailScreen._reply) : ouvre le choix de pack, la slide envoyée
  /// rejoint CETTE discussion via reply_to_send_id.
  Future<void> _reply() async {
    final replied = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'reply-root'),
        builder: (_) => PacksScreen(replyToSendId: widget.send.id),
      ),
    );
    if (!mounted) return;
    // Voir demande utilisateur : même correctif que _sendAnotherCard — le
    // clavier ne doit pas se rouvrir tout seul au retour sur cette
    // discussion.
    _composeFocusNode.unfocus();
    if (replied == true) {
      _loadReplies();
    }
  }

  /// Répondre par un battement de cœur — même choix (pensée surprise ou mot
  /// personnalisé) que SlideDetailScreen._openHeartbeatReplyOptions.
  ///
  /// "Une pensée surprise" envoie et ATTEND la fin de l'envoi AVANT de
  /// fermer la feuille (voir StatefulBuilder ci-dessous), avec un loader à
  /// la place des deux choix pendant ce temps — sans ça, la feuille se
  /// fermait tout de suite et l'utilisateur se retrouvait face à la
  /// discussion sans aucun indice qu'un envoi était en cours (voir demande
  /// utilisateur, délai perçu comme "l'app n'a rien fait").
  Future<void> _openHeartbeatReplyOptions() async {
    if (_sendingHeartbeatReply) return;
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;
    // En dehors du builder — sinon StatefulBuilder le réinitialiserait à
    // `false` à chaque reconstruction déclenchée par setSheetState, et le
    // loader n'apparaîtrait jamais (constaté via l'analyseur : "dead code"
    // sur la branche `if (sendingRandom)`).
    var sendingRandom = false;
    // Un sous-titre différent tiré au hasard parmi 4 à chaque ouverture de
    // la feuille (voir demande utilisateur) — calculé une seule fois ici,
    // pas dans le builder, sinon setSheetState en tirerait un nouveau à
    // chaque frappe/chargement et le texte clignoterait.
    final randomSubtitleKey = 'heartbeat_reply_random_subtitle_${math.Random().nextInt(4) + 1}';
    final customSubtitleKey = 'heartbeat_reply_custom_subtitle_${math.Random().nextInt(4) + 1}';

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: theme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return SafeArea(
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t('heartbeat_reply_sheet_title'),
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: theme.textOnBackground),
                        ),
                      ),
                      // Même prix quel que soit le choix (voir
                      // HeartbeatController::send) — un seul badge ici
                      // plutôt que répété sur chaque option en dessous,
                      // même principe que Duo (voir DarkQuickActionsGrid).
                      if (_heartbeatPrice != null) _HeartbeatPriceBadge(coinPrice: _heartbeatPrice!),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t('heartbeat_reply_sheet_subtitle'),
                    style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                  ),
                  const SizedBox(height: 18),
                  if (sendingRandom)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: theme.primary),
                            const SizedBox(height: 12),
                            Text(t('common_sending_in_progress'), style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted)),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.auto_awesome_rounded, color: theme.primary),
                      title: Text(t('heartbeat_reply_random_title'), style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground)),
                      subtitle: Text(
                        t(randomSubtitleKey),
                        style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                      ),
                      onTap: () async {
                        setSheetState(() => sendingRandom = true);
                        await _sendHeartbeatReply();
                        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_note_rounded, color: theme.primary),
                      title: Text(t('heartbeat_reply_custom_title'), style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground)),
                      subtitle: Text(
                        t(customSubtitleKey),
                        style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                      ),
                      onTap: () => Navigator.of(sheetContext).pop('custom'),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );

    if (!mounted) return;
    _composeFocusNode.unfocus();
    // "random" est déjà entièrement envoyé (et sa bulle déjà à l'écran)
    // avant même la fermeture de la feuille ci-dessus — rien d'autre à
    // faire ici.
    if (choice != 'custom') return;
    _composeCustomHeartbeatReply();
  }

  /// Le dialogue reste ouvert le temps de l'envoi (voir StatefulBuilder,
  /// même principe que _openHeartbeatReplyOptions) — bouton "Envoyer"
  /// remplacé par un petit loader plutôt que de fermer tout de suite en
  /// laissant l'utilisateur face à la discussion sans indice d'envoi en
  /// cours (voir demande utilisateur).
  Future<void> _composeCustomHeartbeatReply() async {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;
    final controller = TextEditingController();
    var sending = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: theme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(t('heartbeat_reply_dialog_title'), style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground)),
          content: TextField(
            controller: controller,
            autofocus: true,
            enabled: !sending,
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
              onPressed: sending ? null : () => Navigator.of(dialogContext).pop(),
              child: Text(t('common_cancel'), style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: theme.primary),
              onPressed: sending
                  ? null
                  : () async {
                      final text = controller.text.trim();
                      if (text.isEmpty) return;
                      setDialogState(() => sending = true);
                      await _sendHeartbeatReply(message: text);
                      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                    },
              child: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                    )
                  : Text(t('heartbeat_reply_send_button')),
            ),
          ],
        ),
      ),
    );
    // Voir demande utilisateur : même correctif que _sendAnotherCard/_reply
    // — pas de clavier qui se rouvre tout seul au retour sur cette
    // discussion une fois le battement de cœur envoyé.
    if (mounted) _composeFocusNode.unfocus();
  }

  Future<void> _sendHeartbeatReply({String? message}) async {
    if (_sendingHeartbeatReply) return;
    setState(() => _sendingHeartbeatReply = true);
    try {
      // Un seul aller-retour réseau avant d'afficher quoi que ce soit — la
      // réponse contient déjà le Send créé (voir ContentService.sendHeartbeat),
      // pas besoin d'un _loadReplies() qui recharge TOUT le fil (jusqu'à 100
      // messages) juste pour ce nouveau message. C'était la cause du délai
      // de 4-5 secondes constaté en réel (voir demande utilisateur) : trois
      // appels réseau enchaînés (envoi, rafraîchissement du solde, puis
      // rechargement complet) avant que quoi que ce soit apparaisse.
      final reply = await ContentService.instance.sendHeartbeat(message: message, replyToSendId: widget.send.id);
      if (!mounted) return;
      // L'écho temps réel de notre propre envoi (voir _onRealtimeEvent) peut
      // arriver avant cette réponse HTTP et l'ajouter en premier — éviter un
      // doublon si c'est déjà le cas (voir demande utilisateur : le message
      // apparaissait deux fois jusqu'à quitter/revenir sur l'écran).
      if (!_replies.any((r) => r.id == reply.id)) {
        setState(() => _replies = [..._replies, reply]);
      }
      _scrollToBottom();
      _syncRepliesCacheSilently();
      // Le solde affiché ailleurs (badge en haut) peut se rafraîchir en
      // arrière-plan sans bloquer l'apparition du message — l'utilisateur
      // n'a pas besoin d'attendre ça pour voir sa pensée envoyée.
      unawaited(WalletBalanceNotifier.instance.refresh());
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

  /// Toutes les cartes du "Sondage Surprise" révélées (les deux réponses
  /// réunies) dans CETTE discussion, dans l'ORDRE chronologique — la carte
  /// racine d'abord, puis chaque relance envoyée via "envoyer une autre
  /// carte" (voir _replies, déjà dans cet ordre). Sert à la fois au score
  /// de la discussion (_threadPollStats) et à la règle "la toute première
  /// carte affiche toujours la première formule" (voir
  /// _isFirstPollRevealInThread).
  List<GameCardSend> get _revealedPollCardsInThread {
    if (!widget.game.isBlindPoll) return const [];
    return <GameCardSend>[
      if (_rootSend.gameCard != null) _rootSend.gameCard!,
      for (final r in _replies)
        if (r.gameCard != null) r.gameCard!,
    ].where((c) => c.senderAnswer != null && c.answer != null).toList();
  }

  /// Vrai seulement pour la toute première carte révélée de la discussion
  /// (dans l'ordre chronologique) — elle affiche toujours la première
  /// formule de la liste correspondante (voir pickPollRevealPhrase), les
  /// suivantes piochent parmi les autres.
  bool _isFirstPollRevealInThread(String cardId) {
    final cards = _revealedPollCardsInThread;
    return cards.isNotEmpty && cards.first.id == cardId;
  }

  /// Score de complicité pour "Le Sondage Surprise" (voir Game.isBlindPoll)
  /// — calculé UNIQUEMENT à partir des cartes déjà chargées de CETTE
  /// discussion (la carte racine + toute carte renvoyée via "envoyer une
  /// autre carte", voir _replies), jamais mélangé avec d'autres discussions
  /// du même jeu : chaque discussion garde son propre score (demande
  /// explicite de l'utilisateur, pas un score cumulé pour tout le jeu comme
  /// pour le quiz "Qui nous connaît le mieux ?"). Aucun appel réseau
  /// supplémentaire : ces cartes sont déjà en mémoire pour l'affichage du
  /// fil lui-même.
  BlindPollStats? get _threadPollStats {
    final cards = _revealedPollCardsInThread;

    if (cards.isEmpty) return null;
    final aligned = cards.where((c) => c.pollAligned).length;
    return BlindPollStats(totalResolved: cards.length, aligned: aligned, percentage: aligned / cards.length * 100);
  }

  /// Toutes les questions déjà présentes dans CETTE discussion — la carte
  /// d'origine et toute carte déjà renvoyée via ce même raccourci (voir
  /// _replies) — pour qu'aucune ne puisse être re-choisie par erreur depuis
  /// l'éventail rouvert ci-dessous.
  Set<String> get _questionIdsAlreadyInThread => {
        if (widget.send.gameCard != null) widget.send.gameCard!.gameBoxQuestionId,
        for (final r in _replies)
          if (r.gameCard != null) r.gameCard!.gameBoxQuestionId,
      };

  /// Série de choix Vérité/Défi identiques déjà envoyés par MOI dans cette
  /// discussion (la carte d'origine et toute carte déjà renvoyée), la plus
  /// récente d'abord — pour que la règle des 3 choix consécutifs (voir
  /// TruthOrDareSessionScreen._isBlocked) survive à la fermeture/réouverture
  /// répétée de l'éventail via "envoyer une autre carte" : chaque
  /// ré-ouverture recrée un TOUT NOUVEL écran (donc un _streak local remis à
  /// zéro), ce qui laissait sinon passer 3 défis d'affilée en cliquant 3
  /// fois de suite sur cette icône plutôt qu'une seule fois sur la même
  /// carte retournée.
  ({String? category, int streak}) get _myTrailingCategoryStreak {
    final mine = <Send>[
      if (widget.send.gameCard != null && widget.send.senderId == widget.user.id) widget.send,
      for (final r in _replies)
        if (r.gameCard != null && r.senderId == widget.user.id) r,
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    String? lastCategory;
    var streak = 0;
    for (final send in mine) {
      final category = send.gameCard!.category;
      if (category == null) continue;
      if (category == lastCategory) {
        streak++;
      } else {
        lastCategory = category;
        streak = 1;
      }
    }
    return (category: lastCategory, streak: streak);
  }

  /// Même principe que [_myTrailingCategoryStreak], mais pour MES réponses
  /// à une demande "choisis Vérité ou Défi" (voir TruthOrDareRequest) —
  /// évite qu'on puisse contourner la règle des 3 choix identiques
  /// d'affilée en répondant toujours "Défi" à chaque nouvelle demande.
  ({String? category, int streak}) get _myTrailingResponseStreak {
    final mine = _replies
        .where((r) =>
            r.isTruthOrDareRequest &&
            r.truthOrDareRequest != null &&
            r.truthOrDareRequest!.isAnswered &&
            r.truthOrDareRequest!.responderId == widget.user.id)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    String? lastCategory;
    var streak = 0;
    for (final send in mine) {
      final category = send.truthOrDareRequest!.chosenCategory;
      if (category == null) continue;
      if (category == lastCategory) {
        streak++;
      } else {
        lastCategory = category;
        streak = 1;
      }
    }
    return (category: lastCategory, streak: streak);
  }

  /// Même règle que TruthOrDareSessionScreen._isBlocked, appliquée à MES
  /// réponses plutôt qu'à mes propres cartes envoyées (voir demande
  /// utilisateur : "la contrainte des 3 choix identiques s'applique à
  /// celui/celle qui choisit"). Ne vérifie pas l'exclusion des questions
  /// déjà jouées dans CE fil (contrairement à TruthOrDareSessionScreen) —
  /// simple indicateur du côté "répondre à une demande", pas une vraie
  /// pioche.
  bool _isResponseBlocked(String category) {
    final trailing = _myTrailingResponseStreak;
    if (trailing.category != category || trailing.streak < widget.game.consecutiveChoiceLimit - 1) return false;
    final other = category == 'verite' ? widget.box.questions.where((q) => q.isDefi) : widget.box.questions.where((q) => q.isVerite);
    return other.isNotEmpty;
  }

  Future<void> _answerTruthOrDareRequest(Send reply, String category) async {
    try {
      final updated = await GameService.instance.answerTruthOrDareRequest(reply.truthOrDareRequest!.id, category);
      GameCardInboxService.instance.removePending(reply.id);
      if (!mounted) return;
      setState(() {
        _replies = _replies.map((r) => r.id == updated.id ? updated : r).toList();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'enregistrer ta réponse. Réessaie dans un instant.")),
      );
    }
  }

  /// Le binôme a répondu — je pioche maintenant une carte DANS la
  /// catégorie qu'il/elle a choisie (voir TruthOrDareSessionScreen.
  /// lockedCategory, qui saute l'écran de choix habituel).
  Future<void> _openTruthOrDareFromRequest(Send reply) async {
    final category = reply.truthOrDareRequest?.chosenCategory;
    if (category == null) return;
    final result = await Navigator.of(context).push<Send>(
      MaterialPageRoute(
        builder: (_) => TruthOrDareSessionScreen(
          game: widget.game,
          box: widget.box,
          user: widget.user,
          excludeQuestionIds: _questionIdsAlreadyInThread,
          replyToSendId: widget.send.id,
          lockedCategory: category,
        ),
      ),
    );
    if (!mounted) return;
    _composeFocusNode.unfocus();
    if (result == null) return;
    if (!_replies.any((r) => r.id == result.id)) {
      setState(() => _replies = [..._replies, result]);
    }
    _scrollToBottom();
    _syncRepliesCacheSilently();
  }

  /// Repart de l'éventail de la même boîte pour en choisir et envoyer une
  /// autre — rejoint CETTE discussion comme un nouveau message (voir
  /// GameBoxSessionScreen._send/TruthOrDareSessionScreen._send,
  /// replyToSendId), jamais une nouvelle discussion séparée. Le gabarit
  /// poussé dépend du jeu : "Vérité ou Défi" ramène toujours sur l'écran de
  /// choix de catégorie, pas directement sur un éventail (voir
  /// Game.isTruthOrDare).
  Future<void> _sendAnotherCard() async {
    final trailing = _myTrailingCategoryStreak;
    final result = await Navigator.of(context).push<Send>(
      MaterialPageRoute(
        builder: (_) => widget.game.isTruthOrDare
            ? TruthOrDareSessionScreen(
                game: widget.game,
                box: widget.box,
                user: widget.user,
                excludeQuestionIds: _questionIdsAlreadyInThread,
                replyToSendId: widget.send.id,
                initialLastCategory: trailing.category,
                initialStreak: trailing.streak,
              )
            : GameBoxSessionScreen(
                game: widget.game,
                box: widget.box,
                user: widget.user,
                excludeQuestionIds: _questionIdsAlreadyInThread,
                replyToSendId: widget.send.id,
              ),
      ),
    );
    if (!mounted) return;
    // Voir demande utilisateur : "quand je clique pour envoyer le clavier
    // s'ouvre automatiquement et c'est gênant" — au retour de l'écran de
    // composition de la carte, Flutter redonnait le focus au champ de
    // texte de CETTE discussion (le seul encore focalisable), rouvrant le
    // clavier sans action volontaire de l'utilisateur.
    _composeFocusNode.unfocus();
    if (result == null) return;
    // Même protection que _sendPending/_onRealtimeEvent (SendCreated) : si
    // l'écho temps réel a déjà ajouté cette carte avant que cette réponse
    // HTTP ne revienne, l'ajouter une seconde fois dupliquait son id dans
    // [_replies] — deux bulles réutilisaient alors la MÊME GlobalKey (voir
    // _keyFor), ce qui faisait planter tout l'arbre de rendu ("Duplicate
    // GlobalKey detected in widget tree") et laissait l'écran entièrement
    // vide jusqu'à rouvrir la discussion (voir demande utilisateur).
    if (!_replies.any((r) => r.id == result.id)) {
      setState(() => _replies = [..._replies, result]);
    }
    _scrollToBottom();
    _syncRepliesCacheSilently();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    // La carte évolue en place (réponse/devinette/verdict, voir _rootSend) —
    // widget.send.gameCard reste figé sur l'état d'ouverture de l'écran.
    final card = _rootSend.gameCard;
    final partner = _partner;
    // Tirage stable pour toute la durée de vie de cet écran (seedé par
    // l'id du fil, pas re-tiré à chaque rebuild) — voir partnerDisplayName.
    final partnerName = partnerDisplayName(partner, widget.user.loveName, widget.send.id);
    final isOnline = _presentMemberIds.contains(_partnerId);
    final statusLabel = isOnline ? LocaleScope.of(context).t('presence_online') : _lastSeenLabel(context, partner?.lastSeenAt);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        // En-tête façon appli de messagerie : avatar + prénom du binôme,
        // pas le titre technique de la boîte — cette discussion EST
        // l'échange avec lui/elle, pas un simple libellé de carte.
        titleSpacing: 0,
        title: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: theme.primary.withValues(alpha: 0.15),
                  backgroundImage: partner?.avatar != null ? NetworkImage(partner!.avatar!) : null,
                  child: partner?.avatar == null
                      ? Text(partnerName.isNotEmpty ? partnerName[0] : '?', style: TextStyle(color: theme.primary))
                      : null,
                ),
                if (isOnline)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.greenAccent.shade400,
                        border: Border.all(color: theme.background, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    partnerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: theme.textOnBackground),
                  ),
                  Text(
                    statusLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.nunito(
                      fontSize: 11.5,
                      color: isOnline ? Colors.greenAccent.shade700 : theme.textOnBackgroundMuted,
                      fontWeight: isOnline ? FontWeight.w700 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_threadPollStats != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => showBlindPollMatchScoreboard(context, theme: theme, stats: _threadPollStats!),
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
                        const Text('💚', style: TextStyle(fontSize: 12)),
                        const SizedBox(width: 5),
                        Text(
                          '${_threadPollStats!.percentage.toStringAsFixed(0)}%',
                          style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: theme.textOnBackground),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.chevron_right_rounded, size: 14, color: theme.textOnBackgroundMuted),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: ThemedBackground(
        child: SafeArea(
          // Ferme la barre de réactions au tap sur un espace vide — un tap
          // sur le cercle/un émoji précis gagne l'arène de geste en premier
          // (recognizer le plus interne), donc ce onTap-ci ne se déclenche
          // QUE quand rien de plus spécifique n'a intercepté le tap ;
          // opaque nécessaire pour que les zones transparentes comptent
          // aussi comme "vide" cliquable. Même motif que SlideDetailScreen.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_reactionPickerOpenForSendId != null) setState(() => _reactionPickerOpenForSendId = null);
            },
            child: card == null
                ? EmptyState(icon: Icons.style_rounded, message: LocaleScope.of(context).t('game_card_not_found'))
                : Column(
                    children: [
                      Expanded(child: _buildMessageList(theme, card)),
                      Padding(
                        // Le Scaffold remonte déjà tout seul au-dessus du
                        // clavier (resizeToAvoidBottomInset, par défaut à
                        // true) — ajouter ENCORE viewInsets.bottom ici
                        // comptait la hauteur du clavier deux fois, laissant
                        // un grand vide entre la zone de texte et le clavier
                        // (voir capture utilisateur : "la zone de texte
                        // s'est décalée en haut").
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                        child: _buildComposer(theme),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList(ThemePalette theme, GameCardSend card) {
    final answer = _localAnswer ?? card.answer;

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      children: [
        // Séparateur de date pour la carte racine — premier message du fil,
        // toujours daté (voir demande utilisateur, capture de référence
        // WhatsApp : "Aujourd'hui"/"Hier"/nom du jour/date complète).
        _ThreadDateHeader(label: dateHeaderLabel(context, widget.send.createdAt), theme: theme),
        GestureDetector(
          // Clic-maintenu → menu "Répondre"/pensée/poème (voir
          // _showMessageActionsMenu) — disponible sur N'IMPORTE QUEL
          // message, y compris le sien propre (voir demande utilisateur).
          onLongPressStart: (details) => _showMessageActionsMenu(
            context,
            details.globalPosition,
            quoteText: card.questionTextFor(LocaleScope.of(context).current.code),
            quoteSendId: _rootSend.id,
            hideReply: card.isDefi,
          ),
          child: _GameCardMessageBubble(
            key: _keyFor(_rootSend.id),
            theme: theme,
            isMine: _isMine,
            question: card.questionTextFor(LocaleScope.of(context).current.code),
            boxTitle: card.gameBoxTitleFor(LocaleScope.of(context).current.code),
            imagePath: widget.box.imagePath,
            imageFocusX: widget.box.imageFocusX,
            imageFocusY: widget.box.imageFocusY,
            iconKey: widget.box.iconKey,
            time: widget.send.createdAt,
            tick: _isMine ? sendTickFor(_rootSend) : null,
            category: card.category,
            // Réaction accrochée au bord bas de LA carte concernée (voir
            // SlideDetailScreen._reactionOverlay, même motif) — set d'émojis
            // thématisé selon le jeu (voir _reactionEmojis).
            reactionOverlay: _reactionOverlay(theme, _rootSend),
          ),
        ),
        // Repliée derrière le cercle de réaction, juste au-dessus — même
        // principe que SlideDetailScreen._buildHeader.
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _reactionPickerOpenForSendId == _rootSend.id
              ? Padding(
                  padding: const EdgeInsets.only(top: 20, bottom: 4),
                  child: Align(
                    alignment: _isMine ? Alignment.centerRight : Alignment.centerLeft,
                    child: KeyedSubtree(
                      key: _reactionPanelKeyFor(_rootSend.id),
                      child: _reactionPanel(theme, _rootSend),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (answer != null) ...[
          const SizedBox(height: 6),
          // Clé posée sur la bulle de réponse elle-même (voir
          // _answerKeyFor/_scrollToAnswer), quel que soit le widget qui la
          // représente à cet instant — une seule des branches ci-dessous
          // est jamais montée en même temps pour une même carte.
          if (widget.game.isQuiz)
            // Réponse/devinette/verdict d'un jeu `session_type = 'quiz'` —
            // bulle de réponse SÉPARÉE de la carte (comme une réponse
            // WhatsApp), avec une citation de la question en tête, plutôt
            // que fondue dans la carte-photo elle-même.
            KeyedSubtree(key: _answerKeyFor(_rootSend.id), child: _buildQuizReplyBubble(theme, card))
          else if (widget.game.isBlindPoll)
            // Les deux réponses cachées sont réunies dès que `answer` est
            // renseigné (sender_answer, lui, est posé dès l'envoi, voir
            // GameCardController::send) — révélation automatique, jamais de
            // verdict à donner.
            KeyedSubtree(key: _answerKeyFor(_rootSend.id), child: _buildPollRevealBubble(theme, card))
          else if (card.isPollRevealed)
            // "Ai-je le droit ?"/"Sans Détour" : qui a envoyé la carte a été
            // invité·e (voir _inviteSenderToAnswer) et a répondu à son tour
            // — la citation de la question est greffée SUR la bulle de
            // révélation elle-même (voir _buildPollRevealBubble,
            // replyPreview) plutôt que sur une bulle de réponse séparée
            // laissée au-dessus (voir demande utilisateur : une seule
            // bulle, pas deux).
            KeyedSubtree(
              key: _answerKeyFor(_rootSend.id),
              child: _buildPollRevealBubble(
                theme,
                card,
                replyPreview: card.questionTextFor(LocaleScope.of(context).current.code),
                onReplyTap: () => _scrollToCard(_rootSend.id),
              ),
            )
          else if (widget.game.isYesNo || widget.game.isYesNoOnly)
            KeyedSubtree(
              key: _answerKeyFor(_rootSend.id),
              child: _ChatBubble(
              theme: theme,
              // La réponse "officielle" vient toujours de l'autre membre du
              // couple par rapport à qui a envoyé la question.
              isMine: !_isMine,
              text: answer,
              time: card.answeredAt ?? widget.send.createdAt,
              // Pas de suivi de lecture pour cette réponse historique (stockée
              // à part dans GameCardSend.answer, sans Send propre à elle) —
              // simple confirmation d'envoi.
              tick: !_isMine ? SendTick.sent : null,
              // Un Oui/Non seul ne dit pas à quelle carte il répond dès que
              // d'autres échanges se sont accumulés depuis (voir demande
              // utilisateur) — citation de la question, tappable pour y
              // remonter.
              replyPreview: card.questionTextFor(LocaleScope.of(context).current.code),
              onReplyTap: () => _scrollToCard(_rootSend.id),
              actionsMenu: _buildAnswerActionsMenu(theme, _rootSend),
              // Carte à gratter : je suis l'expéditeur·rice invité·e à
              // répondre à mon tour, sa réponse à elle/lui reste cachée
              // tant que je n'ai pas donné la mienne (voir demande
              // utilisateur) — jamais activé côté binôme, qui voit sa
              // propre réponse normalement.
              masked: _isMine && card.needsSenderAnswer,
              onLongPress: card.needsSenderAnswer && _isMine
                  ? null
                  : (pos) => _showMessageActionsMenu(context, pos, quoteText: answer, quoteSendId: _rootSend.id),
              ),
            )
          else if (widget.game.isTruthOrDare && card.isDefi)
            // Verdict d'une carte "défi" — même rendu qu'un Oui/Non (bulle
            // séparée avec citation de la question), voir
            // _buildDefiVerdictBar pour le picker qui l'a produit.
            KeyedSubtree(
              key: _answerKeyFor(_rootSend.id),
              child: _ChatBubble(
                theme: theme,
                isMine: !_isMine,
                text: answer,
                time: card.answeredAt ?? widget.send.createdAt,
                tick: !_isMine ? SendTick.sent : null,
                replyPreview: card.questionTextFor(LocaleScope.of(context).current.code),
                onReplyTap: () => _scrollToCard(_rootSend.id),
                onLongPress: (pos) => _showMessageActionsMenu(context, pos, quoteText: answer, quoteSendId: _rootSend.id),
              ),
            ),
          // Sinon (jeu à réponse libre "classique", ni Oui/Non ni quiz ni
          // Sondage Surprise) : la réponse est rendue plus bas, TOUJOURS en
          // fin de fil (voir la boucle _lateClassicAnswers en bas de cette
          // ListView) — jamais ici, juste après sa carte, pour ne jamais se
          // retrouver coincée entre deux cartes quand on répond à une carte
          // plus ancienne via le clic-maintenu (voir demande utilisateur).
          _buildInviteStatusLabel(theme, _rootSend),
          if (_isMine && card.needsSenderAnswer) ...[
            // Picker Oui/Non collé à CETTE carte pour MA réponse en tant
            // qu'expéditeur·rice invité·e (voir _inviteSenderToAnswer) —
            // là encore, plusieurs cartes peuvent m'attendre en même temps
            // (voir demande utilisateur), donc chacune garde son propre
            // picker plutôt qu'un seul partagé dans la barre de saisie.
            const SizedBox(height: 6),
            _buildSenderAnswerBar(theme, _rootSend),
          ],
        ] else if ((widget.game.isYesNo || widget.game.isYesNoOnly) && !_isMine) ...[
          // Picker Oui/Non collé à CETTE carte plutôt qu'un seul picker
          // partagé dans la barre de saisie (qui ne pouvait répondre qu'à
          // la carte la plus récente) — chaque carte non répondue garde
          // ainsi son propre moyen d'y répondre, même si d'autres cartes
          // ont été envoyées depuis (voir demande utilisateur).
          const SizedBox(height: 6),
          _buildYesNoAnswerBar(theme, _rootSend),
        ] else if (widget.game.isTruthOrDare && card.isDefi && !_isMine) ...[
          // Verdict Défi collé à CETTE carte, même principe que le picker
          // Oui/Non juste au-dessus (voir demande utilisateur).
          const SizedBox(height: 6),
          _buildDefiVerdictBar(theme, _rootSend),
        ] else if (widget.game.isBlindPoll && _isMine && card.senderAnswer != null) ...[
          // Ma propre réponse (déjà posée à l'envoi, voir
          // GameCardController::send) reste invisible pour mon binôme tant
          // qu'iel n'a pas répondu à son tour — mais MOI, je dois pouvoir la
          // revoir en attendant (voir demande utilisateur : "je dois
          // pouvoir voir ma propre réponse en attendant que mon binôme
          // réponde"), pas juste un silence total jusqu'à la révélation.
          const SizedBox(height: 6),
          _buildPollWaitingBubble(theme, card),
        ] else if (widget.game.isBlindPoll && !_isMine && card.senderAnswer != null) ...[
          // Picker collé à CETTE carte pour MA réponse en tant que
          // destinataire, même principe que le picker Oui/Non juste
          // au-dessus — sans ça, une deuxième carte reçue avant d'avoir
          // répondu à la première restait bloquée sans aucun moyen d'y
          // répondre (voir demande utilisateur).
          const SizedBox(height: 6),
          _buildBlindPollAnswerBar(theme, _rootSend),
        ],
        if (_loadingReplies)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        // Tout ce qui suit la carte racine, TRIÉ PAR HORODATAGE RÉEL (voir
        // _buildTimelineEntries) — plus une simple concaténation
        // cartes-puis-messages-puis-réponses-tardives : ça laissait une
        // réponse à une carte "classique" (voir _buildClassicAnswerBubble,
        // toujours rendue en dernier auparavant) passer AVANT un message
        // envoyé après elle (constaté en réel, voir demande utilisateur :
        // "le plus récent doit être en bas").
        // Un séparateur de date est inséré à chaque changement de jour (voir
        // dateHeaderLabel) — `lastDate` commence à la date de la carte
        // racine, déjà datée juste au-dessus.
        for (final entry in _timelineEntriesWithDateHeaders(theme)) ...[
          const SizedBox(height: 6),
          entry,
        ],
      ],
    );
  }

  /// Construit, TRIE PAR HORODATAGE et retourne tout ce qui suit la carte
  /// racine dans le fil : cartes relancées (avec leurs éléments propres —
  /// réaction, révélation, picker Oui/Non — regroupés dans le MÊME
  /// élément, horodaté par leur date d'ENVOI), réponses aux jeux
  /// "classiques" (racine ou relancée, horodatées par leur date de
  /// RÉPONSE), messages libres, et messages en attente d'envoi.
  List<_TimelineEntry> _buildTimelineEntries(ThemePalette theme) {
    final entries = <_TimelineEntry>[];
    final localeCode = LocaleScope.of(context).current.code;

    // Réponse à la carte racine, pour un jeu à texte libre "classique" —
    // seule celle-ci n'est jamais rendue inline juste après sa carte (voir
    // plus haut dans _buildMessageList), justement pour pouvoir la trier
    // ici avec le reste plutôt que la laisser figée en haut du fil.
    final rootCard = _rootSend.gameCard;
    if (rootCard != null &&
        rootCard.answer != null &&
        !widget.game.isYesNo &&
        !widget.game.isYesNoOnly &&
        !widget.game.isQuiz &&
        !widget.game.isBlindPoll &&
        !rootCard.isDefi) {
      entries.add(_TimelineEntry(
        rootCard.answeredAt ?? widget.send.createdAt,
        _buildClassicAnswerBubble(theme, _rootSend),
      ));
    }

    for (final reply in _replies) {
      // Une carte envoyée depuis cette discussion (voir _sendAnotherCard)
      // reste une carte visuellement, jamais une bulle de texte plate —
      // même widget que la carte d'origine.
      if (reply.isGameCard && reply.gameCard != null) {
        entries.add(_TimelineEntry(
          reply.createdAt,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onLongPressStart: (details) => _showMessageActionsMenu(
                  context,
                  details.globalPosition,
                  quoteText: reply.gameCard!.questionTextFor(localeCode),
                  quoteSendId: reply.id,
                  hideReply: reply.gameCard!.isDefi,
                ),
                child: _GameCardMessageBubble(
                  key: _keyFor(reply.id),
                  theme: theme,
                  isMine: reply.senderId == widget.user.id,
                  question: reply.gameCard!.questionTextFor(localeCode),
                  boxTitle: reply.gameCard!.gameBoxTitleFor(localeCode),
                  imagePath: widget.box.imagePath,
                  imageFocusX: widget.box.imageFocusX,
                  imageFocusY: widget.box.imageFocusY,
                  iconKey: widget.box.iconKey,
                  time: reply.createdAt,
                  tick: reply.senderId == widget.user.id ? sendTickFor(reply) : null,
                  category: reply.gameCard!.category,
                  // Chaque carte relancée a SA PROPRE réaction (voir
                  // _reactionOverlay) — avant, seule la carte racine pouvait
                  // en recevoir une, le cercle disparaissait purement et
                  // simplement dès la deuxième carte envoyée dans le fil.
                  reactionOverlay: _reactionOverlay(theme, reply),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _reactionPickerOpenForSendId == reply.id
                    ? Padding(
                        padding: const EdgeInsets.only(top: 20, bottom: 4),
                        child: Align(
                          alignment:
                              reply.senderId == widget.user.id ? Alignment.centerRight : Alignment.centerLeft,
                          child: KeyedSubtree(
                            key: _reactionPanelKeyFor(reply.id),
                            child: _reactionPanel(theme, reply),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              // Révélation de CETTE carte relancée — sans ça, seule la carte
              // racine affichait jamais "Vous êtes raccord/Chacun sa vibe" ;
              // une carte renvoyée via "envoyer une autre carte" (voir
              // _sendAnotherCard) restait juste une image de question, même
              // une fois les deux réponses réunies.
              if (widget.game.isBlindPoll && reply.gameCard!.isPollRevealed) ...[
                const SizedBox(height: 6),
                KeyedSubtree(key: _answerKeyFor(reply.id), child: _buildPollRevealBubble(theme, reply.gameCard!)),
              ] else if (widget.game.isBlindPoll &&
                  reply.senderId == widget.user.id &&
                  reply.gameCard!.senderAnswer != null) ...[
                // Même repli que pour la carte racine (voir
                // _buildPollWaitingBubble) : je dois voir ma propre réponse
                // sur CETTE carte relancée aussi, pas seulement la toute
                // première du fil.
                const SizedBox(height: 6),
                _buildPollWaitingBubble(theme, reply.gameCard!),
              ] else if (widget.game.isBlindPoll &&
                  reply.recipientId == widget.user.id &&
                  reply.gameCard!.senderAnswer != null) ...[
                // Picker collé à CETTE carte relancée pour MA réponse en
                // tant que destinataire, même principe que pour la racine
                // juste au-dessus.
                const SizedBox(height: 6),
                _buildBlindPollAnswerBar(theme, reply),
              ],
              // Réponse à CETTE carte relancée pour les jeux avec un
              // mécanisme dédié (Sondage Surprise déjà géré au-dessus,
              // "Ai-je le droit ?"/"Sans Détour" ci-dessous) — le quiz
              // garde son mécanisme actuel, scopé à la racine (guess/
              // verdict, non généralisé ici). Un jeu "classique" (texte
              // libre) n'a RIEN ici : sa réponse devient son propre élément
              // du fil, horodaté par sa date de réponse (voir plus bas).
              if (!widget.game.isQuiz && !widget.game.isBlindPoll && reply.gameCard!.answer != null) ...[
                if (reply.gameCard!.isPollRevealed) ...[
                  const SizedBox(height: 6),
                  // "Ai-je le droit ?"/"Sans Détour" : qui a envoyé CETTE
                  // carte relancée a été invité·e et a répondu à son tour —
                  // citation greffée sur la bulle de révélation elle-même,
                  // même principe que pour la racine.
                  KeyedSubtree(
                    key: _answerKeyFor(reply.id),
                    child: _buildPollRevealBubble(
                      theme,
                      reply.gameCard!,
                      replyPreview: reply.gameCard!.questionTextFor(localeCode),
                      onReplyTap: () => _scrollToCard(reply.id),
                    ),
                  ),
                ] else if (widget.game.isYesNo || widget.game.isYesNoOnly) ...[
                  const SizedBox(height: 6),
                  KeyedSubtree(
                    key: _answerKeyFor(reply.id),
                    child: _ChatBubble(
                      theme: theme,
                      isMine: reply.recipientId == widget.user.id,
                      text: reply.gameCard!.answer!,
                      time: reply.gameCard!.answeredAt ?? reply.createdAt,
                      tick: reply.recipientId == widget.user.id ? SendTick.sent : null,
                      replyPreview: reply.gameCard!.questionTextFor(localeCode),
                      onReplyTap: () => _scrollToCard(reply.id),
                      actionsMenu: _buildAnswerActionsMenu(theme, reply),
                      // Carte à gratter, même principe que pour la racine.
                      masked: reply.senderId == widget.user.id && reply.gameCard!.needsSenderAnswer,
                      onLongPress: reply.senderId == widget.user.id && reply.gameCard!.needsSenderAnswer
                          ? null
                          : (pos) => _showMessageActionsMenu(
                                context,
                                pos,
                                quoteText: reply.gameCard!.answer!,
                                quoteSendId: reply.id,
                              ),
                    ),
                  ),
                ] else if (widget.game.isTruthOrDare && reply.gameCard!.isDefi) ...[
                  // Verdict Défi de CETTE carte relancée, même rendu que
                  // pour la racine (voir plus haut).
                  const SizedBox(height: 6),
                  KeyedSubtree(
                    key: _answerKeyFor(reply.id),
                    child: _ChatBubble(
                      theme: theme,
                      isMine: reply.recipientId == widget.user.id,
                      text: reply.gameCard!.answer!,
                      time: reply.gameCard!.answeredAt ?? reply.createdAt,
                      tick: reply.recipientId == widget.user.id ? SendTick.sent : null,
                      replyPreview: reply.gameCard!.questionTextFor(localeCode),
                      onReplyTap: () => _scrollToCard(reply.id),
                      onLongPress: (pos) => _showMessageActionsMenu(
                        context,
                        pos,
                        quoteText: reply.gameCard!.answer!,
                        quoteSendId: reply.id,
                      ),
                    ),
                  ),
                ],
                _buildInviteStatusLabel(theme, reply),
                if (reply.senderId == widget.user.id && reply.gameCard!.needsSenderAnswer) ...[
                  // Picker Oui/Non pour MA réponse en tant qu'expéditeur·rice
                  // invité·e sur CETTE carte relancée, même principe que
                  // pour la racine juste au-dessus.
                  const SizedBox(height: 6),
                  _buildSenderAnswerBar(theme, reply),
                ],
              ] else if ((widget.game.isYesNo || widget.game.isYesNoOnly) && reply.recipientId == widget.user.id) ...[
                // Picker Oui/Non collé à CETTE carte relancée, même principe
                // que pour la racine — sans ça, une carte relancée non
                // répondue restait bloquée dès qu'une carte plus récente
                // captait le seul picker partagé (voir demande utilisateur).
                const SizedBox(height: 6),
                _buildYesNoAnswerBar(theme, reply),
              ] else if (widget.game.isTruthOrDare && reply.gameCard!.isDefi && reply.recipientId == widget.user.id) ...[
                // Verdict Défi collé à CETTE carte relancée, même principe
                // que pour la racine.
                const SizedBox(height: 6),
                _buildDefiVerdictBar(theme, reply),
              ],
            ],
          ),
        ));

        // Réponse "classique" (texte libre) à CETTE carte relancée — son
        // propre élément du fil, horodaté par sa date de réponse plutôt
        // que rattaché à la position de sa carte (voir demande
        // utilisateur).
        final replyCard = reply.gameCard!;
        if (replyCard.answer != null &&
            !replyCard.isPollRevealed &&
            !widget.game.isYesNo &&
            !widget.game.isYesNoOnly &&
            !widget.game.isQuiz &&
            !widget.game.isBlindPoll &&
            !replyCard.isDefi) {
          entries.add(_TimelineEntry(
            replyCard.answeredAt ?? reply.createdAt,
            _buildClassicAnswerBubble(theme, reply),
          ));
        }
      } else if (reply.isHeartbeat) {
        // Design propre à une pensée (voir demande utilisateur) — la VRAIE
        // carte (HeartbeatCard, déjà utilisée dans le Carnet de bord et sa
        // modale de réponse), pas un texte plat avec une icône devant.
        // Même principe que les cartes-questions/poèmes envoyés depuis
        // cette discussion : un battement de cœur reste une carte
        // visuellement, jamais une bulle de chat classique.
        final messageText = reply.heartbeatMessageFor(localeCode) ?? LocaleScope.of(context).t('heartbeat_default_message');
        entries.add(_TimelineEntry(
          reply.createdAt,
          _buildHeartbeatBubble(theme, reply, messageText),
        ));
      } else if (reply.isPack && reply.pack != null) {
        // Même principe que le battement de cœur juste au-dessus (voir
        // demande utilisateur) — la VRAIE carte-poème (feuilletable, voir
        // SlidePackViewer/showPackReplyModal), pas un texte plat avec juste
        // le titre du pack.
        entries.add(_TimelineEntry(
          reply.createdAt,
          _PoemReplyBubble(
            theme: theme,
            reply: reply,
            isMine: reply.senderId == widget.user.id,
            onLongPress: (pos) => _showMessageActionsMenu(
              context,
              pos,
              quoteText: reply.pack!.titleFor(localeCode),
              quoteSendId: reply.id,
            ),
          ),
        ));
      } else if (reply.isTruthOrDareRequest && reply.truthOrDareRequest != null) {
        entries.add(_TimelineEntry(
          reply.createdAt,
          _buildTruthOrDareRequestBubble(theme, reply),
        ));
      } else {
        // Un message de chat normal peut lui-même être une réponse citée
        // (voir _encodeQuoted/_showMessageActionsMenu) — décodé ici pour
        // affichage, jamais stocké décodé.
        final decoded = _decodeQuoted(_replyText(reply));
        entries.add(_TimelineEntry(
          reply.createdAt,
          KeyedSubtree(
            key: _messageKeyFor(reply.id),
            child: _ChatBubble(
              theme: theme,
              isMine: reply.senderId == widget.user.id,
              text: decoded.text,
              time: reply.createdAt,
              tick: reply.senderId == widget.user.id ? sendTickFor(reply) : null,
              replyPreview: decoded.quote,
              // Citation tappable pour remonter au message cité (voir
              // _scrollToQuoted) — quoteId reste `null` pour un message
              // envoyé AVANT l'ajout de ce lien (voir _decodeQuoted), pas
              // de lien plutôt que de planter dans ce cas.
              onReplyTap: decoded.quoteId == null ? null : () => _scrollToQuoted(decoded.quoteId!),
              onLongPress: (pos) =>
                  _showMessageActionsMenu(context, pos, quoteText: decoded.text, quoteSendId: reply.id),
            ),
          ),
        ));
      }
    }

    for (final pending in _pending) {
      final decoded = _decodeQuoted(pending.text);
      entries.add(_TimelineEntry(
        pending.time,
        _ChatBubble(
          theme: theme,
          isMine: true,
          text: decoded.text,
          time: pending.time,
          tick: pending.failed ? SendTick.failed : SendTick.sending,
          onRetry: pending.failed ? () => _sendPending(pending) : null,
          replyPreview: decoded.quote,
          // Le message cité (s'il y en a un) a déjà un id stable, même si
          // CE message-ci (encore en attente, voir _PendingText) n'en a pas
          // lui-même — le lien "remonter à" fonctionne donc dès l'affichage
          // optimiste, pas seulement une fois confirmé.
          onReplyTap: decoded.quoteId == null ? null : () => _scrollToQuoted(decoded.quoteId!),
          // Pas encore d'id serveur stable pour CE message — citation
          // possible, mais personne ne peut encore "remonter à" lui tant
          // que l'envoi n'est pas confirmé (voir onLongPress sans
          // quoteSendId).
          onLongPress: (pos) => _showMessageActionsMenu(context, pos, quoteText: decoded.text),
        ),
      ));
    }

    // Tri stable (index en départage) — List.sort() n'est pas garanti
    // stable, deux éléments à la même milliseconde ne doivent pas pour
    // autant échanger leur ordre à chaque rebuild.
    final indexed = entries.asMap().entries.toList()
      ..sort((a, b) {
        final byTime = a.value.time.compareTo(b.value.time);
        return byTime != 0 ? byTime : a.key.compareTo(b.key);
      });
    return indexed.map((e) => e.value).toList();
  }

  /// Insère un _ThreadDateHeader entre deux entrées de jours différents (et
  /// avant la première si elle tombe un autre jour que la carte racine,
  /// déjà datée juste au-dessus dans _buildMessageList) — voir
  /// dateHeaderLabel/demande utilisateur, capture de référence WhatsApp.
  List<Widget> _timelineEntriesWithDateHeaders(ThemePalette theme) {
    final widgets = <Widget>[];
    var lastDate = DateTime(widget.send.createdAt.year, widget.send.createdAt.month, widget.send.createdAt.day);
    for (final entry in _buildTimelineEntries(theme)) {
      final entryDate = DateTime(entry.time.year, entry.time.month, entry.time.day);
      if (entryDate != lastDate) {
        widgets.add(_ThreadDateHeader(label: dateHeaderLabel(context, entry.time), theme: theme));
        lastDate = entryDate;
      }
      widgets.add(entry.widget);
    }
    return widgets;
  }

  Widget _buildClassicAnswerBubble(ThemePalette theme, Send target) {
    final card = target.gameCard!;
    final isMine = target.recipientId == widget.user.id;
    return KeyedSubtree(
      key: _answerKeyFor(target.id),
      child: _ChatBubble(
        theme: theme,
        isMine: isMine,
        text: card.answer!,
        time: card.answeredAt ?? target.createdAt,
        tick: isMine ? SendTick.sent : null,
        // Un texte seul ne dit pas à quelle carte il répond dès que
        // d'autres échanges se sont accumulés depuis — citation de la
        // question, tappable pour y remonter (même motif que les autres
        // types de réponse, voir _buildPollRevealBubble/_buildQuizReplyBubble).
        replyPreview: card.questionTextFor(LocaleScope.of(context).current.code),
        onReplyTap: () => _scrollToCard(target.id),
        onLongPress: (pos) => _showMessageActionsMenu(context, pos, quoteText: card.answer!, quoteSendId: target.id),
      ),
    );
  }

  /// Une pensée envoyée depuis cette discussion — la VRAIE carte
  /// (HeartbeatCard, voir SlideDetailScreen/showHeartbeatReplyModal), pas
  /// une bulle de chat classique (voir demande utilisateur). Taille fixe
  /// pour la variante avec photo (remplit tout le cadre en BoxFit.cover,
  /// a besoin de bornes) ; la variante texte seul se dimensionne à son
  /// contenu, la forcer casserait sa mise en page interne.
  Widget _buildHeartbeatBubble(ThemePalette theme, Send reply, String messageText) {
    final isMine = reply.senderId == widget.user.id;
    final hasFamilyImage = HeartbeatCard.usesFamilyImage(reply.heartbeatFamily, reply.heartbeatImages);
    final hasImages = reply.heartbeatImages.isNotEmpty || hasFamilyImage;
    // Cette bulle ne fait que 210px de large — le texte manuscrit par
    // défaut (HeartbeatCard) est pensé pour une carte pleine largeur et y
    // débordait/paraissait démesuré (voir demande utilisateur, même
    // correctif que _PoemReplyBubble pour les cartes-poèmes).
    final card = hasImages
        ? SizedBox(
            width: 210,
            child: AspectRatio(
              aspectRatio: hasFamilyImage ? 4 / 5 : 3 / 4,
              child: HeartbeatCard(
                images: reply.heartbeatImages,
                message: messageText,
                theme: theme,
                family: reply.heartbeatFamily,
                senderGender: reply.sender?.gender,
                scale: 0.6,
              ),
            ),
          )
        : ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: HeartbeatCard(images: const [], message: messageText, theme: theme, scale: 0.6),
          );

    // Heure + accusé de lecture posés DIRECTEMENT sur la carte (coin bas
    // droit, pastille sombre), pas comme un élément séparé en dessous — un
    // Align/Row sous une carte de largeur variable pouvait finir visuellement
    // détaché du bord de la carte (voir demande utilisateur : "il y a des
    // heures qui se baladent"). Même traitement, garanti fiable, que
    // _GameCardMessageBubble.
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => showHeartbeatReplyModal(
          context,
          images: reply.heartbeatImages,
          message: messageText,
          family: reply.heartbeatFamily,
          senderGender: reply.sender?.gender,
        ),
        onLongPressStart: (details) =>
            _showMessageActionsMenu(context, details.globalPosition, quoteText: messageText, quoteSendId: reply.id),
        child: Stack(
          children: [
            card,
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${reply.createdAt.toLocal().hour.toString().padLeft(2, '0')}:${reply.createdAt.toLocal().minute.toString().padLeft(2, '0')}',
                      style: GoogleFonts.nunito(fontSize: 10.5, color: Colors.white),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 4),
                      SendTickIcon(tick: sendTickFor(reply), color: Colors.white, onRetry: null),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Bulle "demande Vérité ou Défi" (voir TruthOrDareRequest) — trois états
  /// visuels possibles : en attente côté auteur·e de la demande, à répondre
  /// côté destinataire (boutons, verrouillés par [_isResponseBlocked]), ou
  /// répondue (avec une pioche "Choisir une carte" côté auteur·e une fois la
  /// catégorie connue).
  Widget _buildTruthOrDareRequestBubble(ThemePalette theme, Send reply) {
    final req = reply.truthOrDareRequest!;
    final isMine = reply.senderId == widget.user.id; // j'ai envoyé la demande
    final iMustAnswer = !isMine && req.isPending;

    Widget body;
    if (req.isPending) {
      body = iMustAnswer
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${reply.sender?.prenom ?? "Ton binôme"} te demande de choisir :',
                  style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: theme.textOnBackground),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildTruthOrDareAnswerButton(theme, reply, 'verite', veriteColor, 'Vérité')),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTruthOrDareAnswerButton(theme, reply, 'defi', defiColor, 'Défi')),
                  ],
                ),
              ],
            )
          : Text(
              'En attente du choix de ${reply.recipient?.prenom ?? "ton binôme"}...',
              style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
            );
    } else {
      final categoryLabel = req.isDefi ? 'Défi' : 'Vérité';
      final categoryColor = req.isDefi ? defiColor : veriteColor;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 16, color: categoryColor),
              const SizedBox(width: 6),
              Text(
                isMine
                    ? '${reply.recipient?.prenom ?? "Ton binôme"} a choisi : $categoryLabel'
                    : 'Tu as choisi : $categoryLabel',
                style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: theme.textOnBackground),
              ),
            ],
          ),
          // Voir demande utilisateur : "il clique sur défi et choisit une
          // carte et m'envoie" — seul l'auteur·e de la demande pioche la
          // carte ; rien à faire côté destinataire une fois répondu.
          if (isMine) ...[
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () => _openTruthOrDareFromRequest(reply),
              icon: const Icon(Icons.style_rounded, size: 18),
              label: const Text('Choisir une carte'),
              style: ElevatedButton.styleFrom(backgroundColor: categoryColor, foregroundColor: Colors.white),
            ),
          ],
        ],
      );
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.primary.withValues(alpha: 0.2)),
        ),
        child: body,
      ),
    );
  }

  Widget _buildTruthOrDareAnswerButton(ThemePalette theme, Send reply, String category, Color color, String label) {
    final blocked = _isResponseBlocked(category);
    return OutlinedButton(
      onPressed: blocked ? null : () => _answerTruthOrDareRequest(reply, category),
      style: OutlinedButton.styleFrom(
        foregroundColor: blocked ? theme.textOnBackgroundMuted : color,
        side: BorderSide(color: blocked ? theme.textOnBackgroundMuted.withValues(alpha: 0.3) : color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (blocked) ...[
            Icon(Icons.lock_outline_rounded, size: 14, color: theme.textOnBackgroundMuted),
            const SizedBox(width: 4),
          ],
          Text(label),
        ],
      ),
    );
  }

  /// Couleur de contenu lisible sur la bulle — blanc sur le dégradé côté
  /// "moi", couleur de texte normale côté surface, même principe que
  /// EmojiStorySessionScreen._StoryBubbleState._onColor.
  Color _quizOnColor(ThemePalette theme, bool mine) {
    if (!mine) return theme.textOnBackground;
    return theme.primary.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
  }

  /// Petit bloc imbriqué DANS la bulle de réponse — façon citation de
  /// message (WhatsApp/Telegram) : fine bordure gauche + fond légèrement
  /// teinté, toujours dans la même famille de couleur que la bulle. Copie
  /// conforme de EmojiStorySessionScreen._StoryBubbleState._replyBlock.
  Widget _quoteBlock({required Color onColor, required String label, required Widget content}) {
    final labelColor = onColor.withValues(alpha: 0.7);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
      decoration: BoxDecoration(
        color: onColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: onColor.withValues(alpha: 0.35), width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: labelColor)),
          const SizedBox(height: 2),
          DefaultTextStyle(style: GoogleFonts.nunito(fontSize: 13, color: onColor), child: content),
        ],
      ),
    );
  }

  /// Bulle de réponse pour une carte d'un jeu `session_type = 'quiz'` (voir
  /// Game.isQuiz) — une vraie bulle de chat séparée de la carte-photo de la
  /// question (comme une réponse WhatsApp), directement sous elle : pas de
  /// rappel de la question ici (déjà visible juste au-dessus, dans la
  /// carte) — juste l'historique des devinettes (voir _quoteBlock, une
  /// citation par tentative pour distinguer qui a dit quoi) puis l'action
  /// en cours (boutons de verdict/attente/nouvelle tentative/résultat
  /// final) en clair. Copie simplifiée du motif construit pour
  /// EmojiStorySessionScreen._StoryBubble (sans édition/suppression de
  /// devinette, non demandées ici).
  Widget _buildQuizReplyBubble(ThemePalette theme, GameCardSend card) {
    final mine = _isMine;
    final onColor = _quizOnColor(theme, mine);
    final mutedColor = onColor.withValues(alpha: 0.7);
    final t = LocaleScope.of(context).t;
    final partnerName = _partner?.prenom ?? _partner?.name ?? t('game_partner_name_fallback');
    // Qui devine (toujours le/la destinataire de la carte) vs qui rend
    // verdict (toujours qui a envoyé la carte) — déduit de mon propre rôle.
    final guesserName = mine ? partnerName : t('common_you');
    final composerName = mine ? t('common_you') : partnerName;

    final blocks = <Widget>[];

    for (final g in card.guesses) {
      if (g.isCorrect == null) continue;
      blocks.add(_quoteBlock(
        onColor: onColor,
        label: guesserName,
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(g.isCorrect! ? Icons.check_rounded : Icons.close_rounded, size: 14, color: g.isCorrect! ? onColor : mutedColor),
            const SizedBox(width: 5),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    if (!g.isCorrect!) TextSpan(text: t('game_quiz_missed_prefix')),
                    TextSpan(text: g.guess),
                  ],
                ),
                style: TextStyle(color: g.isCorrect! ? onColor : mutedColor, decoration: g.isCorrect! ? null : TextDecoration.lineThrough),
              ),
            ),
          ],
        ),
      ));
      if (g.reveal != null && g.reveal!.isNotEmpty) {
        blocks.add(_quoteBlock(
          onColor: onColor,
          label: composerName,
          content: Text(g.reveal!, style: const TextStyle(fontStyle: FontStyle.italic)),
        ));
      }
    }

    // La devinette en attente de verdict — sans ça, seuls le statut/les
    // boutons de verdict apparaissaient, sans jamais montrer CE qui a été
    // deviné (bug initial : la boucle ci-dessus ignore volontairement les
    // devinettes pas encore tranchées, voir `if (g.isCorrect == null)`).
    if (card.needsVerdict) {
      final pending = card.latestGuess!;
      blocks.add(_quoteBlock(
        onColor: onColor,
        label: guesserName,
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_empty_rounded, size: 14, color: mutedColor),
            const SizedBox(width: 5),
            Flexible(child: Text(pending.guess)),
          ],
        ),
      ));
    }

    if (card.isResolved) {
      final won = card.won == true;
      blocks.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(won ? Icons.emoji_events_rounded : Icons.sentiment_dissatisfied_rounded, size: 16, color: onColor),
          const SizedBox(width: 6),
          Text(
            won ? t('game_quiz_guessed_correct') : t('game_quiz_guessed_wrong'),
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 12.5, color: onColor),
          ),
        ],
      ));
    } else if (card.needsVerdict && mine) {
      blocks.add(_buildVerdictButtons(theme, card));
    } else if (card.needsVerdict) {
      blocks.add(Text(
        t('game_quiz_awaiting_verdict', {'name': composerName}),
        style: GoogleFonts.nunito(fontSize: 12.5, fontStyle: FontStyle.italic, color: mutedColor),
      ));
    } else if (card.needsGuess && !mine && card.guesses.isNotEmpty) {
      blocks.add(_buildRetryGuessField(theme));
    } else if (card.needsGuess && card.guesses.isNotEmpty) {
      blocks.add(Text(
        t('game_quiz_awaiting_guess', {'name': guesserName}),
        style: GoogleFonts.nunito(fontSize: 12.5, fontStyle: FontStyle.italic, color: mutedColor),
      ));
    }

    return _QuizReplyBubble(
      theme: theme,
      isMine: mine,
      time: card.answeredAt ?? widget.send.createdAt,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: blocks),
    );
  }

  /// Boutons de verdict — visibles uniquement pour qui a posé la question
  /// (voir GameCardController::verdict, expéditeur uniquement).
  Widget _buildVerdictButtons(ThemePalette theme, GameCardSend card) {
    final t = LocaleScope.of(context).t;
    return Row(
      children: [
        Expanded(
          child: _QuizActionButton(
            label: t('game_quiz_correct'),
            color: Colors.green,
            filled: true,
            loading: _submittingVerdict,
            onTap: _submittingVerdict ? null : () => _submitVerdict(card, correct: true),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _QuizActionButton(
            label: t('game_quiz_retry'),
            color: theme.primary,
            filled: false,
            loading: _submittingVerdict,
            onTap: _submittingVerdict ? null : () => _submitVerdict(card, correct: false, retry: true),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _QuizActionButton(
            label: t('game_quiz_not_found'),
            color: theme.textOnBackgroundMuted,
            filled: false,
            loading: _submittingVerdict,
            onTap: _submittingVerdict ? null : () => _submitVerdict(card, correct: false, retry: false),
          ),
        ),
      ],
    );
  }

  /// Champ de devinette pour une nouvelle chance — la toute première
  /// devinette passe par le champ de saisie principal (voir
  /// _pendingSpecialAnswerSend), celui-ci ne sert qu'aux tentatives suivantes.
  Widget _buildRetryGuessField(ThemePalette theme) {
    final t = LocaleScope.of(context).t;
    if (!_retryGuessing) {
      return Align(
        alignment: Alignment.centerLeft,
        child: _QuizActionButton(
          label: t('game_quiz_guess_again'),
          icon: Icons.psychology_alt_rounded,
          color: theme.primary,
          filled: true,
          onTap: () => setState(() => _retryGuessing = true),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _retryGuessController,
          autofocus: true,
          maxLines: 3,
          style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackground),
          cursorColor: theme.primary,
          decoration: InputDecoration(
            filled: true,
            fillColor: theme.surface,
            hintText: t('game_quiz_guess_hint'),
            hintStyle: GoogleFonts.nunito(fontSize: 12.5, color: theme.textOnBackgroundMuted),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
        const SizedBox(height: 8),
        _QuizActionButton(
          label: t('game_quiz_send_guess'),
          color: theme.primary,
          filled: true,
          loading: _submittingGuess,
          onTap: _submittingGuess ? null : _submitRetryGuess,
        ),
      ],
    );
  }

  Future<void> _submitVerdict(GameCardSend card, {required bool correct, bool? retry}) async {
    setState(() => _submittingVerdict = true);
    try {
      final updated = await GameService.instance.submitCardVerdict(card.id, correct: correct, retry: retry);
      if (!mounted) return;
      setState(() => _rootSend = updated);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submittingVerdict = false);
    }
  }

  Future<void> _submitRetryGuess() async {
    final card = _rootSend.gameCard;
    final text = _retryGuessController.text.trim();
    if (card == null || text.isEmpty || _submittingGuess) return;
    setState(() => _submittingGuess = true);
    try {
      final updated = await GameService.instance.guessCard(card.id, text);
      if (!mounted) return;
      _retryGuessController.clear();
      setState(() {
        _rootSend = updated;
        _retryGuessing = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submittingGuess = false);
    }
  }

  /// Boutons de choix collés SOUS [target] elle-même dans le fil (voir
  /// _buildMessageList) tant qu'elle attend ma réponse — chaque carte non
  /// répondue garde son propre picker, même principe que
  /// _buildYesNoAnswerBar (voir demande utilisateur : plusieurs cartes de
  /// ce jeu peuvent attendre ma réponse en même temps dans la même
  /// discussion).
  Widget _buildBlindPollAnswerBar(ThemePalette theme, Send target) {
    final card = target.gameCard!;
    final loading = _submittingBlindAnswer == target.id;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            LocaleScope.of(context).t('game_blind_poll_your_turn'),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: theme.textOnBackground),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in card.options)
                _QuizActionButton(
                  label: option,
                  color: theme.primary,
                  filled: false,
                  loading: loading,
                  onTap: _submittingBlindAnswer != null ? null : () => _submitBlindPollAnswer(target, option),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Boutons Oui/Non affichés EN LIGNE, juste sous [target] elle-même dans
  /// le fil (voir _buildMessageList), tant que sa toute première réponse
  /// n'est pas encore envoyée — un jeu `session_type = 'yes_no'`/
  /// `'yes_no_only'` ("Ai-je le droit ?"/"Sans Détour") peut avoir
  /// PLUSIEURS cartes sans réponse en même temps dans le même fil (racine +
  /// relances), donc chacune garde SON PROPRE picker plutôt qu'un picker
  /// unique dans la barre de saisie qui ne pouvait répondre qu'à la carte
  /// la plus récente (voir demande utilisateur). Contrairement au Sondage
  /// Surprise, ce n'est pas la réponse finale pour `yes_no` : le champ de
  /// texte libre habituel de la barre de saisie reste toujours disponible
  /// pour expliquer le pourquoi, indépendamment de ce picker.
  Widget _buildYesNoAnswerBar(ThemePalette theme, Send target) {
    final t = LocaleScope.of(context).t;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _QuizActionButton(
              label: t('game_answer_yes'),
              color: theme.primary,
              filled: true,
              loading: _submittingYesNoChoice == '${target.id}|Oui',
              onTap: _submitting ? null : () => _submitYesNoAnswer(target, 'Oui'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuizActionButton(
              label: t('game_answer_no'),
              color: theme.primary,
              filled: false,
              loading: _submittingYesNoChoice == '${target.id}|Non',
              onTap: _submitting ? null : () => _submitYesNoAnswer(target, 'Non'),
            ),
          ),
        ],
      ),
    );
  }

  /// Verdict d'une carte "défi" de "Vérité ou Défi" (voir Game.isTruthOrDare/
  /// GameCardSend.isDefi) — un champ de texte libre n'a pas de sens ici,
  /// seul un verdict binaire compte (voir demande utilisateur, comme
  /// _buildYesNoAnswerBar : collé EN LIGNE sous [target] plutôt qu'un
  /// picker unique dans la barre de saisie, plusieurs cartes défi pouvant
  /// attendre un verdict en même temps).
  Widget _buildDefiVerdictBar(ThemePalette theme, Send target) {
    final t = LocaleScope.of(context).t;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _QuizActionButton(
              label: t('truth_or_dare_dare_completed'),
              color: theme.primary,
              filled: true,
              loading: _submittingDefiVerdict == '${target.id}|${t('truth_or_dare_dare_completed')}',
              onTap: _submitting
                  ? null
                  : () => _submitDefiVerdict(target, t('truth_or_dare_dare_completed')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuizActionButton(
              label: t('truth_or_dare_dare_dodged'),
              color: theme.primary,
              filled: false,
              loading: _submittingDefiVerdict == '${target.id}|${t('truth_or_dare_dare_dodged')}',
              onTap: _submitting
                  ? null
                  : () => _submitDefiVerdict(target, t('truth_or_dare_dare_dodged')),
            ),
          ),
        ],
      ),
    );
  }

  /// Boutons Oui/Non pour MA propre réponse, une fois invité·e par mon
  /// binôme à répondre à la même question que lui/elle (voir
  /// GameCardSend.needsSenderAnswer) — affiché EN LIGNE sous [target]
  /// (voir _buildMessageList, même principe que _buildYesNoAnswerBar :
  /// chaque carte qui m'attend garde son propre picker), visuellement
  /// identique à _buildYesNoAnswerBar mais pose sender_answer via
  /// _submitSenderAnswer plutôt que answer.
  Widget _buildSenderAnswerBar(ThemePalette theme, Send target) {
    final t = LocaleScope.of(context).t;
    final partnerName = _partner?.prenom ?? t('game_partner_name_fallback');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('game_sender_answer_prompt', {'partner': partnerName}),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: theme.textOnBackground),
          ),
          const SizedBox(height: 4),
          Text(
            t('game_sender_answer_subtitle'),
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _QuizActionButton(
                  label: t('game_answer_yes'),
                  color: theme.primary,
                  filled: true,
                  loading: _submittingSenderAnswerKey == '${target.id}|Oui',
                  onTap: _submittingSenderAnswerKey != null ? null : () => _submitSenderAnswer(target, 'Oui'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuizActionButton(
                  label: t('game_answer_no'),
                  color: theme.primary,
                  filled: false,
                  loading: _submittingSenderAnswerKey == '${target.id}|Non',
                  onTap: _submittingSenderAnswerKey != null ? null : () => _submitSenderAnswer(target, 'Non'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Rappel permanent — pas juste un snackbar qui disparaît — tant que
  /// l'invitation lancée est encore sans réponse (voir
  /// _inviteSenderToAnswer) : sans ça, rien n'indiquait plus qu'une
  /// invitation avait bien été envoyée une fois le snackbar initial
  /// disparu (voir demande utilisateur). Visible UNIQUEMENT côté qui a
  /// invité (le/la destinataire de [cardSend]) — qui a envoyé la carte a
  /// déjà son propre rappel permanent, le picker Oui/Non affiché en ligne
  /// sous SA carte tant qu'il/elle n'a pas répondu (voir
  /// _buildSenderAnswerBar).
  Widget _buildInviteStatusLabel(ThemePalette theme, Send cardSend) {
    final card = cardSend.gameCard;
    if (card == null || card.senderInvitedAt == null || card.senderAnswer != null) return const SizedBox.shrink();
    if (cardSend.recipientId != widget.user.id) return const SizedBox.shrink();

    final partnerName = _partner?.prenom ?? LocaleScope.of(context).t('game_partner_name_fallback');
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_top_rounded, size: 12, color: theme.textOnBackgroundMuted),
            const SizedBox(width: 4),
            // Flexible + ellipsis : un prénom (ou une traduction) trop long
            // débordait sinon hors de l'écran (Row sans limite de largeur,
            // voir demande utilisateur) — se tronque proprement à la place.
            Flexible(
              child: Text(
                LocaleScope.of(context).t('game_invite_waiting_label', {'partner': partnerName}),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.nunito(fontSize: 11, fontStyle: FontStyle.italic, color: theme.textOnBackgroundMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Petit menu accroché à l'icône sur une bulle de réponse Oui/Non
  /// ("Ai-je le droit ?"/"Sans Détour" uniquement, voir Game.isYesNo/
  /// isYesNoOnly) : inviter le binôme à répondre à SA/SON tour à la même
  /// question (voir _inviteSenderToAnswer) — visible UNIQUEMENT pour qui a
  /// répondu (le/la destinataire de [cardSend]), jamais pour qui a envoyé
  /// la carte, voir demande utilisateur — plus les 3 raccourcis habituels
  /// (nouvelle carte/poème/battement de cœur, mêmes actions que
  /// _buildComposerActionsRow).
  Widget _buildAnswerActionsMenu(ThemePalette theme, Send cardSend) {
    final t = LocaleScope.of(context).t;
    final card = cardSend.gameCard!;
    final answeredByMe = cardSend.recipientId == widget.user.id;
    // Une fois envoyée (ou en cours d'envoi), l'entrée reste visible plutôt
    // que de disparaître — grisée, et un tap dessus rappelle qu'elle a déjà
    // été envoyée au lieu de la renvoyer silencieusement (voir demande
    // utilisateur : avant, l'entrée disparaissait purement et simplement,
    // sans plus aucun moyen de vérifier qu'elle avait bien été envoyée).
    final alreadyInvited = card.senderInvitedAt != null || _invitingSenderForSendId == cardSend.id;
    // Le bouton flotte maintenant dans un petit cercle theme.surface au
    // coin de la bulle (voir _ChatBubble) — toujours sur ce même fond
    // neutre, quel que soit le dégradé de la bulle en dessous, donc plus
    // besoin de bascule blanc/gris selon [answeredByMe] comme avant (un
    // icône blanc y devenait invisible, voir demande utilisateur : "revoir").
    final iconColor = theme.primary;
    final partnerName = _partner?.prenom ?? t('game_partner_name_fallback');
    final invitedColor = theme.textOnBackgroundMuted.withValues(alpha: 0.5);

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, size: 14, color: iconColor),
      padding: EdgeInsets.zero,
      color: theme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (value) {
        switch (value) {
          case 'invite':
            if (alreadyInvited) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t('game_invite_already_sent', {'partner': partnerName}))),
              );
            } else {
              _inviteSenderToAnswer(cardSend);
            }
            break;
          case 'new_card':
            _sendAnotherCard();
            break;
          case 'poem':
            _reply();
            break;
          case 'heartbeat':
            _openHeartbeatReplyOptions();
            break;
        }
      },
      itemBuilder: (context) => [
        if (answeredByMe)
          PopupMenuItem(
            value: 'invite',
            child: Row(
              children: [
                Icon(Icons.campaign_rounded, size: 18, color: alreadyInvited ? invitedColor : theme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t('game_invite_to_answer', {'partner': partnerName}),
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      color: alreadyInvited ? invitedColor : theme.textOnBackground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'new_card',
          child: Row(
            children: [
              Icon(Icons.style_rounded, size: 18, color: theme.primary),
              const SizedBox(width: 10),
              Text(t('game_action_send_new_card'), style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackground)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'poem',
          child: Row(
            children: [
              Icon(Icons.auto_stories_rounded, size: 18, color: theme.primary),
              const SizedBox(width: 10),
              Text(t('game_action_send_poem'), style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackground)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'heartbeat',
          child: Row(
            children: [
              Icon(Icons.favorite_rounded, size: 18, color: theme.primary),
              const SizedBox(width: 10),
              Text(t('game_action_send_heartbeat'), style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackground)),
            ],
          ),
        ),
      ],
    );
  }

  /// Bulle de révélation pour "Le Sondage Surprise" — les deux réponses
  /// côte à côte avec un indicateur raccord/pas raccord, même esprit visuel
  /// que l'ancienne _RevealView/_AnswerCard (voir BlindPollSessionScreen,
  /// retiré) désormais affichée dans la discussion plutôt que sur un écran
  /// séparé à passer de main en main.
  Widget _buildPollRevealBubble(ThemePalette theme, GameCardSend card, {String? replyPreview, VoidCallback? onReplyTap}) {
    final t = LocaleScope.of(context).t;
    final aligned = card.pollAligned;
    final senderName = _isMine ? t('common_you') : (_partner?.prenom ?? _partner?.name ?? t('game_partner_name_fallback'));
    final recipientName = _isMine ? (_partner?.prenom ?? _partner?.name ?? t('game_partner_name_fallback')) : t('common_you');
    // Tirage stable par carte (basé sur son id, pas Random()) : la même
    // carte affiche toujours la même formule, pas une nouvelle à chaque
    // reconstruction du widget (scroll, setState...). La toute première
    // carte révélée de la discussion garde toujours la première formule de
    // la liste (demande explicite) — les suivantes piochent parmi les
    // autres.
    final phrase = pickPollRevealPhrase(
      card.id,
      aligned: aligned,
      forceFirst: _isFirstPollRevealInThread(card.id),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: (aligned ? Colors.green : theme.primary).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Citation de la question "greffée" sur la bulle de révélation
          // (voir demande utilisateur) plutôt que laissée sur une bulle de
          // réponse séparée au-dessus — sans ça, il fallait garder DEUX
          // bulles (la réponse brute + la comparaison) pour ne pas perdre
          // le lien vers la carte concernée. Même style que
          // _ChatBubble.replyPreview.
          if (replyPreview != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: onReplyTap,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
                  decoration: BoxDecoration(
                    color: theme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border(left: BorderSide(color: theme.primary.withValues(alpha: 0.5), width: 3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.reply_rounded, size: 13, color: theme.textOnBackgroundMuted.withValues(alpha: 0.8)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          replyPreview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.nunito(
                            fontSize: 11.5,
                            fontStyle: FontStyle.italic,
                            color: theme.textOnBackgroundMuted.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _PollAnswerCard(theme: theme, name: senderName, answer: card.senderAnswer ?? '')),
                const SizedBox(width: 8),
                Expanded(child: _PollAnswerCard(theme: theme, name: recipientName, answer: card.answer ?? '')),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(phrase.emoji, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  t(phrase.textKey),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: aligned ? Colors.green.shade700 : theme.textOnBackgroundMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Ma propre réponse, seule (voir _buildPollRevealBubble pour la version
  /// à deux réponses une fois le binôme aussi répondu) — affichée UNIQUEMENT
  /// pour qui a envoyé la carte (jamais côté binôme, qui ne doit rien voir
  /// avant sa propre réponse, voir demande utilisateur sur le caractère
  /// "à l'aveugle" du jeu).
  Widget _buildPollWaitingBubble(ThemePalette theme, GameCardSend card) {
    final t = LocaleScope.of(context).t;
    final editing = _editingBlindPollAnswerFor == card.id;
    final updating = _submittingBlindAnswer == card.id;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (editing) ...[
            // Tant que le binôme n'a pas répondu (cette bulle n'existe que
            // dans ce cas, voir _buildMessageList), ma réponse cachée reste
            // modifiable — verrouillé dès que la révélation existe (voir
            // GameCardController::updateSenderAnswer, demande utilisateur).
            Text(
              t('game_blind_poll_edit_your_answer'),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: theme.textOnBackground),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in card.options)
                  _QuizActionButton(
                    label: option,
                    color: theme.primary,
                    filled: option == card.senderAnswer,
                    loading: updating,
                    onTap: _submittingBlindAnswer != null
                        ? null
                        : () => _updateBlindPollSenderAnswer(card, option),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: updating ? null : () => setState(() => _editingBlindPollAnswerFor = null),
                child: Text(
                  t('common_cancel'),
                  style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: theme.textOnBackgroundMuted),
                ),
              ),
            ),
          ] else ...[
            _PollAnswerCard(theme: theme, name: t('common_you'), answer: card.senderAnswer ?? ''),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: () => setState(() => _editingBlindPollAnswerFor = card.id),
                child: Text(
                  t('common_edit'),
                  style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: theme.primary),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                WaitingDots(color: theme.textOnBackgroundMuted),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    t(
                      'game_blind_poll_waiting_for_partner',
                      {'partner': partnerReferenceLabel(context, _partner, card.id)},
                    ),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.textOnBackgroundMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Barre de saisie façon messagerie (Telegram/WhatsApp). Les 3 raccourcis
  /// (poème/battement de cœur/envoyer une autre carte) ne sont plus
  /// affichés en permanence à gauche — repliés derrière un seul bouton "+"
  /// (voir _buildComposerActionsTrigger), qui les déploie juste au-dessus
  /// au tap (voir _buildComposerActionsRow) — le champ de saisie récupère
  /// ainsi tout l'espace qu'occupaient les 3 cercles empilés. Champ en
  /// pilule au centre, bouton d'envoi rond à droite — toujours visibles,
  /// jamais remplacés par un autre contrôle, même après une réponse : les
  /// deux côtés peuvent toujours écrire (vrai chat libre, voir
  /// _submitMessage).
  ///
  /// Exception : "Sans Détour" (`session_type = 'yes_no_only'`, voir
  /// Game.isYesNoOnly) — la zone de texte libre classique n'apparaît
  /// JAMAIS, avant ni après une réponse Oui/Non : le principe même du jeu
  /// est de ne pas argumenter (voir _buildActionsOnlyComposer).
  Widget _buildComposer(ThemePalette theme) {
    if (widget.game.isYesNoOnly) return _buildActionsOnlyComposer(theme);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bannière "Tu réponds à..." tant qu'une citation est en attente
        // (voir _showMessageActionsMenu) — sans elle, rien n'indique que
        // le prochain envoi citera CE message plutôt que d'être un simple
        // message de chat.
        if (_replyQuoteText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.reply_rounded, size: 16, color: theme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: _replyQuoteSendId == null ? null : () => _scrollToQuoted(_replyQuoteSendId!),
                      child: Text(
                        LocaleScope.of(context).t('game_replying_to_label', {'quote': _replyQuoteText ?? ''}),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(fontSize: 12.5, color: theme.textOnBackground),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() {
                      _replyQuoteText = null;
                      _replyQuoteSendId = null;
                    }),
                    child: Icon(Icons.close_rounded, size: 16, color: theme.textOnBackgroundMuted),
                  ),
                ],
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ComposerActionsTrigger(
              theme: theme,
              open: false,
              onTap: _openComposerMenu,
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
                    BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                ),
                child: TextField(
                  controller: _composeController,
                  focusNode: _composeFocusNode,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  style: GoogleFonts.nunito(color: theme.textOnBackground),
                  cursorColor: theme.primary,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: LocaleScope.of(context).t('game_compose_hint'),
                    hintStyle: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: theme.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _submitting ? null : _submitMessage,
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: _submitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                      : const Icon(Icons.send_rounded, size: 20, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Version réduite de _buildComposer pour "Sans Détour" (voir
  /// Game.isYesNoOnly) : garde le tiroir de raccourcis (poème/battement de
  /// cœur/envoyer une autre carte, voir _buildComposerActionsRow) derrière
  /// le bouton "+", mais sans le champ de texte libre ni le bouton d'envoi
  /// — il n'y a rien à écrire, la réponse Oui/Non EST le message (voir
  /// _buildYesNoAnswerBar/_submitSpecialAnswer).
  Widget _buildActionsOnlyComposer(ThemePalette theme) {
    return ComposerActionsTrigger(
      theme: theme,
      open: false,
      onTap: _openComposerMenu,
    );
  }

  /// Feuille "+" façon Carnet de bord (voir TimelineScreen._openComposeMenu)
  /// — une liste de lignes icône+libellé dans une modale qui glisse depuis
  /// le bas, plutôt que le tiroir d'icônes utilisé avant ici (voir demande
  /// utilisateur : les deux "+" de l'app doivent se comporter pareil).
  Future<void> _openComposerMenu() async {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;
    _composeFocusNode.unfocus();

    final choice = await showModalBottomSheet<String>(
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
              ComposeMenuTile(
                theme: theme,
                icon: Icons.style_rounded,
                label: t('game_action_send_new_card'),
                onTap: () => Navigator.of(sheetContext).pop('new_card'),
              ),
              const SizedBox(height: 8),
              ComposeMenuTile(
                theme: theme,
                icon: Icons.favorite_rounded,
                label: t('composer_reply_heartbeat_tooltip'),
                onTap: () => Navigator.of(sheetContext).pop('heartbeat'),
              ),
              const SizedBox(height: 8),
              ComposeMenuTile(
                theme: theme,
                icon: Icons.auto_stories_rounded,
                label: t('composer_reply_poem_tooltip'),
                onTap: () => Navigator.of(sheetContext).pop('poem'),
              ),
              // Voir demande utilisateur : "mon binôme peut m'envoyer une
              // demande me disant de choisir défi ou vérité" — réservé à ce
              // jeu précis, chemin inverse du choix à l'aveugle habituel
              // (voir "Envoyer une autre carte" ci-dessus).
              if (widget.game.isTruthOrDare) ...[
                const SizedBox(height: 8),
                ComposeMenuTile(
                  theme: theme,
                  icon: Icons.help_outline_rounded,
                  label: 'Demander Vérité ou Défi',
                  onTap: () => Navigator.of(sheetContext).pop('truth_or_dare_request'),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (!mounted || choice == null) return;
    switch (choice) {
      case 'poem':
        _reply();
      case 'heartbeat':
        _openHeartbeatReplyOptions();
      case 'new_card':
        _sendAnotherCard();
      case 'truth_or_dare_request':
        _sendTruthOrDareRequest();
    }
  }

  /// Voir demande utilisateur : envoie la demande, puis se comporte comme
  /// les 3 autres actions du menu "+" (clavier jamais rouvert tout seul au
  /// retour, voir demande utilisateur "le clavier s'ouvre automatiquement").
  Future<void> _sendTruthOrDareRequest() async {
    try {
      final result = await GameService.instance.sendTruthOrDareRequest(widget.game.id, replyToSendId: widget.send.id);
      if (!mounted) return;
      _composeFocusNode.unfocus();
      if (!_replies.any((r) => r.id == result.id)) {
        setState(() => _replies = [..._replies, result]);
      }
      _scrollToBottom();
      _syncRepliesCacheSilently();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'envoyer la demande. Réessaie dans un instant.")),
      );
    }
  }
}

/// "En ligne" prime toujours (voir isOnline dans build) — cette fonction ne
/// sert que le repli hors ligne, à partir de AppUser.lastSeenAt
/// (voir TouchLastSeen côté backend).
String _lastSeenLabel(BuildContext context, DateTime? lastSeenAt) => lastSeenLabel(context, lastSeenAt);

/// Bulle "carte" pour la question elle-même — une vraie carte-photo (même
/// esprit que SlideVisualCard/"Envoyer une pensée" : image de la boîte en
/// fond, voile sombre, légende en italique par-dessus, halo lumineux tout
/// autour) plutôt qu'une bulle de chat classique, pour qu'on reconnaisse
/// immédiatement une carte-question jouée d'un simple message écrit. Les
/// réponses/messages libres qui suivent restent, eux, des _ChatBubble
/// ordinaires.
class _GameCardMessageBubble extends StatelessWidget {
  final ThemePalette theme;
  final bool isMine;
  final String question;
  final String boxTitle;
  final String? imagePath;
  final double imageFocusX;
  final double imageFocusY;
  final String? iconKey;
  final DateTime time;
  // Uniquement "en cours d'envoi"/"envoyé"/"lu" — jamais "échec" : les
  // cartes envoyées depuis cette discussion (voir _sendAnotherCard)
  // attendent déjà la confirmation serveur sur leur propre écran avant de
  // rejoindre le fil, donc jamais affichées ici en pending/échouées.
  final SendTick? tick;
  // Cercle "+"/badge de réaction accroché au bord bas de la carte (voir
  // _GameCardThreadScreenState._reactionOverlay) — même motif que
  // SlideDetailScreen._ChatBubble.cornerOverlay.
  final Widget? reactionOverlay;
  // 'verite' | 'defi' | null (jeux "classiques", voir
  // GameCardSend.category) — affiché à la place du badge générique "CARTE"
  // quand renseigné, pour qu'on sache d'un coup d'œil, sans ouvrir la
  // carte, s'il s'agit d'une Vérité ou d'un Défi (voir demande
  // utilisateur).
  final String? category;

  const _GameCardMessageBubble({
    super.key,
    required this.theme,
    required this.isMine,
    required this.question,
    required this.boxTitle,
    required this.imagePath,
    this.imageFocusX = 50,
    this.imageFocusY = 50,
    required this.iconKey,
    required this.time,
    this.tick,
    this.reactionOverlay,
    this.category,
  });

  String get _time {
    final local = time.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  /// Même mapping que GameBox.imageAlignment — pas d'accès à l'objet
  /// GameBox complet ici, seulement son point de focus brut.
  Alignment get _imageAlignment => Alignment(
        (imageFocusX.clamp(0, 100) / 100) * 2 - 1,
        (imageFocusY.clamp(0, 100) / 100) * 2 - 1,
      );

  // Très légèrement arrondi plutôt que totalement fermé (même ratio que
  // les bulles du Carnet de bord, voir _ChatBubble dans SlideDetailScreen :
  // 6 sur un rayon principal de 26) — un vrai 0 lisait comme un défaut de
  // rendu plutôt qu'un choix de design.
  BorderRadius get _cardRadius => BorderRadius.only(
        topLeft: const Radius.circular(22),
        topRight: const Radius.circular(22),
        bottomLeft: Radius.circular(isMine ? 22 : 5),
        bottomRight: Radius.circular(isMine ? 5 : 22),
      );

  @override
  Widget build(BuildContext context) {
    final hasImage = imagePath != null && imagePath!.isNotEmpty;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.62),
            child: Container(
              // Halo lumineux tout autour de la carte — ce qui donne
              // immédiatement "ceci est un objet à part", pas un message.
              // Coin en angle droit du côté de l'expéditeur·rice (même
              // traitement que les bulles des poèmes-slides envoyés, voir
              // _ChatBubble dans SlideDetailScreen) — les 3 autres coins
              // restent arrondis.
              decoration: BoxDecoration(
                borderRadius: _cardRadius,
                boxShadow: [
                  BoxShadow(color: theme.primary.withValues(alpha: 0.45), blurRadius: 22, spreadRadius: 1),
                  BoxShadow(color: theme.secondary.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 6)),
                ],
              ),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: _cardRadius,
                    gradient: theme.accentGradient,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.28), width: 1.4),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (hasImage)
                        Image.network(
                          imagePath!,
                          fit: BoxFit.cover,
                          alignment: _imageAlignment,
                          errorBuilder: (context, error, stackTrace) => Center(
                            child: Icon(iconForGameBox(iconKey), size: 56, color: Colors.white.withValues(alpha: 0.55)),
                          ),
                        )
                      else
                        Center(
                          child: Icon(iconForGameBox(iconKey), size: 56, color: Colors.white.withValues(alpha: 0.55)),
                        ),
                      // Voile sombre en bas pour garder la légende lisible
                      // par-dessus la photo — même dégradé que SlideVisualCard.
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
                      // Chip "CARTE" — seul indice explicite, en plus du
                      // format photo lui-même, qu'il s'agit d'une carte
                      // jouée plutôt que d'un message.
                      Positioned(
                        left: 12,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                          ),
                          child: Builder(
                            builder: (context) {
                              final t = LocaleScope.of(context).t;
                              final label = switch (category) {
                                'defi' => t('truth_or_dare_dare_label'),
                                'verite' => t('truth_or_dare_truth_label'),
                                _ => t('game_card_badge'),
                              };
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.style_rounded, size: 11, color: Colors.white),
                                  const SizedBox(width: 4),
                                  Text(
                                    label.toUpperCase(),
                                    style: GoogleFonts.poppins(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 14,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              boxTitle.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.nunito(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                                shadows: const [Shadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 1))],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              question,
                              style: GoogleFonts.playfairDisplay(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                fontStyle: FontStyle.italic,
                                height: 1.3,
                                shadows: const [Shadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 2))],
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Heure + accusé de lecture directement sur la
                            // carte, en bas à droite (voir capture
                            // utilisateur : "voici comment l'heure sur
                            // WhatsApp est représentée, faire pareil").
                            // Pastille sombre (même traitement que le badge
                            // "CARTE" plus haut) plutôt qu'un texte blanc nu
                            // avec juste une ombre — sur un fond clair
                            // (dégradé de la carte, pas toujours sombre en
                            // bas), le texte devenait illisible/invisible
                            // (voir demande utilisateur : "aucune date
                            // n'apparaît nulle part").
                            Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _time,
                                      style: GoogleFonts.nunito(
                                        fontSize: 10.5,
                                        color: Colors.white,
                                      ),
                                    ),
                                    if (isMine && tick != null) ...[
                                      const SizedBox(width: 4),
                                      SendTickIcon(tick: tick!, color: Colors.white),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (reactionOverlay != null)
            // Transform (pas un Positioned dans un Stack) : ça déplace le
            // tap en même temps que le dessin — avec Positioned, la moitié
            // débordante du cercle était peinte hors de sa zone réellement
            // cliquable, et il fallait taper plusieurs fois pour que ça
            // marche (même piège déjà identifié et corrigé côté
            // SlideDetailScreen._ChatBubble.cornerOverlay).
            Transform.translate(
              offset: const Offset(0, -16),
              child: Align(
                alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: isMine ? 0 : 14, right: isMine ? 14 : 0),
                  child: reactionOverlay!,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Petit cercle façon avatar, accroché au bord de la carte — un émoji
/// représentatif du set proposé (pas une vraie photo de profil) invitant à
/// réagir. Au tap, déploie la barre de réactions juste en dessous. Copie
/// conforme de SlideDetailScreen._ReactionTriggerCircle.
class _ReactionTriggerCircle extends StatelessWidget {
  final String emoji;
  final VoidCallback onTap;

  const _ReactionTriggerCircle({required this.emoji, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        // Zone de tap 44x44 (minimum recommandé Material/Android), même si
        // le cercle VISIBLE reste 32x32 — un finger réel manque facilement
        // une cible de 32px accrochée au bord d'une carte, surtout sur un
        // appareil d'entrée de gamme (constaté en réel : aucune réaction au
        // tap, jamais de ripple ni de panneau qui s'ouvre).
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
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
              child: ColorFiltered(
                colorFilter: const ColorFilter.mode(Colors.black45, BlendMode.srcIn),
                child: Text(emoji, style: const TextStyle(fontSize: 16)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// LA réaction posée sur cette carte (une seule à la fois) — retapable par
/// le/la destinataire pour la changer. Copie conforme de
/// SlideDetailScreen._SingleReactionBadge.
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

/// Les DEUX réactions posées sur la carte (moi + mon binôme) — deux petits
/// cercles superposés façon iMessage plutôt qu'un seul émoji, pour qu'on
/// voie d'un coup d'œil qu'il y en a deux sans avoir à ouvrir le panneau.
class _DualReactionBadge extends StatelessWidget {
  final String mineEmoji;
  final String partnerEmoji;
  final VoidCallback onTap;

  const _DualReactionBadge({required this.mineEmoji, required this.partnerEmoji, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        // Zone de tap élargie (voir _ReactionTriggerCircle) — pas de forme
        // circulaire ici (le badge est ovale, deux cercles côte à côte),
        // donc pas de customBorder : un rectangle discret suffit, il reste
        // invisible (Material transparent).
        child: SizedBox(
          width: 54,
          height: 44,
          child: Center(
            child: SizedBox(
              width: 42,
              height: 32,
              child: Stack(
                children: [
                  _reactionDot(partnerEmoji),
                  Positioned(left: 12, child: _reactionDot(mineEmoji)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _reactionDot(String emoji) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Text(emoji, style: const TextStyle(fontSize: 14)),
    );
  }
}

/// La "bande" qui liste qui a réagi avec quoi — déployée au-dessus de la
/// rangée d'émojis quand on tape sur le cercle de réaction (voir
/// _GameCardThreadScreenState._reactionPanel). Une puce par réaction (moi
/// en premier si j'en ai une), jamais tapable : changer la sienne se fait
/// via la rangée d'émojis juste en dessous, pas ici.
class _ReactionSummaryStrip extends StatelessWidget {
  final ThemePalette theme;
  final List<SendReaction> reactions;
  final String myUserId;

  const _ReactionSummaryStrip({required this.theme, required this.reactions, required this.myUserId});

  @override
  Widget build(BuildContext context) {
    final ordered = [...reactions]..sort((a, b) => a.userId == myUserId ? -1 : (b.userId == myUserId ? 1 : 0));

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.84),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final reaction in ordered)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(reaction.emoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    // Flexible + ellipsis : un prénom long débordait sinon
                    // hors du cadre de la bande (ConstrainedBox 0.84 *
                    // largeur d'écran, voir plus bas), même motif que
                    // _buildInviteStatusLabel plus haut dans ce fichier.
                    Flexible(
                      child: Text(
                        reaction.userId == myUserId
                            ? LocaleScope.of(context).t('common_you')
                            : (reaction.user?.prenom ?? LocaleScope.of(context).t('game_partner_name_fallback')),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(fontSize: 12.5, fontWeight: FontWeight.w700, color: theme.textOnBackground),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Barre de réactions rapides — set d'émojis passé en paramètre (thématisé
/// selon le jeu, voir _GameCardThreadScreenState._reactionEmojis). Copie
/// conforme de SlideDetailScreen._ReactionBar.
class _ReactionBar extends StatelessWidget {
  final bool enabled;
  final ValueChanged<String> onPick;
  final ThemePalette theme;
  final List<String> emojiOptions;

  const _ReactionBar({
    required this.enabled,
    required this.onPick,
    required this.theme,
    required this.emojiOptions,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.84),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: emojiOptions.map((emoji) {
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

/// Message texte libre envoyé optimistiquement (voir
/// _GameCardThreadScreenState._submitMessage) — identité par référence
/// d'objet (pas d'id serveur tant qu'il n'est pas confirmé), mutable pour
/// pouvoir basculer son statut d'échec sans reconstruire toute la liste.
class _PendingText {
  final String text;
  final DateTime time;
  bool failed = false;

  _PendingText({required this.text, required this.time});
}

/// Badge de coût pour l'envoi d'une pensée — même rendu que
/// DarkQuickActionsGrid._PriceBadge (Duo), copié tel quel plutôt que
/// partagé (widget privé à ce fichier-là) pour rester cohérent visuellement
/// où qu'on lance l'envoi d'une pensée dans l'app.
class _HeartbeatPriceBadge extends StatelessWidget {
  final int coinPrice;

  const _HeartbeatPriceBadge({required this.coinPrice});

  @override
  Widget build(BuildContext context) {
    // Abonnement actif : le battement de cœur est gratuit et illimité
    // (voir HeartbeatController côté backend, aucun débit pour un abonné)
    // — plus aucune raison d'afficher son prix (voir demande utilisateur :
    // "rien ne doit apparaître").
    if (SubscriptionStatusNotifier.instance.isActive) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CoinIcon(size: 14, fallbackColor: Color(0xFFFFD37A)),
          const SizedBox(width: 4),
          Text(
            '$coinPrice',
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Un élément du fil sous la carte racine, avec l'horodatage réel qui doit
/// décider de sa position — voir _GameCardThreadScreenState._timelineEntries.
/// Sans ça, une réponse à une carte "classique" (voir _buildClassicAnswerBubble)
/// rendue systématiquement en toute fin de liste pouvait se retrouver
/// AVANT un message/poème/pensée envoyé après elle (constaté en réel, voir
/// demande utilisateur : "le plus récent doit être en bas").
class _TimelineEntry {
  final DateTime time;
  final Widget widget;

  _TimelineEntry(this.time, this.widget);
}

class _ChatBubble extends StatelessWidget {
  final ThemePalette theme;
  final bool isMine;
  final String text;
  final DateTime time;
  final SendTick? tick;
  final VoidCallback? onRetry;
  // Citation tappable en tête de bulle, façon "réponse à" WhatsApp — utile
  // dès qu'un Oui/Non ou un message court ne suffit pas à lui seul à dire
  // à quelle carte il répond (voir _GameCardThreadScreenState.
  // _scrollToRootCard, qui fournit onReplyTap pour la réponse racine).
  final String? replyPreview;
  final VoidCallback? onReplyTap;
  // Petit menu accroché à la bulle ("Ai-je le droit ?"/"Sans Détour"
  // uniquement, voir _GameCardThreadScreenState._buildAnswerActionsMenu) —
  // inviter le binôme à répondre à la même question + les raccourcis
  // habituels (nouvelle carte/poème/battement de cœur).
  final Widget? actionsMenu;
  // Cache [text] derrière une bande façon "carte à gratter" — pour qui a
  // été invité·e à répondre à la même question (voir GameCardSend.
  // needsSenderAnswer) et n'a pas encore répondu, pour ne pas voir la
  // réponse du binôme avant la sienne et risquer d'être influencé·e (voir
  // demande utilisateur). Jamais activé pour qui a répondu en premier :
  // c'est SA propre réponse, rien à lui cacher.
  final bool masked;
  // Clic-maintenu → menu "Répondre"/pensée/poème (voir
  // _GameCardThreadScreenState._showMessageActionsMenu) — `null` pour les
  // rares bulles qui n'ont pas de texte pertinent à citer (ex. carte
  // masquée en attente).
  final void Function(Offset globalPosition)? onLongPress;

  const _ChatBubble({
    required this.theme,
    required this.isMine,
    required this.text,
    required this.time,
    this.tick,
    this.onRetry,
    this.replyPreview,
    this.onReplyTap,
    this.actionsMenu,
    this.masked = false,
    this.onLongPress,
  });

  String get _time {
    final local = time.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: onLongPress == null ? null : (details) => onLongPress!(details.globalPosition),
      child: Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        // Stack plutôt qu'un simple Container : quand [actionsMenu] existe
        // (ex. inviter le binôme à répondre à son tour), il flotte en petit
        // bouton rond au coin haut-droit de la bulle (voir plus bas) — avant,
        // il était noyé dans la même ligne que l'heure/l'accusé de lecture,
        // en bas, et passait facilement inaperçu (voir demande utilisateur).
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
          decoration: BoxDecoration(
            gradient: isMine ? LinearGradient(colors: [theme.primary, theme.secondary]) : null,
            color: isMine ? null : theme.surface,
            // Coin "pointu" du côté de l'expéditeur (façon Telegram) plutôt
            // que symétrique — donne la petite queue de bulle qui indique
            // visuellement de quel côté part le message.
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMine ? 16 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 16),
            ),
            border: isMine ? null : Border.all(color: theme.primary.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (replyPreview != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: GestureDetector(
                    onTap: onReplyTap,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
                      decoration: BoxDecoration(
                        color: (isMine ? Colors.white : theme.primary).withValues(alpha: isMine ? 0.16 : 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border(
                          left: BorderSide(color: (isMine ? Colors.white : theme.primary).withValues(alpha: 0.5), width: 3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.reply_rounded,
                            size: 13,
                            color: (isMine ? Colors.white : theme.textOnBackgroundMuted).withValues(alpha: 0.8),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              replyPreview!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.nunito(
                                fontSize: 11.5,
                                fontStyle: FontStyle.italic,
                                color: (isMine ? Colors.white : theme.textOnBackgroundMuted).withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (masked)
                Container(
                  width: 56,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (isMine ? Colors.white : theme.primary).withValues(alpha: isMine ? 0.35 : 0.18),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Icon(
                    Icons.lock_rounded,
                    size: 12,
                    color: isMine ? Colors.white.withValues(alpha: 0.9) : theme.primary,
                  ),
                )
              else
                Text(
                  text,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    height: 1.35,
                    color: isMine ? Colors.white : theme.textOnBackground,
                  ),
                ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _time,
                    style: GoogleFonts.nunito(
                      fontSize: 10.5,
                      color: isMine ? Colors.white.withValues(alpha: 0.75) : theme.textOnBackgroundMuted,
                    ),
                  ),
                  if (isMine && tick != null) ...[
                    const SizedBox(width: 4),
                    SendTickIcon(tick: tick!, color: Colors.white.withValues(alpha: 0.75), onRetry: onRetry),
                  ],
                ],
              ),
            ],
          ),
            ),
            if (actionsMenu != null)
              Positioned(
                top: -6,
                right: -6,
                // Taille imposée : PopupMenuButton réclame sinon sa zone de
                // tap minimale par défaut (48x48, celle d'un IconButton
                // normal), largement surdimensionnée pour ce petit badge
                // flottant (voir demande utilisateur : "trop gros").
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.surface,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 5, offset: const Offset(0, 1)),
                      ],
                    ),
                    child: actionsMenu,
                  ),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Un poème envoyé depuis cette discussion — la VRAIE carte (feuilletable,
/// voir SlidePackViewer/showPackReplyModal), pas un texte plat avec juste
/// le titre du pack (voir demande utilisateur, même principe que
/// HeartbeatCard pour les pensées). Contrairement à un battement de cœur,
/// un pack de poème n'embarque pas ses slides dans le Send lui-même (voir
/// SlideDetailScreen._loadPackSlides) — il faut les récupérer séparément,
/// d'où le StatefulWidget dédié plutôt qu'une simple fonction de rendu.
class _PoemReplyBubble extends StatefulWidget {
  final ThemePalette theme;
  final Send reply;
  final bool isMine;
  final void Function(Offset globalPosition)? onLongPress;

  const _PoemReplyBubble({
    required this.theme,
    required this.reply,
    required this.isMine,
    this.onLongPress,
  });

  @override
  State<_PoemReplyBubble> createState() => _PoemReplyBubbleState();
}

class _PoemReplyBubbleState extends State<_PoemReplyBubble> {
  List<Slide>? _slides;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final packId = widget.reply.pack?.id;
    if (packId == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final pack = await ContentService.instance.fetchPack(packId);
      if (!mounted) return;
      setState(() {
        _slides = pack.slides;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final packId = widget.reply.pack?.id;

    Widget card;
    if (_loading) {
      card = Center(child: CircularProgressIndicator(color: theme.primary));
    } else if (_slides == null || _slides!.isEmpty) {
      card = Center(
        child: Icon(Icons.auto_stories_rounded, size: 40, color: theme.primary.withValues(alpha: 0.4)),
      );
    } else {
      card = SlidePackViewer(
        slides: _slides!,
        theme: theme,
        category: widget.reply.pack?.category,
        senderGender: widget.reply.sender?.gender,
        // Même correctif que la modale de réponse/SlideDetailScreen : marge
        // horizontale seulement, pas de marge verticale (sinon le fond de
        // la bulle apparaît en bordure comme un cadre).
        slideMargin: const EdgeInsets.symmetric(horizontal: 6),
        // Cette bulle ne fait que 200px de large — la légende par défaut
        // (SlideVisualCard) est pensée pour une carte pleine largeur et
        // s'y retrouvait coupée en mots isolés sur des lignes minuscules
        // (voir demande utilisateur, capture "chaque jour il" sur sa
        // propre ligne). Même principe que SlideDetailScreen._packPreview,
        // qui réduit déjà pour sa miniature de 130px.
        scale: 0.6,
      );
    }

    return Align(
      alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: packId == null ? null : () => showPackReplyModal(context, packId: packId),
        onLongPressStart: widget.onLongPress == null
            ? null
            : (details) => widget.onLongPress!(details.globalPosition),
        // Heure + accusé de lecture en overlay directement sur la carte
        // (coin bas droit, pastille sombre) plutôt qu'en élément séparé
        // dessous — même correctif fiable que _GameCardMessageBubble/
        // _buildHeartbeatBubble (voir demande utilisateur : "il y a des
        // heures qui se baladent").
        child: Stack(
          children: [
            SizedBox(
              width: 200,
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(color: theme.surface, child: card),
                ),
              ),
            ),
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${widget.reply.createdAt.toLocal().hour.toString().padLeft(2, '0')}:${widget.reply.createdAt.toLocal().minute.toString().padLeft(2, '0')}',
                      style: GoogleFonts.nunito(fontSize: 10.5, color: Colors.white),
                    ),
                    if (widget.isMine) ...[
                      const SizedBox(width: 4),
                      SendTickIcon(
                        tick: sendTickFor(widget.reply),
                        color: Colors.white,
                        onRetry: null,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bulle de réponse pour le fil deviner/verdict d'une carte `quiz` (voir
/// _GameCardThreadScreenState._buildQuizReplyBubble) — même gabarit que
/// _ChatBubble (fond plein/dégradé, coin pointu côté expéditeur·rice) mais
/// avec un [child] arbitraire plutôt qu'un simple texte, pour pouvoir y
/// empiler la citation de la question, l'historique des devinettes et
/// l'action en cours.
class _QuizReplyBubble extends StatelessWidget {
  final ThemePalette theme;
  final bool isMine;
  final Widget child;
  final DateTime time;

  const _QuizReplyBubble({
    required this.theme,
    required this.isMine,
    required this.child,
    required this.time,
  });

  String get _time {
    final local = time.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
          decoration: BoxDecoration(
            gradient: isMine ? LinearGradient(colors: [theme.primary, theme.secondary]) : null,
            color: isMine ? null : theme.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMine ? 16 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 16),
            ),
            border: isMine ? null : Border.all(color: theme.primary.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              child,
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _time,
                  style: GoogleFonts.nunito(
                    fontSize: 10.5,
                    color: isMine ? Colors.white.withValues(alpha: 0.75) : theme.textOnBackgroundMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Petit bouton compact pour le fil deviner/verdict des jeux `quiz` (voir
/// _GameCardThreadScreenState._buildQuizReplyBubble) — copie simplifiée de
/// EmojiStorySessionScreen._SmallActionButton (pleine couleur ou juste
/// contourné, avec un mini spinner intégré pendant l'envoi).
class _QuizActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final bool filled;
  final bool loading;
  final VoidCallback? onTap;

  const _QuizActionButton({
    required this.label,
    this.icon,
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
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: filled ? null : Border.all(color: fg.withValues(alpha: 0.5)),
            ),
            child: loading
                ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
                // Row(mainAxisSize.min) + Text sans Flexible débordait
                // (RenderFlex overflow) quand 3 boutons se partagent une
                // bulle de largeur limitée (voir _buildVerdictButtons) — le
                // Container reçoit une largeur fixe de son Expanded parent,
                // mais un Text plein ignore cette contrainte.
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
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

/// Une formule affichée sous les deux réponses de la bulle de révélation
/// (voir _buildPollRevealBubble) — emoji + texte, choisis ensemble pour
/// rester cohérents.
class PollRevealPhrase {
  final String emoji;
  final String textKey;

  const PollRevealPhrase(this.emoji, this.textKey);
}

/// 20 formules par état (raccord / pas raccord) plutôt qu'une seule figée —
/// une même carte affiche toujours la MÊME formule (voir
/// pickPollRevealPhrase, tirage stable par id de carte), mais deux cartes
/// différentes ont de bonnes chances de tomber sur des formules différentes,
/// pour que la révélation garde un peu de surprise au fil des sondages.
const List<PollRevealPhrase> kPollAlignedPhrases = [
  PollRevealPhrase('🔥', 'poll_aligned_1'),
  PollRevealPhrase('✨', 'poll_aligned_2'),
  PollRevealPhrase('🎯', 'poll_aligned_3'),
  PollRevealPhrase('🤝', 'poll_aligned_4'),
  PollRevealPhrase('💫', 'poll_aligned_5'),
  PollRevealPhrase('🧠', 'poll_aligned_6'),
  PollRevealPhrase('🎉', 'poll_aligned_7'),
  PollRevealPhrase('🪄', 'poll_aligned_8'),
  PollRevealPhrase('🎶', 'poll_aligned_9'),
  PollRevealPhrase('🌟', 'poll_aligned_10'),
  PollRevealPhrase('🫶', 'poll_aligned_11'),
  PollRevealPhrase('🎊', 'poll_aligned_12'),
  PollRevealPhrase('🧲', 'poll_aligned_13'),
  PollRevealPhrase('🕊️', 'poll_aligned_14'),
  PollRevealPhrase('🎁', 'poll_aligned_15'),
  PollRevealPhrase('🥂', 'poll_aligned_16'),
  PollRevealPhrase('🎵', 'poll_aligned_17'),
  PollRevealPhrase('🏆', 'poll_aligned_18'),
  PollRevealPhrase('💞', 'poll_aligned_19'),
  PollRevealPhrase('🚀', 'poll_aligned_20'),
];

const List<PollRevealPhrase> kPollMisalignedPhrases = [
  PollRevealPhrase('🎭', 'poll_misaligned_1'),
  PollRevealPhrase('🤷', 'poll_misaligned_2'),
  PollRevealPhrase('🍿', 'poll_misaligned_3'),
  PollRevealPhrase('😅', 'poll_misaligned_4'),
  PollRevealPhrase('🧩', 'poll_misaligned_5'),
  PollRevealPhrase('🎨', 'poll_misaligned_6'),
  PollRevealPhrase('🎲', 'poll_misaligned_7'),
  PollRevealPhrase('🌗', 'poll_misaligned_8'),
  PollRevealPhrase('🎢', 'poll_misaligned_9'),
  PollRevealPhrase('🍕', 'poll_misaligned_10'),
  PollRevealPhrase('🧭', 'poll_misaligned_11'),
  PollRevealPhrase('🎈', 'poll_misaligned_12'),
  PollRevealPhrase('🌈', 'poll_misaligned_13'),
  PollRevealPhrase('🔮', 'poll_misaligned_14'),
  PollRevealPhrase('🎤', 'poll_misaligned_15'),
  PollRevealPhrase('🛸', 'poll_misaligned_16'),
  PollRevealPhrase('😆', 'poll_misaligned_17'),
  PollRevealPhrase('🎳', 'poll_misaligned_18'),
  PollRevealPhrase('🧵', 'poll_misaligned_19'),
  PollRevealPhrase('🌤️', 'poll_misaligned_20'),
];

/// Tirage stable (pas Random()) : basé sur le hash de l'id de la carte, donc
/// toujours la même formule pour la même carte, y compris après un
/// rafraîchissement ou une réouverture de la discussion. [forceFirst] :
/// pour la toute première carte révélée d'une discussion, toujours la
/// première formule de la liste (index 0) — demande explicite, plutôt que
/// le tirage habituel.
PollRevealPhrase pickPollRevealPhrase(String cardId, {required bool aligned, bool forceFirst = false}) {
  final pool = aligned ? kPollAlignedPhrases : kPollMisalignedPhrases;
  if (forceFirst) return pool.first;
  final index = cardId.hashCode.abs() % pool.length;
  return pool[index];
}

/// Une des deux réponses côte à côte dans la bulle de révélation du
/// "Sondage Surprise" (voir _buildPollRevealBubble) — copie visuelle
/// simplifiée de l'ancienne _AnswerCard (BlindPollSessionScreen, retiré).
class _PollAnswerCard extends StatelessWidget {
  final ThemePalette theme;
  final String name;
  final String answer;

  const _PollAnswerCard({required this.theme, required this.name, required this.answer});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: theme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.nunito(fontSize: 10.5, fontWeight: FontWeight.w700, color: theme.textOnBackgroundMuted),
          ),
          const SizedBox(height: 4),
          Text(
            answer,
            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: theme.textOnBackground),
          ),
        ],
      ),
    );
  }
}
