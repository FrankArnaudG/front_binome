import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/app_router.dart';
import '../../core/realtime_client.dart';
import '../../l10n/locale_scope.dart';
import '../../models/app_user.dart';
import '../../models/emoji_story_session.dart';
import '../../models/game.dart';
import '../../models/send.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/send_status_tick.dart';
import '../box/box_scope.dart';
import '../box/box_service.dart';
import 'emoji_story_session_screen.dart';
import 'game_service.dart';

/// Liste des discussions "Devine mon émoji" (voir
/// EmojiStoryController::sessions) — équivalent de GameBoxHistoryScreen pour
/// ce jeu : chaque "plan de jeu" (voir EmojiStorySession) est sa PROPRE
/// discussion continue, avec potentiellement plusieurs stories échangées
/// dans le même fil au fil du temps (voir EmojiStorySessionScreen), jamais
/// mélangées avec celles d'une autre discussion. Ouvre soit une discussion
/// existante, soit un nouveau "plan de jeu" (fil vide prêt à composer).
class EmojiStoryHistoryScreen extends StatefulWidget {
  final Game game;
  final AppUser user;

  const EmojiStoryHistoryScreen({super.key, required this.game, required this.user});

  @override
  State<EmojiStoryHistoryScreen> createState() => _EmojiStoryHistoryScreenState();
}

class _EmojiStoryHistoryScreenState extends State<EmojiStoryHistoryScreen> {
  List<EmojiStorySession>? _sessions;
  bool _loading = true;
  bool _error = false;
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
  /// GameService.cachedEmojiStorySessions), avant même la réponse réseau,
  /// comme GameBoxHistoryScreen/TimelineScreen.
  Future<void> _loadCachedThenRefresh() async {
    try {
      final cached = await GameService.instance.cachedEmojiStorySessions(widget.game.id);
      if (cached != null && mounted) {
        setState(() {
          _sessions = cached.items;
          _hasMore = cached.hasMore;
          _loading = false;
        });
      }
    } catch (_) {
      // Ignoré — le fetch réseau ci-dessous fait foi.
    }
    await _load();
  }

