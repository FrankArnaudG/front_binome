import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../core/app_router.dart';
import '../../core/feature_flags_service.dart';
import '../../core/realtime_client.dart';
import '../../core/timeline_refresh_signal.dart';
import '../../l10n/locale_scope.dart';
import '../../models/app_user.dart';
import '../../models/doodle.dart';
import '../../models/send.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/binome_wordmark.dart';
import '../../widgets/coin_balance_badge.dart';
import '../../widgets/coin_icon.dart';
import '../../widgets/composer_actions.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/send_status_tick.dart';
import '../box/box_scope.dart';
import '../box/couple_profile_screen.dart';
import '../doodle/doodle_history_screen.dart';
import '../doodle/doodle_service.dart';
import '../home/tab_navigation_controller.dart';
import '../home/widgets/couple_avatars_badge.dart';
import '../shop/shop_screen.dart';
import '../shop/wallet_balance_notifier.dart';
import 'content_service.dart';
import 'packs_screen.dart';
import 'slide_detail_screen.dart';
import 'unread_timeline_service.dart';

enum _GalleryFilter { all, favorites, gifts, poems, heartbeats }

class TimelineScreen extends StatefulWidget {
  final AppUser user;

  const TimelineScreen({super.key, required this.user});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  // État explicite plutôt qu'un FutureBuilder : on veut pouvoir afficher le
  // cache (voir LocalCache/ContentService.cachedSends) immédiatement au
  // premier rendu SANS jamais montrer de loader tant qu'on a déjà quelque
  // chose à l'écran — le réseau ne fait ensuite que rafraîchir discrètement
  // par-dessus. Un FutureBuilder recommence toujours par
  // ConnectionState.waiting, incompatible avec ce besoin.
  List<Send>? _sends;
  bool _initialLoading = true;
  bool _loadError = false;
  // "Petits mots" (voir demande utilisateur) — une seule discussion pour
  // tous les doodles échangés, fusionnée dans ce fil et repositionnée
  // selon le DERNIER envoi (voir _groupByDate) plutôt que d'être une
  // capsule à part par doodle.
  List<Doodle>? _doodles;
  Doodle? get _lastDoodle => (_doodles == null || _doodles!.isEmpty) ? null : _doodles!.last;
  _GalleryFilter _filter = _GalleryFilter.all;
  // Pagination : seule la première page est mise en cache (voir
  // ContentService.fetchSends) et affichée d'entrée — le reste de
  // l'historique se charge au scroll vers le bas (voir _loadMore), plutôt
  // que de tout récupérer d'un coup pour un Carnet de bord qui peut
  // grossir indéfiniment.
  static const _pageSize = 20;
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;
  final ScrollController _scrollController = ScrollController();
  // L'écran reste vivant dans l'IndexedStack (voir MainTabScreen) sans se
  // reconstruire tout seul — sans ce tick, "il y a 2 min" resterait figé
  // indéfiniment tant qu'on ne quitte/revient pas sur cet onglet ou qu'on
  // ne tire pas pour rafraîchir. Rejoue juste le rendu (_relativeTime lit
  // DateTime.now() à chaque appel), aucun appel réseau.
  Timer? _tickTimer;

  // Réglable depuis l'espace admin (voir HeartbeatSetting), affiché sur le
  // menu "+" comme sur la tuile équivalente du Dashboard (voir
  // DarkQuickActionsGrid._loadHeartbeatPrice) — échec silencieux, le menu
  // reste utilisable sans badge plutôt que de bloquer.
  int? _heartbeatPrice;

  // Voir _onRealtimeEvent — sans cet abonnement, les doubles-coches "reçu"/
  // "lu" de cette liste ne se mettaient jamais à jour tant qu'on regardait
  // l'écran (juste au prochain rafraîchissement complet, voir demande
  // utilisateur : vérifier que le temps réel fonctionne partout où ces
  // symboles existent). Toutes les autres listes de discussions de l'app
  // (historique de boîte de jeu, "Devine mon émoji", fil d'un poème) s'y
  // abonnaient déjà ; seul le Carnet de bord ne le faisait pas.
  String? _subscribedBoxId;

