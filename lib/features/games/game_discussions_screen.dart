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
import '../home/tab_navigation_controller.dart';
import 'game_box_history_screen.dart';
import 'game_service.dart';
import 'games_menu_screen.dart';

/// Onglet "Discussions" (voir demande utilisateur : "une icône dans la barre
/// de navigation à côté de Jeux qui permet de voir rapidement et
/// directement les discussions liées aux jeux") — même liste que
/// GameBoxHistoryScreen, mais TOUS jeux et toutes boîtes confondus (voir
/// SendController::index avec `type=game_card`), au lieu d'une seule boîte
/// ouverte depuis l'éventail de cartes.
class GameDiscussionsScreen extends StatefulWidget {
  final AppUser user;

  // Rang de cet onglet dans MainTabScreen/AppShell — sert à recharger la
  // liste à chaque retour sur l'onglet (il reste vivant dans l'IndexedStack).
  static const tabIndex = 3;

  const GameDiscussionsScreen({super.key, required this.user});

  @override
  State<GameDiscussionsScreen> createState() => _GameDiscussionsScreenState();
}

class _GameDiscussionsScreenState extends State<GameDiscussionsScreen> {
  static const _pageSize = 20;

  List<Send>? _sends;
  bool _loading = true;
  bool _error = false;
  int _page = 1;
  bool _hasMore = false;
  bool _loadingMore = false;
  bool _opening = false;
  final _scrollController = ScrollController();

  // Jeux et boîtes, chargés à la demande : la liste n'a que les ids
  // (voir GameCardSend.gameId/gameBoxId), GameCardThreadScreen a besoin des
  // objets complets.
  Map<String, Game> _games = {};
  final Map<String, List<GameBox>> _boxesByGame = {};

  String? _subscribedBoxId;
  StreamSubscription<void>? _resyncSub;
  // Rechargement groupé après un événement temps réel (voir _scheduleReload).
  Timer? _reloadDebounce;
  int _lastTabIndex = TabNavigationController.instance.index;

  @override
  void initState() {
    super.initState();
    _load();
    _loadGames();
    // La Box du couple n'est pas forcément encore chargée quand cet onglet
    // est créé (il l'est dès le lancement, dans l'IndexedStack) : on
    // s'abonne dès qu'elle est connue, et on suit un éventuel changement.
    BoxService.instance.addListener(_syncRealtimeSubscription);
    _syncRealtimeSubscription();
    // Retour au premier plan / reconnexion : des événements ont pu être
    // manqués pendant l'absence (voir RealtimeClient.requestResync).
    _resyncSub = RealtimeClient.instance.resyncRequests.listen((_) => _load());
    TabNavigationController.instance.addListener(_onTabChanged);
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
    TabNavigationController.instance.removeListener(_onTabChanged);
    BoxService.instance.removeListener(_syncRealtimeSubscription);
    _resyncSub?.cancel();
    _reloadDebounce?.cancel();
    _scrollController.dispose();
    if (_subscribedBoxId != null) {
      RealtimeClient.instance.unsubscribeFromBox(_subscribedBoxId!, onEvent: _onRealtimeEvent);
    }
    super.dispose();
  }

  /// Recharge en arrivant sur l'onglet — le temps réel couvre ce qui arrive
  /// pendant que l'app est ouverte, pas ce qui a pu être manqué entre-temps.
  void _onTabChanged() {
    final index = TabNavigationController.instance.index;
    if (index == GameDiscussionsScreen.tabIndex && _lastTabIndex != index) _load();
    _lastTabIndex = index;
  }

  Future<void> _load() async {
    try {
      final sends = await ContentService.instance.fetchSends(type: 'game_card', limit: _pageSize);
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
      final next = await ContentService.instance.fetchSends(type: 'game_card', page: _page + 1, limit: _pageSize);
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

  Future<void> _loadGames() async {
    try {
      final games = await GameService.instance.fetchGames();
      if (!mounted) return;
      setState(() => _games = {for (final g in games) g.id: g});
    } catch (_) {
      // Sans les jeux, les lignes n'affichent que le nom de la boîte ;
      // _open() réessaie de toute façon au moment d'ouvrir une discussion.
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
    // Box connue (éventuellement après coup) : la liste chargée avant a pu
    // manquer des envois.
    _load();
    try {
      await RealtimeClient.instance.subscribeToBox(coupleBoxId, onEvent: _onRealtimeEvent);
    } catch (_) {
      // Best effort — la liste se recharge quand même à chaque retour sur
      // l'onglet (voir _onTabChanged).
    }
  }

  /// Recharge la liste peu après un événement de jeu — filet de sécurité
  /// pour ce que la mise à jour locale ne sait pas reconstruire seule
  /// (réponse à une carte, relance, sondage...), groupé si plusieurs
  /// événements arrivent d'affilée.
  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _load();
    });
  }

  /// Même traitement que GameBoxHistoryScreen._onRealtimeEvent, sans le
  /// filtre sur une boîte précise.
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

    // Réponse dans une discussion déjà listée : remonte-la en tête avec son
    // nouvel aperçu, comme une vraie liste de conversations.
    if (send.replyToSendId != null) {
      final index = current.indexWhere((s) => s.id == send.replyToSendId);
      if (index == -1) {
        // Discussion pas encore chargée (plus ancienne que la première
        // page) : un rechargement la fera remonter en tête.
        _scheduleReload();
        return;
      }
      final thread = current[index].copyWith(latestReply: send);
      setState(() => _sends = [thread, ...current.where((s) => s.id != thread.id)]);
      return;
    }