  Future<void> _load() async {
    try {
      final page = await GameService.instance.fetchEmojiStorySessions(widget.game.id);
      if (!mounted) return;
      setState(() {
        _sessions = page.items;
        _hasMore = page.hasMore;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_sessions == null) _error = true;
      });
    }
  }

  /// Discussions moins récemment actives que celles déjà affichées — même
  /// principe que GameBoxHistoryScreen._loadMore.
  Future<void> _loadMore() async {
    final sessions = _sessions;
    if (!_hasMore || _loadingMore || sessions == null || sessions.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await GameService.instance.fetchEmojiStorySessions(
        widget.game.id,
        beforeId: sessions.last.lastActivityAt.toIso8601String(),
      );
      if (!mounted) return;
      setState(() {
        _sessions = [...sessions, ...page.items];
        _hasMore = page.hasMore;
      });
    } catch (_) {
      // best effort — l'utilisateur pourra réessayer en re-scrollant.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _initRealtime() async {
    final coupleBoxId = BoxService.instance.currentBox?.id;
    if (coupleBoxId == null) return;
    _subscribedBoxId = coupleBoxId;
    try {
      await RealtimeClient.instance.subscribeToBox(coupleBoxId, onEvent: _onRealtimeEvent);
    } catch (_) {
      // Best effort — la liste reste utilisable, juste sans mise à jour
      // immédiate des nouvelles discussions.
    }
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.event == 'SendCreated') {
      final sendJson = event.data?['send'] as Map<String, dynamic>?;
      if (sendJson == null) return;
      final send = Send.fromJson(sendJson);
      final sessionId = send.emojiStory?.sessionId;
      if (send.sendableType != 'emoji_story' || sessionId == null) return;
      if (!mounted) return;
      _bumpSession(sessionId, latestSend: send, lastActivityAt: send.createdAt);
      return;
    }
    if (event.event == 'EmojiStoryUpdated') {
      final sendJson = event.data?['send'] as Map<String, dynamic>?;
      if (sendJson == null) return;
      final updated = Send.fromJson(sendJson);
      final sessionId = updated.emojiStory?.sessionId;
      if (sessionId == null) return;
      if (!mounted) return;
      _bumpSession(sessionId, latestSend: updated, lastActivityAt: DateTime.now());
      return;
    }
    if (event.event == 'SendSeen') {
      final sendId = event.data?['send_id'] as String?;
      if (sendId == null) return;
      final seenAtStr = event.data?['seen_at'] as String?;
      _applyStatus(sendId, status: 'seen', seenAt: seenAtStr != null ? DateTime.parse(seenAtStr) : DateTime.now());
      return;
    }
    if (event.event == 'SendDelivered') {
      final sendIds = (event.data?['send_ids'] as List?)?.map((e) => e as String).toList();
      if (sendIds == null || sendIds.isEmpty) return;
      final deliveredAtStr = event.data?['delivered_at'] as String?;
      final deliveredAt = deliveredAtStr != null ? DateTime.parse(deliveredAtStr) : DateTime.now();
      for (final id in sendIds) {
        _applyStatus(id, status: 'delivered', deliveredAt: deliveredAt);
      }
    }
  }

  /// Fait remonter une discussion en tête de liste dès qu'une activité la
  /// concerne — nouvelle story, devinette, verdict, édition, suppression
  /// (voir EmojiStoryController::broadcastUpdate, qui touche last_activity_at
  /// pour TOUTE activité) — façon vraie liste de conversations. [latestSend]
  /// ne remplace l'aperçu que si cet envoi EST la story la plus récente de
  /// la discussion (une activité sur une story plus ancienne fait quand même
  /// remonter la discussion, sans changer l'aperçu affiché).
  void _bumpSession(String sessionId, {required Send latestSend, required DateTime lastActivityAt}) {
    final current = _sessions ?? [];
    final index = current.indexWhere((s) => s.id == sessionId);
    late final EmojiStorySession updated;
    final rest = List<EmojiStorySession>.of(current);
    if (index == -1) {
      // Nouvelle discussion démarrée (par moi ou mon binôme) pendant que la
      // liste est déjà ouverte.
      updated = EmojiStorySession(id: sessionId, gameId: widget.game.id, lastActivityAt: lastActivityAt, latestSend: latestSend);
    } else {
      final existing = rest.removeAt(index);
      final keepPreview = existing.latestSend.id != latestSend.id && existing.latestSend.createdAt.isAfter(latestSend.createdAt);
      updated = EmojiStorySession(
        id: existing.id,
        gameId: existing.gameId,
        lastActivityAt: lastActivityAt,
        latestSend: keepPreview ? existing.latestSend : latestSend,
      );
    }
    setState(() => _sessions = [updated, ...rest]);
  }

  void _applyStatus(String sendId, {required String status, DateTime? seenAt, DateTime? deliveredAt}) {
    final current = _sessions;
    if (current == null) return;
    final index = current.indexWhere((s) => s.latestSend.id == sendId);
    if (index == -1) return;
    final existing = current[index];
    if (existing.latestSend.status != 'sent' && status == 'delivered') return;
    setState(() {
      final copy = List<EmojiStorySession>.of(current);
      copy[index] = EmojiStorySession(
        id: existing.id,
        gameId: existing.gameId,
        lastActivityAt: existing.lastActivityAt,
        latestSend: existing.latestSend.copyWith(status: status, seenAt: seenAt, deliveredAt: deliveredAt),
      );
      _sessions = copy;
    });
  }

  Future<void> _openThread({EmojiStorySession? session}) async {
    // Renforce le masquage fait dans EmojiStorySessionScreen.initState (voir
    // TimelineScreen._openSend pour le même principe côté SlideDetailScreen)
    // — appartient au call-site, pas seulement à l'écran poussé.
    AppRouter.showGlobalNavBar.value = false;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmojiStorySessionScreen(game: widget.game, user: widget.user, sessionId: session?.id),
      ),
    );
    AppRouter.showGlobalNavBar.value = true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final partnerName = BoxScope.of(context).currentBox?.partnerOf(widget.user.id)?.prenom ?? 'ton/ta partenaire';

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(
          widget.game.nameFor(LocaleScope.of(context).current.code),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
      ),
      body: ThemedBackground(
        child: SafeArea(child: _buildBody(theme, partnerName)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openThread(),
        backgroundColor: theme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          LocaleScope.of(context).t('emoji_story_new_thread_button'),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
    );
  }

  static const _weekdayKeys = [
    'weekday_monday',
    'weekday_tuesday',
    'weekday_wednesday',
    'weekday_thursday',
    'weekday_friday',
    'weekday_saturday',
    'weekday_sunday',
  ];
  static const _monthKeys = [
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

  /// Même vocabulaire de séparateur de date que GameBoxHistoryScreen/
  /// TimelineScreen — pour que tous les écrans d'historique se lisent
  /// comme un seul système.
  String _dateHeaderFor(DateTime dt) {
    final t = LocaleScope.of(context).t;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(date).inDays;
    if (diff == 0) return t('date_today');
    if (diff == 1) return t('date_yesterday');
    final weekday = t(_weekdayKeys[dt.weekday - 1]);
    if (diff < 7) return weekday;
    return '$weekday ${dt.day} ${t(_monthKeys[dt.month - 1])}';
  }

  List<_HistoryEntry> _groupByDate(List<EmojiStorySession> sessions) {
    final entries = <_HistoryEntry>[];
    for (var i = 0; i < sessions.length; i++) {
      final session = sessions[i];
      final header = _dateHeaderFor(session.lastActivityAt);
      final prevHeader = i == 0 ? null : _dateHeaderFor(sessions[i - 1].lastActivityAt);
      final nextHeader = i == sessions.length - 1 ? null : _dateHeaderFor(sessions[i + 1].lastActivityAt);
      final isFirstInGroup = header != prevHeader;
      final isLastInGroup = header != nextHeader;
      if (isFirstInGroup) entries.add(_HistoryEntry.header(header));
      entries.add(_HistoryEntry.session(session, isFirstInGroup: isFirstInGroup, isLastInGroup: isLastInGroup));
    }
    return entries;
  }

  /// Légende de statut d'une discussion (à partir de sa story la plus
  /// récente) — croise les getters déjà exposés par EmojiStorySend avec qui,
  /// entre moi et mon binôme, est composeur/composeuse (sender) vs
  /// devineur/devineuse (recipient) de CETTE story.
  String _statusCaption(Send send, String partnerName) {
    final story = send.emojiStory;
    if (story == null) return '';
    final t = LocaleScope.of(context).t;
    if (story.isDeleted) return t('emoji_story_status_deleted');
    final isMine = send.senderId == widget.user.id;
    if (story.needsGuess) {
      return isMine
          ? t('emoji_story_status_waiting_guess', {'name': partnerName})
          : t('emoji_story_status_your_turn_guess');
    }
    if (story.needsVerdict) {
      return isMine
          ? t('emoji_story_status_your_turn_verdict')
          : t('emoji_story_status_waiting_verdict', {'name': partnerName});
    }
    if (story.isResolved) {
      return story.won == true
          ? t('emoji_story_status_won')
          : t('emoji_story_status_lost');
    }
    return '';
  }

  Widget _buildBody(ThemePalette theme, String partnerName) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error) {
      return const Center(
        child: EmptyState(icon: Icons.wifi_off_rounded, message: 'Impossible de charger les discussions.'),
      );
    }
    final sessions = _sessions ?? [];
    if (sessions.isEmpty) {
      return Center(
        child: EmptyState(
          icon: Icons.emoji_emotions_rounded,
          message: "Aucune devinette pour l'instant.\nLance le premier plan de jeu avec $partnerName !",
        ),
      );
    }

    final entries = _groupByDate(sessions);
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 90),
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
          return _DateHeaderLabel(label: entry.header!, theme: theme);
        }

        final session = entry.session!;
        final send = session.latestSend;
        final isMine = send.senderId == widget.user.id;

        return _HistoryRow(
          theme: theme,
          send: send,
          isFirstInGroup: entry.isFirstInGroup,
          isLastInGroup: entry.isLastInGroup,
          emojis: send.emojiStory?.emojis ?? '🔮',
          subtitle: _statusCaption(send, partnerName),
          time: _formattedTime(session.lastActivityAt),
          tick: isMine ? sendTickFor(send) : null,
          // Le dernier envoi de cette discussion m'a été adressé et je ne
          // l'ai pas encore ouvert — même repère que TimelineScreen (Carnet
          // de bord) et GameBoxHistoryScreen, pour un langage visuel
          // cohérent sur toutes les listes de discussions de l'app.
          unread: send.recipientId == widget.user.id && !send.isSeen,
          onTap: () async {
            await _openThread(session: session);
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

class _HistoryEntry {
  final String? header;
  final EmojiStorySession? session;
  final bool isFirstInGroup;
  final bool isLastInGroup;

  const _HistoryEntry.header(this.header) : session = null, isFirstInGroup = false, isLastInGroup = false;

  const _HistoryEntry.session(this.session, {required this.isFirstInGroup, required this.isLastInGroup}) : header = null;

  bool get isHeader => header != null;
}

class _DateHeaderLabel extends StatelessWidget {
  final String label;
  final ThemePalette theme;

  const _DateHeaderLabel({required this.label, required this.theme});

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

/// Une ligne = une discussion — design plat/monochrome (une seule teinte,
/// [theme.primary]/[theme.surface] en opacités, aucun dégradé), même parti
/// pris que les bulles de "Devine mon émoji" et le scoreboard "match".
class _HistoryRow extends StatelessWidget {
  final ThemePalette theme;
  final Send send;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final String emojis;
  final String subtitle;
  final String time;
  final SendTick? tick;
  final bool unread;
  final VoidCallback onTap;

  const _HistoryRow({
    required this.theme,
    required this.send,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    required this.emojis,
    required this.subtitle,
    required this.time,
    required this.tick,
    required this.unread,
    required this.onTap,
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
                color: theme.surface,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onTap,
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
                                emojis,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 18, height: 1.2),
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
                            // TimelineScreen (Carnet de bord) et
                            // GameBoxHistoryScreen, pour un langage visuel
                            // cohérent sur toutes les listes de discussions.
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