  // Voir demande utilisateur : même en-tête que l'onglet Duo, avatars +
  // pastille de présence comprises (voir DashboardTab, copié à l'identique
  // sur cet abonnement déjà existant plutôt que d'en ouvrir un second).
  String? _partnerId;
  bool _partnerPresent = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _loadHeartbeatPrice();
    TimelineRefreshSignal.instance.addListener(_refresh);
    FeatureFlagsService.instance.addListener(_onFeatureFlagsChanged);
    // 15s plutôt que 60s : sinon un envoi tout juste arrivé reste affiché
    // "À l'instant" bien après la minute écoulée, le temps du prochain
    // tick — constaté en réel.
    _tickTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
    _scrollController.addListener(() {
      if (!_hasMore || _loadingMore || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.pixels >= position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // BoxScope a besoin du context, donc ici plutôt que initState — ne
    // réagit qu'à un VRAI changement de box (jumelage/séparation), pas à
    // chaque appel (voir la garde sur _subscribedBoxId).
    final box = BoxScope.of(context).currentBox;
    final boxId = box?.id;
    if (boxId != null && boxId != _subscribedBoxId) {
      if (_subscribedBoxId != null) {
        RealtimeClient.instance.unsubscribeFromBox(_subscribedBoxId!, onEvent: _onRealtimeEvent, onPresenceChange: _onPresenceChange);
      }
      _subscribedBoxId = boxId;
      _partnerId = box?.partnerOf(widget.user.id)?.id;
      RealtimeClient.instance
          .subscribeToBox(boxId, onEvent: _onRealtimeEvent, onPresenceChange: _onPresenceChange)
          .catchError((_) {
        // Best effort : sans temps réel, la liste reste utilisable, juste
        // sans mise à jour immédiate des coches "reçu"/"lu".
      });
    }
  }

  void _onPresenceChange(Set<String> memberIds) {
    if (!mounted) return;
    final present = _partnerId != null && memberIds.contains(_partnerId);
    if (present != _partnerPresent) setState(() => _partnerPresent = present);
  }

  /// Met à jour en direct les coches "reçu"/"lu" (voir SendTickIcon) des
  /// envois déjà affichés, sans re-fetch complet — même principe que
  /// GameCardThreadScreen._onRealtimeEvent/_applySeen/_applyDelivered.
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
    if (event.event == 'DoodleSent') {
      final data = event.data;
      if (data == null || !mounted) return;
      final doodle = Doodle.fromJson(data['doodle'] as Map<String, dynamic>);
      setState(() {
        final existing = _doodles ?? [];
        if (!existing.any((d) => d.id == doodle.id)) {
          _doodles = [...existing, doodle];
        }
      });
    }
  }

  /// Best-effort, indépendant du fetch des Sends ci-dessus — un échec ne
  /// doit jamais empêcher le reste du Carnet de bord de s'afficher (voir
  /// demande utilisateur, la discussion "petits mots" est un ajout, pas une
  /// dépendance dure du fil principal).
  Future<void> _refreshDoodles() async {
    try {
      final doodles = await DoodleService.instance.fetchDoodles();
      if (mounted) setState(() => _doodles = doodles);
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> _openDoodleThread() async {
    AppRouter.showGlobalNavBar.value = false;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DoodleHistoryScreen(user: widget.user)),
    );
    AppRouter.showGlobalNavBar.value = true;
    if (mounted) _refreshDoodles();
  }

  void _applySeen(String sendId, DateTime seenAt) {
    if (!mounted || _sends == null) return;
    setState(() {
      _sends = _sends!.map((s) => s.id == sendId ? s.copyWith(status: 'seen', seenAt: seenAt) : s).toList();
    });
  }

  void _applyDelivered(List<String> sendIds, DateTime deliveredAt) {
    if (!mounted || _sends == null) return;
    setState(() {
      _sends = _sends!
          .map((s) => sendIds.contains(s.id) && s.status == 'sent'
              ? s.copyWith(status: 'delivered', deliveredAt: deliveredAt)
              : s)
          .toList();
    });
  }

  @override
  void dispose() {
    if (_subscribedBoxId != null) {
      RealtimeClient.instance.unsubscribeFromBox(_subscribedBoxId!, onEvent: _onRealtimeEvent, onPresenceChange: _onPresenceChange);
    }
    TimelineRefreshSignal.instance.removeListener(_refresh);
    FeatureFlagsService.instance.removeListener(_onFeatureFlagsChanged);
    _tickTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Si le filtre actif correspond à une fonctionnalité désactivée depuis
  /// le panel admin pendant que l'écran est ouvert (ex. "Cadeaux" coupé
  /// alors que ce filtre était sélectionné), on ne laisse pas l'utilisateur
  /// bloqué dessus — retour silencieux sur "Tous".
  void _onFeatureFlagsChanged() {
    final flags = FeatureFlagsService.instance;
    final hidden = (_filter == _GalleryFilter.gifts && !flags.isEnabled('gifts')) ||
        (_filter == _GalleryFilter.heartbeats && !flags.isEnabled('heartbeat'));
    if (hidden) _setFilter(_GalleryFilter.all);
  }

  /// Affiche le cache tout de suite s'il existe (uniquement pertinent pour
  /// la vue par défaut, voir ContentService.cachedSends), puis lance quand
  /// même le vrai fetch réseau derrière pour rafraîchir — sans jamais
  /// remontrer de loader une fois que quelque chose est déjà affiché.
  Future<void> _loadInitial() async {
    if (_filter == _GalleryFilter.all) {
      final cached = await ContentService.instance.cachedSends();
      if (cached != null && mounted) {
        setState(() {
          _sends = cached;
          _initialLoading = false;
        });
      }
      // Même principe pour "Petits mots" (voir DoodleService.cachedDoodles)
      // — sans ça, l'entrée du fil de doodles n'apparaissait qu'après le
      // fetch réseau, un temps après les Sends déjà affichés depuis le
      // cache (voir demande utilisateur : "ça n'apparaît pas immédiatement
      // comme les autres").
      final cachedDoodles = await DoodleService.instance.cachedDoodles();
      if (cachedDoodles != null && mounted) {
        setState(() => _doodles = cachedDoodles);
      }
    }
    await _refresh();
  }

  String? get _typeForFilter => switch (_filter) {
        _GalleryFilter.gifts => 'gift',
        _GalleryFilter.poems => 'pack',
        _GalleryFilter.heartbeats => 'heartbeat',
        _ => null,
      };

  Future<List<Send>> _fetch({int page = 1}) {
    return ContentService.instance.fetchSends(
      page: page,
      limit: _pageSize,
      favoriteOnly: _filter == _GalleryFilter.favorites,
      type: _typeForFilter,
    );
  }

  /// Recharge la première page — pull-to-refresh, changement de filtre, ou
  /// signal externe (nouvel envoi, voir TimelineRefreshSignal). Remplace
  /// entièrement la liste plutôt que de fusionner : un rafraîchissement
  /// explicite revient à la page 1, remonter à l'historique déjà chargé
  /// via [_loadMore] se refait ensuite au scroll si besoin.
  Future<void> _refresh() async {
    try {
      final sends = await _fetch(page: 1);
      if (mounted) {
        setState(() {
          _sends = sends;
          _initialLoading = false;
          _loadError = false;
          _page = 1;
          _hasMore = sends.length >= _pageSize;
        });
      }
      // Recalcule la pastille de l'onglet en même temps — seulement pour la
      // vue par défaut (voir UnreadTimelineService, basé sur le même fetch
      // sans filtre ni favori que cette page 1).
      if (_filter == _GalleryFilter.all) {
        UnreadTimelineService.instance.refresh(widget.user.id);
        _refreshDoodles();
      }
    } catch (_) {
      // Rien de nouveau à montrer : on garde silencieusement ce qui est
      // déjà affiché (cache ou fetch précédent) plutôt que de basculer sur
      // un état d'erreur — seul le tout premier chargement, sans rien à
      // montrer, doit signaler l'échec (voir build()).
      if (mounted && _sends == null) {
        setState(() {
          _initialLoading = false;
          _loadError = true;
        });
      }
    }
  }

  /// Page suivante — déclenché en approchant le bas de l'écran (voir le
  /// ScrollController dans initState). Une page renvoyant moins que
  /// [_pageSize] éléments signale la fin de l'historique, sans avoir
  /// besoin de lire la pagination Laravel côté client.
  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _sends == null) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final more = await _fetch(page: nextPage);
      if (mounted) {
        setState(() {
          _sends = [...?_sends, ...more];
          _page = nextPage;
          _hasMore = more.length >= _pageSize;
        });
      }
    } catch (_) {
      // best effort — se retente en re-scrollant.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _setFilter(_GalleryFilter filter) {
    if (filter == _filter) return;
    setState(() {
      _filter = filter;
      // Changer de filtre n'a pas de cache (voir ContentService) — repasse
      // par un vrai chargement le temps de la requête.
      _sends = null;
      _initialLoading = true;
      _loadError = false;
    });
    _refresh();
  }

