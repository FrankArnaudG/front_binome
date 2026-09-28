import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/app_router.dart';
import '../../core/realtime_client.dart';
import '../../l10n/locale_scope.dart';
import '../../models/app_user.dart';
import '../../models/game.dart';
import '../../models/game_box.dart';
import '../../models/send.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/send_status_tick.dart';
import '../box/box_service.dart';
import '../content/content_service.dart';
import 'game_box_history_screen.dart';
import 'game_boxes_screen.dart';
import 'game_service.dart';

/// Discussions d'UN SEUL jeu — voir demande utilisateur : "lister tout les
/// jeux, pour voir une conversation il faut cliquer sur le jeu" (voir
/// GameDiscussionsScreen, qui liste désormais les jeux plutôt que les
/// messages). Copie structurelle de l'ancien GameDiscussionsScreen "tous
/// jeux confondus", scopée à [game] via `gameId` (voir
/// ContentService.fetchSends/SendController::index) — jamais tout
/// `game_card` d'un coup : un jeu très actif pourrait à lui seul compter
/// des centaines, voire des milliers de discussions.
class GameConversationsScreen extends StatefulWidget {
  final Game game;
  final AppUser user;

  const GameConversationsScreen({super.key, required this.game, required this.user});

  @override
  State<GameConversationsScreen> createState() => _GameConversationsScreenState();
}

class _GameConversationsScreenState extends State<GameConversationsScreen> {
  static const _pageSize = 20;

  List<Send>? _sends;
  bool _loading = true;
  bool _error = false;
  int _page = 1;
  bool _hasMore = false;
  bool _loadingMore = false;
  bool _opening = false;
  final _scrollController = ScrollController();

  List<GameBox>? _boxes;

  String? _subscribedBoxId;
  StreamSubscription<void>? _resyncSub;
  Timer? _reloadDebounce;