    if (send.sendableType != 'game_card') return;
    if (current.any((s) => s.id == send.id)) return;
    setState(() => _sends = [send, ...current]);
    // L'événement ne porte pas toujours tout ce que la liste affiche
    // (expéditeur complet...) : complète avec la version serveur.
    _scheduleReload();
  }

  Future<GameBox?> _boxFor(String gameId, String gameBoxId) async {
    var boxes = _boxesByGame[gameId];
    if (boxes == null) {
      boxes = await GameService.instance.fetchBoxes(gameId);
      _boxesByGame[gameId] = boxes;
    }
    final matches = boxes.where((b) => b.id == gameBoxId);
    return matches.isEmpty ? null : matches.first;
  }

  /// Ouvre la discussion — même écran que depuis l'historique d'une boîte
  /// (voir GameBoxHistoryScreen), qui a besoin du jeu et de la boîte
  /// complets.
  Future<void> _open(Send send) async {
    final card = send.gameCard;
    if (card == null || _opening) return;
    setState(() => _opening = true);
    try {
      if (!_games.containsKey(card.gameId)) await _loadGames();
      final game = _games[card.gameId];
      final box = await _boxFor(card.gameId, card.gameBoxId);
      if (!mounted) return;
      if (game == null || box == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LocaleScope.of(context).t('game_history_load_error'))),
        );
        return;
      }
      setState(() => _opening = false);
      AppRouter.showGlobalNavBar.value = false;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GameCardThreadScreen(send: send, user: widget.user, game: game, box: box),
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
    final t = LocaleScope.of(context).t;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(
          t('game_chats_title'),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: theme.textOnBackground),
        ),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: Stack(
            children: [
              _buildBody(theme),
              if (_opening) const Positioned.fill(child: Center(child: CircularProgressIndicator())),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemePalette theme) {
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
              message: t('game_chats_empty'),
              actionLabel: t('game_chats_empty_cta'),
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => GamesMenuScreen(user: widget.user, initialCategory: 'classic')),
              ),
            ),
          ],
        ),
      );
    }

    final localeCode = LocaleScope.of(context).current.code;

    // Voir demande utilisateur : "comment faire pour faire la différence
    // des conversations pour chaque jeu" — un en-tête par JEU plutôt qu'une
    // liste unique où seule une petite ligne grise distinguait les jeux.
    // L'ordre des groupes suit la discussion la plus récente de chaque jeu
    // (premier id de jeu rencontré en parcourant `sends`, déjà trié du plus
    // récent au plus ancien par le serveur) — celui qui vient de recevoir
    // un message reste donc en tête, comme avant, juste maintenant groupé.
    // À L'INTÉRIEUR d'un groupe, les en-têtes de date restent comme avant.
    final gameOrder = <String>[];
    final byGame = <String, List<Send>>{};
    for (final send in sends) {
      final gameId = send.gameCard!.gameId;
      var group = byGame[gameId];
      if (group == null) {
        group = <Send>[];
        byGame[gameId] = group;
        gameOrder.add(gameId);
      }
      group.add(send);
    }

    final children = <Widget>[];
    for (final gameId in gameOrder) {
      final group = byGame[gameId]!;
      final game = _games[gameId];
      children.add(_GameGroupHeader(
        theme: theme,
        icon: game != null ? iconForGame(game) : Icons.style_rounded,
        name: game?.nameFor(localeCode) ?? group.first.gameCard!.gameBoxTitleFor(localeCode),
      ));

      for (var i = 0; i < group.length; i++) {
        final send = group[i];
        final card = send.gameCard!;
        final lastMessage = send.lastMessage;
        final isMine = lastMessage.senderId == widget.user.id;
        final senderName = lastMessage.sender?.prenom ?? lastMessage.sender?.name ?? t('game_partner_name_fallback');
        final by = t('game_sent_by', {'sender': isMine ? t('game_sent_by_you') : senderName});
        // Le nom du jeu est déjà dans l'en-tête ci-dessus — seule la
        // catégorie (boîte) reste utile ici, pour ne pas le répéter.
        final subtitle = '${card.gameBoxTitleFor(localeCode)} · $by';

        final dateLabel = dateHeaderLabel(context, lastMessage.createdAt.toLocal());
        final prevLabel = i == 0 ? null : dateHeaderLabel(context, group[i - 1].lastMessage.createdAt.toLocal());
        final nextLabel = i == group.length - 1 ? null : dateHeaderLabel(context, group[i + 1].lastMessage.createdAt.toLocal());

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

        children.add(
          dateLabel == prevLabel
              ? row
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [GameHistoryDateHeader(label: dateLabel, theme: theme), row],
                ),
        );
      }
    }
    if (_loadingMore) {
      children.add(
        const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator())),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        children: children,
      ),
    );
  }

  String _formattedTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

/// En-tête de groupe "un jeu" — voir demande utilisateur : "faire la
/// différence des conversations pour chaque jeu". Bien plus visible que le
/// nom du jeu noyé dans la ligne grise (voir GameHistoryRow.subtitle,
/// désormais réduite à la catégorie/expéditeur) : icône + nom, en gras, en
/// tête de chaque groupe.
class _GameGroupHeader extends StatelessWidget {
  final ThemePalette theme;
  final IconData icon;
  final String name;

  const _GameGroupHeader({required this.theme, required this.icon, required this.name});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: theme.primary.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: theme.primary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w800, color: theme.textOnBackground),
            ),
          ),
        ],
      ),
    );
  }
}