  Future<void> _openSend(Send send) async {
    if (send.recipientId == widget.user.id && !send.isSeen) {
      try {
        await ContentService.instance.markSeen(send.id);
        UnreadTimelineService.instance.decrement();
      } catch (_) {
        // best effort
      }
    }
    if (!mounted) return;

    // Écran immersif façon chat : la barre de navigation globale de
    // l'AppShell (persistante au-dessus de TOUT le Navigator) ne doit pas
    // rester visible en dessous — masquée le temps de l'ouverture, remise
    // au retour.
    AppRouter.showGlobalNavBar.value = false;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SlideDetailScreen(
          send: send,
          isMine: send.senderId == widget.user.id,
          user: widget.user,
        ),
      ),
    );
    AppRouter.showGlobalNavBar.value = true;
    if (mounted) _refresh();
  }

  /// Bouton "+" façon WhatsApp — petit menu de choix plutôt qu'une action
  /// unique directe (voir demande utilisateur), chaque option réutilise un
  /// flux d'envoi déjà existant ailleurs dans l'app (Dashboard) plutôt que
  /// de le dupliquer.
  Future<void> _openComposeMenu() async {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;
    final flags = FeatureFlagsService.instance;

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
                icon: Icons.auto_stories_rounded,
                label: t('cta_send_thought'),
                onTap: () => Navigator.of(sheetContext).pop('poem'),
              ),
              if (flags.isEnabled('heartbeat')) ...[
                const SizedBox(height: 8),
                ComposeMenuTile(
                  theme: theme,
                  icon: Icons.favorite_rounded,
                  label: t('heartbeat_label'),
                  onTap: () => Navigator.of(sheetContext).pop('heartbeat'),
                ),
              ],
              const SizedBox(height: 8),
              ComposeMenuTile(
                theme: theme,
                icon: Icons.sports_esports_rounded,
                label: t('action_games'),
                onTap: () => Navigator.of(sheetContext).pop('games'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || choice == null) return;
    switch (choice) {
      case 'poem':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PacksScreen()));
      case 'heartbeat':
        _openHeartbeatOptions();
      case 'games':
        // Jeux est un onglet du même shell (voir MainTabScreen) : on bascule
        // dessus plutôt que de le pousser en second exemplaire — même
        // principe que DarkQuickActionsGrid pour la tuile équivalente du
        // Dashboard.
        TabNavigationController.instance.setIndex(2);
    }
  }

  // Réglable depuis l'espace admin (voir HeartbeatSetting) — affiché sur la
  // modale, même repli silencieux que DarkQuickActionsGrid._loadHeartbeatPrice
  // si l'appel échoue (menu utilisable sans badge plutôt que bloqué).
  Future<void> _loadHeartbeatPrice() async {
    try {
      final price = await ContentService.instance.fetchHeartbeatPrice();
      if (mounted) setState(() => _heartbeatPrice = price);
    } catch (_) {}
  }

  bool _sendingHeartbeat = false;

  /// Même choix que la tuile "Faire battre son cœur" du Dashboard à l'appui
  /// long (voir DarkQuickActionsGrid._openHeartbeatOptions) — reproduit ici
  /// à l'identique pour le bouton "+" du Carnet de bord (voir demande
  /// utilisateur).
  Future<void> _openHeartbeatOptions() async {
    if (_sendingHeartbeat) return;
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;
    // Un sous-titre différent tiré au hasard parmi 4 à chaque ouverture de
    // la feuille (voir demande utilisateur).
    final randomSubtitleKey = 'heartbeat_option_random_subtitle_${math.Random().nextInt(4) + 1}';
    final customSubtitleKey = 'heartbeat_option_custom_subtitle_${math.Random().nextInt(4) + 1}';

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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t('heartbeat_label'),
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: theme.textOnBackground),
                    ),
                  ),
                  if (_heartbeatPrice != null)
                    _PriceBadge(coinPrice: _heartbeatPrice!, coinSize: 14, fontSize: 13),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                t('heartbeat_sheet_subtitle'),
                style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
              ),
              const SizedBox(height: 18),
              _HeartbeatOptionTile(
                theme: theme,
                icon: Icons.auto_awesome_rounded,
                title: t('heartbeat_option_random_title'),
                subtitle: t(randomSubtitleKey),
                onTap: () => Navigator.of(sheetContext).pop('random'),
              ),
              const SizedBox(height: 10),
              _HeartbeatOptionTile(
                theme: theme,
                icon: Icons.edit_note_rounded,
                title: t('heartbeat_option_custom_title'),
                subtitle: t(customSubtitleKey),
                onTap: () => Navigator.of(sheetContext).pop('custom'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || choice == null) return;
    if (choice == 'random') {
      _sendHeartbeat();
    } else {
      _composeCustomHeartbeat();
    }
  }

  Future<void> _composeCustomHeartbeat() async {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;
    final controller = TextEditingController();

    final message = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(t('heartbeat_compose_title'), style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 140,
          maxLines: 3,
          style: GoogleFonts.nunito(color: theme.textOnBackground),
          cursorColor: theme.primary,
          decoration: InputDecoration(
            hintText: t('heartbeat_compose_hint'),
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
            child: Text(t('heartbeat_send_button')),
          ),
        ],
      ),
    );

    if (message != null && message.isNotEmpty) {
      _sendHeartbeat(message: message);
    }
  }

  Future<void> _sendHeartbeat({String? message}) async {
    if (_sendingHeartbeat) return;
    setState(() => _sendingHeartbeat = true);
    try {
      final send = await ContentService.instance.sendHeartbeat(message: message);
      await WalletBalanceNotifier.instance.refresh();
      if (!mounted) return;
      final localeCode = LocaleScope.of(context).current.code;
      final t = LocaleScope.of(context).t;
      final partnerName = BoxScope.of(context).currentBox?.partnerOf(widget.user.id)?.prenom ?? t('common_partner_fallback');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('heartbeat_sent_snackbar', {'message': send.heartbeatMessageFor(localeCode) ?? '', 'name': partnerName}))),
      );
      _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sendingHeartbeat = false);
    }
  }

  // [send] doit être le DERNIER message de la discussion (voir
  // Send.lastMessage), jamais l'envoi racine brut — sinon une discussion
  // relancée par un message texte/emoji resterait figée sur son ouverture
  // dans la liste, plutôt que de refléter le tout dernier échange.
  String _mainText(Send send) {
    final localeCode = LocaleScope.of(context).current.code;
    if (send.isPack) return send.pack?.titleFor(localeCode) ?? 'Un poème';
    if (send.isGift) return send.gift?.name ?? 'Un cadeau';
    if (send.isHeartbeat) return send.heartbeatMessageFor(localeCode) ?? 'Un cœur qui bat pour toi 💓';
    if (send.isEmojiReply) return send.emojiReplyText ?? '💬';
    if (send.isTextReply) return send.textReplyText ?? '';
    return send.slide?.textFor(localeCode) ?? '';
  }

  String _title(Send send, bool isMine) {
    final t = LocaleScope.of(context).t;
    final fallback = t('common_partner_fallback');
    // Le nom qui compte dépend du sens : "X vous a envoyé..." a besoin de
    // l'expéditeur·rice, mais "Un poème s'est envolé vers X" (soi-même
    // expéditeur·rice) a besoin du·de la destinataire — jamais le même
    // qu'isMine, sans quoi {name} pointait sur la mauvaise personne (ou
    // restait tel quel côté "mine", faute de paramètre transmis).
    final senderName = send.sender?.prenom ?? fallback;
    final recipientName = send.recipient?.prenom ?? fallback;

    if (send.isGift) {
      return isMine ? t('timeline_title_gift_mine') : t('timeline_title_gift_partner', {'name': senderName});
    }
    if (send.isHeartbeat) {
      return isMine ? t('timeline_title_heartbeat_mine') : t('timeline_title_heartbeat_partner', {'name': senderName});
    }
    if (send.isEmojiReply || send.isTextReply) {
      return isMine ? t('timeline_title_message_mine') : t('timeline_title_message_partner', {'name': senderName});
    }
    return isMine
        ? t('timeline_title_poem_mine', {'name': recipientName})
        : t('timeline_title_poem_partner', {'name': senderName});
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return "À l'instant";
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays} j';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
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

  /// Étiquette de séparateur de date façon fil d'actualité : "Aujourd'hui",
  /// "Hier", le jour de la semaine seul si récent, sinon "Lundi 13 juillet".
  String _dateHeaderFor(DateTime dt) {
    final t = LocaleScope.of(context).t;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(date).inDays;
    if (diff == 0) return t('date_today');
    if (diff == 1) return t('date_yesterday');
    if (diff < 7) {
      final weekday = t(_weekdayKeys[dt.weekday - 1]);
      return weekday.isEmpty ? weekday : weekday[0].toUpperCase() + weekday.substring(1);
    }
    // Au-delà d'une semaine, plus de nom de jour mais l'année (voir capture
    // de référence WhatsApp utilisateur : "4 juillet 2026", pas de jour de
    // semaine pour une date ancienne).
    return '${dt.day} ${t(_monthKeys[dt.month - 1])} ${dt.year}';
  }

  /// Aplatit la liste en une seule séquence d'en-têtes de date + envois,
  /// avec des marqueurs de première/dernière position dans leur groupe pour
  /// que le fil vertical ne dépasse jamais d'un jour à l'autre. Fusionne
  /// aussi le fil "petits mots" (voir demande utilisateur) — [lastDoodle]
  /// (le doodle le plus récent, toute la discussion vit derrière une seule
  /// entrée) est trié par date exactement comme un Send, pour qu'il se
  /// repositionne dans le Carnet de bord selon le dernier envoi plutôt que
  /// de rester figé à un endroit fixe.
  List<_TimelineEntry> _groupByDate(List<Send> sends, Doodle? lastDoodle) {
    final rows = <(DateTime sortTime, Send? send, Doodle? doodle)>[
      for (final send in sends) (send.createdAt, send, null),
      if (lastDoodle != null) (lastDoodle.createdAt, null, lastDoodle),
    ]..sort((a, b) => b.$1.compareTo(a.$1));

    final entries = <_TimelineEntry>[];
    for (var i = 0; i < rows.length; i++) {
      final (sortTime, send, doodle) = rows[i];
      final header = _dateHeaderFor(sortTime);
      final prevHeader = i == 0 ? null : _dateHeaderFor(rows[i - 1].$1);
      final nextHeader = i == rows.length - 1 ? null : _dateHeaderFor(rows[i + 1].$1);
      final isFirstInGroup = header != prevHeader;
      final isLastInGroup = header != nextHeader;
      if (isFirstInGroup) entries.add(_TimelineEntry.header(header));
      entries.add(
        send != null
            ? _TimelineEntry.send(send, isFirstInGroup: isFirstInGroup, isLastInGroup: isLastInGroup)
            : _TimelineEntry.doodleThread(doodle!, isFirstInGroup: isFirstInGroup, isLastInGroup: isLastInGroup),
      );
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final box = BoxScope.of(context).currentBox;
    final partner = box?.partnerOf(widget.user.id);

    return Scaffold(
      backgroundColor: theme.background,
      body: ThemedBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Voir demande utilisateur : même en-tête que l'onglet Duo,
              // avatars + solde de pièces compris (même wordmark, même
              // taille, même étendue/padding) plutôt qu'une AppBar avec le
              // titre "Carnet de bord" — voir DashboardTab pour la
              // structure copiée à l'identique.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Row(
                  children: [
                    BinomeWordmark(
                      fontSize: 26,
                      color: theme.textOnBackground,
                      heartColor: theme.primary,
                    ),
                    Expanded(
                      child: Center(
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => CoupleProfileScreen(user: widget.user)),
                          ),
                          child: CoupleAvatarsBadge(
                            user: widget.user,
                            partner: partner,
                            partnerPresent: _partnerPresent,
                          ),
                        ),
                      ),
                    ),
                    CoinBalanceBadge(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ShopScreen()),
                      ),
                    ),
                  ],
                ),
              ),
              // Écoute FeatureFlagsService pour masquer/réafficher "Cadeaux"
              // et "Battements" en direct si un admin coupe la fonctionnalité
              // pendant que l'écran est ouvert (voir _onFeatureFlagsChanged
              // pour le repli automatique si le filtre actif disparaît).
              AnimatedBuilder(
                animation: FeatureFlagsService.instance,
                builder: (context, _) {
                  final flags = FeatureFlagsService.instance;
                  final chips = <Widget>[
                    _FilterChip(
                      label: 'Tous',
                      selected: _filter == _GalleryFilter.all,
                      onTap: () => _setFilter(_GalleryFilter.all),
                      theme: theme,
                    ),
                    _FilterChip(
                      label: 'Favoris',
                      icon: Icons.favorite_rounded,
                      selected: _filter == _GalleryFilter.favorites,
                      onTap: () => _setFilter(_GalleryFilter.favorites),
                      theme: theme,
                    ),
                    // Pas de flag dédié aux poèmes côté backend — visible
                    // en permanence, contrairement à Cadeaux/Battements.
                    _FilterChip(
                      label: 'Poèmes',
                      icon: Icons.auto_stories_rounded,
                      selected: _filter == _GalleryFilter.poems,
                      onTap: () => _setFilter(_GalleryFilter.poems),
                      theme: theme,
                    ),
                    if (flags.isEnabled('heartbeat'))
                      _FilterChip(
                        label: 'Battements',
                        icon: Icons.favorite_rounded,
                        selected: _filter == _GalleryFilter.heartbeats,
                        onTap: () => _setFilter(_GalleryFilter.heartbeats),
                        theme: theme,
                      ),
                    if (flags.isEnabled('gifts'))
                      _FilterChip(
                        label: 'Cadeaux',
                        icon: Icons.card_giftcard_rounded,
                        selected: _filter == _GalleryFilter.gifts,
                        onTap: () => _setFilter(_GalleryFilter.gifts),
                        theme: theme,
                      ),
                  ];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    // Voir demande utilisateur (capture : le dernier filtre
                    // coupé net au bord de l'écran donnait l'impression d'un
                    // débordement) — un simple SingleChildScrollView reste
                    // scrollable, mais le bord franc masquait cette
                    // affordance ; ce fondu signale "il y a plus à faire
                    // défiler" au lieu de couper brutalement.
                    child: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
                        stops: [0, 0.04, 0.92, 1],
                      ).createShader(bounds),
                      blendMode: BlendMode.dstIn,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            for (var i = 0; i < chips.length; i++) ...[
                              if (i > 0) const SizedBox(width: 8),
                              chips[i],
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              Expanded(
                child: RefreshIndicator(
                  color: theme.primary,
                  backgroundColor: theme.surface,
                  onRefresh: _refresh,
                  child: Builder(
                    builder: (context) {
                      // Loader UNIQUEMENT au tout premier chargement sans
                      // rien à montrer (ni cache, ni fetch précédent) — dès
                      // qu'on a quelque chose, il ne réapparaît plus jamais,
                      // même pendant un rafraîchissement réseau derrière.
                      if (_initialLoading) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (_loadError) {
                        return ListView(
                          children: const [
                            EmptyState(
                              icon: Icons.wifi_off_rounded,
                              message: "Impossible de charger le carnet de bord.",
                            ),
                          ],
                        );
                      }
                      final sends = _sends ?? [];
                      if (sends.isEmpty) {
                        return ListView(
                          children: [
                            EmptyState(
                              icon: Icons.mail_outline_rounded,
                              message: _filter == _GalleryFilter.all
                                  ? 'Aucun échange pour le moment. Envoie ta première slide !'
                                  : 'Rien ici pour ce filtre.',
                            ),
                          ],
                        );
                      }
                      final entries = _groupByDate(sends, _filter == _GalleryFilter.all ? _lastDoodle : null);
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
                            return _DateHeaderLabel(
                              label: entry.header!,
                              theme: theme,
                            );
                          }
                          if (entry.isDoodleThread) {
                            final doodle = entry.doodleThread!;
                            final partner = BoxScope.of(context).currentBox?.partnerOf(widget.user.id);
                            final isMineLast = doodle.fromUserId == widget.user.id;
                            return _DoodleThreadRow(
                              isFirstInGroup: entry.isFirstInGroup,
                              isLastInGroup: entry.isLastInGroup,
                              theme: theme,
                              partnerName: partner?.prenom,
                              partnerAvatar: partner?.avatar,
                              preview: isMineLast ? 'Toi : un petit mot 💌' : 'Un petit mot pour toi 💌',
                              time: _relativeTime(doodle.createdAt),
                              unseen: !isMineLast && doodle.viewedAt == null,
                              onTap: _openDoodleThread,
                            );
                          }
                          final send = entry.send!;
                          // Le DERNIER message de la discussion (voir
                          // Send.lastMessage), pas l'envoi racine figé — le
                          // Carnet de bord doit ressembler à une vraie liste
                          // de conversations, dont l'aperçu reflète toujours
                          // le tout dernier échange.
                          final lastMessage = send.lastMessage;
                          final isMine = lastMessage.senderId == widget.user.id;
                          return _TimelineRow(
                            send: send,
                            isMine: isMine,
                            isFirstInGroup: entry.isFirstInGroup,
                            isLastInGroup: entry.isLastInGroup,
                            theme: theme,
                            title: _title(lastMessage, isMine),
                            message: _mainText(lastMessage),
                            time: _relativeTime(lastMessage.createdAt),
                            onTap: () => _openSend(send),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openComposeMenu,
        backgroundColor: theme.primary,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  final ThemePalette theme;

  const _FilterChip({
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? theme.primary : theme.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : (theme.isDark ? Colors.white : Colors.black).withValues(
                      alpha: 0.1,
                    ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: selected ? Colors.white : theme.textOnBackgroundMuted,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : theme.textOnBackgroundMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un élément de la liste aplatie : soit un en-tête de date, soit un envoi
/// avec sa position dans son groupe (première/dernière) pour savoir où le
/// fil vertical doit s'arrêter.
class _TimelineEntry {
  final String? header;
  final Send? send;
  final Doodle? doodleThread;
  final bool isFirstInGroup;
  final bool isLastInGroup;

  const _TimelineEntry.header(this.header)
    : send = null,
      doodleThread = null,
      isFirstInGroup = false,
      isLastInGroup = false;

  const _TimelineEntry.send(
    this.send, {
    required this.isFirstInGroup,
    required this.isLastInGroup,
  }) : header = null,
       doodleThread = null;

  const _TimelineEntry.doodleThread(
    this.doodleThread, {
    required this.isFirstInGroup,
    required this.isLastInGroup,
  }) : header = null,
       send = null;

  bool get isHeader => header != null;
  bool get isDoodleThread => doodleThread != null;
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
        style: GoogleFonts.nunito(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: theme.textOnBackgroundMuted,
        ),
      ),
    );
  }
}

/// Une ligne de la chronologie : l'avatar (avec son marqueur de type) est
/// relié au précédent/suivant par un fil vertical fin, façon fil d'Ariane —
/// [IntrinsicHeight] permet au fil de s'étirer exactement à la hauteur de
/// la carte, même si celle-ci a une hauteur variable selon le texte.
class _TimelineRow extends StatelessWidget {
  final Send send;
  final bool isMine;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final ThemePalette theme;
  final String title;
  final String message;
  final String time;
  final VoidCallback onTap;

  const _TimelineRow({
    required this.send,
    required this.isMine,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    required this.theme,
    required this.title,
    required this.message,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final lineColor = (theme.isDark ? Colors.white : Colors.black).withValues(
      alpha: 0.14,
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Expanded(
                  child: isFirstInGroup
                      ? const SizedBox()
                      : Container(width: 2, color: lineColor),
                ),
                _AvatarWithBadge(send: send, theme: theme),
                Expanded(
                  child: isLastInGroup
                      ? const SizedBox()
                      : Container(width: 2, color: lineColor),
                ),
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
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.nunito(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  height: 1.25,
                                  color: theme.textOnBackground,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (isMine) ...[
                                    SendTickIcon(tick: sendTickFor(send), color: theme.textOnBackgroundMuted),
                                    const SizedBox(width: 4),
                                  ],
                                  Expanded(
                                    child: Text(
                                      message,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.nunito(
                                        fontSize: 13,
                                        fontStyle: FontStyle.italic,
                                        letterSpacing: 0.2,
                                        color: theme.textOnBackgroundMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              time,
                              style: GoogleFonts.nunito(
                                fontSize: 11,
                                color: theme.textOnBackgroundMuted,
                              ),
                            ),
                            if (!isMine && !send.isSeen) ...[
                              const SizedBox(height: 6),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: theme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
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

/// Ligne "petits mots" (voir demande utilisateur) — une seule entrée pour
/// TOUTE la discussion de doodles, positionnée dans le fil comme un Send
/// normal (voir _groupByDate) mais dont l'aperçu/l'horodatage reflètent
/// toujours le DERNIER doodle envoyé, jamais une capsule par envoi. Même
/// structure visuelle que _TimelineRow (fil vertical + carte) pour rester
/// cohérent avec le reste du Carnet de bord.
class _DoodleThreadRow extends StatelessWidget {
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final ThemePalette theme;
  final String? partnerName;
  final String? partnerAvatar;
  final String preview;
  final String time;
  final bool unseen;
  final VoidCallback onTap;

  const _DoodleThreadRow({
    required this.isFirstInGroup,
    required this.isLastInGroup,
    required this.theme,
    this.partnerName,
    this.partnerAvatar,
    required this.preview,
    required this.time,
    required this.unseen,
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
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: theme.primary.withValues(alpha: 0.15),
                      backgroundImage: partnerAvatar != null ? NetworkImage(partnerAvatar!) : null,
                      child: partnerAvatar == null
                          ? Text(partnerName != null && partnerName!.isNotEmpty ? partnerName![0] : '?')
                          : null,
                    ),
                    Positioned(right: -3, bottom: -3, child: _BadgeIcon(icon: Icons.brush_rounded, color: theme.secondary)),
                  ],
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
                                'Mots & dessins avec ${partnerName ?? "ton binôme"}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.nunito(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: theme.textOnBackground,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                preview,
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
                            if (unseen) ...[
                              const SizedBox(height: 6),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(color: theme.primary, shape: BoxShape.circle),
                              ),
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

/// Avatar de l'expéditeur avec un petit marqueur d'émotion superposé —
/// permet de scanner le type d'envoi (cœur / slide / cadeau) sans lire le
/// texte.
class _AvatarWithBadge extends StatelessWidget {
  final Send send;
  final ThemePalette theme;

  const _AvatarWithBadge({required this.send, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: theme.primary.withValues(alpha: 0.15),
          backgroundImage: send.sender?.avatar != null
              ? NetworkImage(send.sender!.avatar!)
              : null,
          child: send.sender?.avatar == null
              ? Text(
                  send.sender != null && send.sender!.prenom.isNotEmpty
                      ? send.sender!.prenom[0]
                      : '?',
                )
              : null,
        ),
        Positioned(right: -3, bottom: -3, child: _typeBadge()),
      ],
    );
  }

  Widget _typeBadge() {
    if (send.isHeartbeat) return _PulsingHeartBadge(color: theme.primary);
    if (send.isGift) return _BadgeIcon(icon: Icons.card_giftcard_rounded, color: theme.accent);
    if (send.isEmojiReply) return _BadgeIcon(icon: Icons.emoji_emotions_rounded, color: theme.secondary);
    return _BadgeIcon(icon: Icons.auto_stories_rounded, color: theme.secondary);
  }
}

class _BadgeIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _BadgeIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Icon(icon, size: 10, color: Colors.white),
    );
  }
}

/// Cœur qui pulse doucement en continu — marqueur des envois "Faire battre
/// son cœur", pour qu'ils se repèrent d'un coup d'œil dans le fil.
class _PulsingHeartBadge extends StatefulWidget {
  final Color color;

  const _PulsingHeartBadge({required this.color});

  @override
  State<_PulsingHeartBadge> createState() => _PulsingHeartBadgeState();
}

class _PulsingHeartBadgeState extends State<_PulsingHeartBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  late final Animation<double> _scale = Tween<double>(
    begin: 0.88,
    end: 1.12,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: const Icon(
          Icons.favorite_rounded,
          size: 10,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Petit badge de prix affiché dans l'en-tête de la modale "Faire battre
/// son cœur" — copie conforme de DarkQuickActionsGrid._PriceBadge (privée
/// à son fichier, pas réutilisable telle quelle).
class _PriceBadge extends StatelessWidget {
  final int coinPrice;
  final double coinSize;
  final double fontSize;

  const _PriceBadge({required this.coinPrice, this.coinSize = 9, this.fontSize = 9});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: coinSize * 0.65, vertical: coinSize * 0.35),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CoinIcon(size: coinSize, fallbackColor: const Color(0xFFFFD37A)),
          SizedBox(width: coinSize * 0.22),
          Text(
            '$coinPrice',
            style: GoogleFonts.poppins(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Une des deux options de la modale "Faire battre son cœur" — copie
/// conforme de DarkQuickActionsGrid._HeartbeatOptionTile.
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