  @override
  void initState() {
    super.initState();
    _load();
    BoxService.instance.addListener(_syncRealtimeSubscription);
    _syncRealtimeSubscription();
    _resyncSub = RealtimeClient.instance.resyncRequests.listen((_) => _load());
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (_hasMore && !_loadingMore && position.pixels >= position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    BoxService.instance.removeListener(_syncRealtimeSubscription);
    _resyncSub?.cancel();
    _reloadDebounce?.cancel();
    _scrollController.dispose();
    if (_subscribedBoxId != null) {
      RealtimeClient.instance.unsubscribeFromBox(_subscribedBoxId!, onEvent: _onRealtimeEvent);
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final sends = await ContentService.instance.fetchSends(type: 'game_card', gameId: widget.game.id, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _sends = sends;
        _page = 1;
        _hasMore = sends.length == _pageSize;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_sends == null) _error = true;
      });
    }
  }

  Future<void> _loadMore() async {
    final sends = _sends;
    if (!_hasMore || _loadingMore || sends == null) return;
    setState(() => _loadingMore = true);
    try {
      final next = await ContentService.instance.fetchSends(
        type: 'game_card',
        gameId: widget.game.id,
        page: _page + 1,
        limit: _pageSize,
      );
      if (!mounted) return;
      final known = sends.map((s) => s.id).toSet();
      setState(() {
        _sends = [...sends, ...next.where((s) => !known.contains(s.id))];
        _page += 1;
        _hasMore = next.length == _pageSize;
      });
    } catch (_) {
      // best effort — l'utilisateur pourra réessayer en re-scrollant.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _syncRealtimeSubscription() async {
    final coupleBoxId = BoxService.instance.currentBox?.id;
    if (coupleBoxId == _subscribedBoxId) return;
    final previous = _subscribedBoxId;
    _subscribedBoxId = coupleBoxId;
    if (previous != null) {
      RealtimeClient.instance.unsubscribeFromBox(previous, onEvent: _onRealtimeEvent);
    }
    if (coupleBoxId == null) return;
    _load();
    try {
      await RealtimeClient.instance.subscribeToBox(coupleBoxId, onEvent: _onRealtimeEvent);
    } catch (_) {
      // Best effort.
    }
  }

  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _load();
    });
  }

  /// Même traitement que GameDiscussionsScreen (ex-écran unique) avant sa
  /// scission — ne retient ici QUE les événements concernant [widget.game]
  /// (voir chaque branche : `gameId != widget.game.id` → ignoré).
  void _onRealtimeEvent(RealtimeEvent event) {
    if (!mounted) return;
    final current = _sends ?? [];

    if (event.event == 'SendSeen') {
      final sendId = event.data?['send_id'] as String?;
      if (sendId == null) return;
      final seenAtStr = event.data?['seen_at'] as String?;
      final seenAt = seenAtStr != null ? DateTime.parse(seenAtStr) : DateTime.now();
      final index = current.indexWhere((s) => s.id == sendId || s.latestReply?.id == sendId);
      if (index == -1) return;
      final updated = List<Send>.of(current);
      final target = updated[index];
      updated[index] = target.latestReply?.id == sendId
          ? target.copyWith(latestReply: target.latestReply!.copyWith(status: 'seen', seenAt: seenAt))
          : target.copyWith(status: 'seen', seenAt: seenAt);
      setState(() => _sends = updated);
      return;
    }

    if (event.event == 'SendDelivered') {
      final sendIds = (event.data?['send_ids'] as List?)?.map((e) => e as String).toList();
      if (sendIds == null || sendIds.isEmpty) return;
      final deliveredAtStr = event.data?['delivered_at'] as String?;
      final deliveredAt = deliveredAtStr != null ? DateTime.parse(deliveredAtStr) : DateTime.now();
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
      return;
    }

    if (event.event == 'GameCardUpdated') {
      final sendJson = event.data?['send'] as Map<String, dynamic>?;
      if (sendJson == null) return;
      final updatedSend = Send.fromJson(sendJson);
      if (updatedSend.gameCard?.gameId != widget.game.id) return;
      final index = current.indexWhere((s) => s.id == updatedSend.id);
      if (index == -1) return;
      final updated = List<Send>.of(current);
      updated[index] = updatedSend.latestReply == null
          ? updatedSend.copyWith(latestReply: current[index].latestReply)
          : updatedSend;
      setState(() => _sends = updated);
      _scheduleReload();
      return;
    }

    if (event.event != 'SendCreated') return;
    final sendJson = event.data?['send'] as Map<String, dynamic>?;
    if (sendJson == null) return;
    final send = Send.fromJson(sendJson);

    if (send.replyToSendId != null) {
      final index = current.indexWhere((s) => s.id == send.replyToSendId);
      if (index == -1) {
        // Racine pas dans CE jeu, ou pas encore chargée — dans les deux
        // cas, rien à faire sans savoir à quel jeu elle appartient ; un
        // rechargement complet trancherait, mais spammerait le réseau à
        // chaque message d'un AUTRE jeu (l'écran majoritaire des cas) —
        // ignoré, la liste se rattrapera au prochain retour sur l'écran.
        return;
      }
      final thread = current[index].copyWith(latestReply: send);
      setState(() => _sends = [thread, ...current.where((s) => s.id != thread.id)]);
      return;
    }

    if (send.sendableType != 'game_card' || send.gameCard?.gameId != widget.game.id) return;
    if (current.any((s) => s.id == send.id)) return;
    setState(() => _sends = [send, ...current]);
    _scheduleReload();
  }

  Future<GameBox?> _boxFor(String gameBoxId) async {
    var boxes = _boxes;
    if (boxes == null) {
      boxes = await GameService.instance.fetchBoxes(widget.game.id);
      _boxes = boxes;
    }
    final matches = boxes.where((b) => b.id == gameBoxId);
    return matches.isEmpty ? null : matches.first;
  }

  Future<void> _open(Send send) async {
    final card = send.gameCard;
    if (card == null || _opening) return;
    setState(() => _opening = true);
    try {
      final box = await _boxFor(card.gameBoxId);
      if (!mounted) return;
      if (box == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LocaleScope.of(context).t('game_history_load_error'))),
        );
        return;
      }
      setState(() => _opening = false);
      AppRouter.showGlobalNavBar.value = false;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GameCardThreadScreen(send: send, user: widget.user, game: widget.game, box: box),
        ),
      );
      AppRouter.showGlobalNavBar.value = true;
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LocaleScope.of(context).t('game_history_load_error'))),
      );
    } finally {
      if (mounted && _opening) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final localeCode = LocaleScope.of(context).current.code;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(
          widget.game.nameFor(localeCode),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: theme.textOnBackground),
        ),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: Stack(
            children: [
              _buildBody(theme, localeCode),
              if (_opening) const Positioned.fill(child: Center(child: CircularProgressIndicator())),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemePalette theme, String localeCode) {
    final t = LocaleScope.of(context).t;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error) {
      return Center(child: EmptyState(icon: Icons.wifi_off_rounded, message: t('game_history_load_error')));
    }
    final sends = (_sends ?? []).where((s) => s.gameCard != null).toList();
    if (sends.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            EmptyState(
              icon: Icons.forum_rounded,
              message: t('game_chats_empty_for_game', {'name': widget.game.nameFor(localeCode)}),
              actionLabel: t('game_chats_empty_cta_for_game'),
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => GameBoxesScreen(game: widget.game, user: widget.user)),
              ),
            ),
          ],
        ),
      );
    }

    final entries = <Widget>[];
    for (var i = 0; i < sends.length; i++) {
      final send = sends[i];
      final card = send.gameCard!;
      final lastMessage = send.lastMessage;
      final isMine = lastMessage.senderId == widget.user.id;
      final senderName = lastMessage.sender?.prenom ?? lastMessage.sender?.name ?? t('game_partner_name_fallback');
      final by = t('game_sent_by', {'sender': isMine ? t('game_sent_by_you') : senderName});
      final subtitle = '${card.gameBoxTitleFor(localeCode)} · $by';

      final dateLabel = dateHeaderLabel(context, lastMessage.createdAt.toLocal());
      final prevLabel = i == 0 ? null : dateHeaderLabel(context, sends[i - 1].lastMessage.createdAt.toLocal());
      final nextLabel = i == sends.length - 1 ? null : dateHeaderLabel(context, sends[i + 1].lastMessage.createdAt.toLocal());

      final row = GameHistoryRow(
        theme: theme,
        send: send,
        isFirstInGroup: dateLabel != prevLabel,
        isLastInGroup: dateLabel != nextLabel,
        questionText: lastMessage.shortPreview(localeCode),
        subtitle: subtitle,
        time: _formattedTime(lastMessage.createdAt),
        tick: isMine ? sendTickFor(lastMessage) : null,
        unread: lastMessage.recipientId == widget.user.id && !lastMessage.isSeen,
        onTap: () => _open(send),
      );

      entries.add(
        dateLabel == prevLabel
            ? row
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [GameHistoryDateHeader(label: dateLabel, theme: theme), row],
              ),
      );
    }
    if (_loadingMore) {
      entries.add(
        const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator())),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        children: entries,
      ),
    );
  }

  String _formattedTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
