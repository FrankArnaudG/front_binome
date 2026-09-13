import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/feature_flags_service.dart';
import '../../core/realtime_client.dart';
import '../../l10n/locale_scope.dart';
import '../../models/app_user.dart';
import '../../models/mood.dart';
import '../../models/send.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/binome_wordmark.dart';
import '../../widgets/coin_balance_badge.dart';
import '../box/box_scope.dart';
import '../box/box_service.dart';
import '../box/couple_profile_screen.dart';
import '../content/content_service.dart';
import '../content/packs_screen.dart';
import '../content/unread_timeline_service.dart';
import '../games/game_card_inbox_service.dart';
import '../mood/mood_screen.dart';
import '../mood/mood_service.dart';
import '../mood/mood_suggestion_modal.dart';
import '../shop/shop_screen.dart';
import '../shop/wallet_balance_notifier.dart';
import 'widgets/couple_avatars_badge.dart';
import 'widgets/dark_day_counter_card.dart';
import 'widgets/dark_nightly_poem_banner.dart';
import 'widgets/dark_quick_actions_grid.dart';
import 'widgets/inbox_toast.dart';
import 'widgets/mood_of_day_card.dart';
import 'widgets/received_poem_card.dart';
import 'widgets/send_thought_cta.dart';

/// Dashboard (onglet Cœur) — suit le thème personnel choisi dans les
/// Paramètres (voir [ThemeScope]), par défaut "Douceur Poudrée" (thème
/// clair). Chaque personne du couple choisit le sien indépendamment.
class DashboardTab extends StatefulWidget {
  final AppUser user;
  final void Function(int tabIndex)? onNavigateToTab;

  const DashboardTab({super.key, required this.user, this.onNavigateToTab});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  bool _hasSentToday = false;
  String? _subscribedBoxId;
  String? _partnerId;
  bool _partnerPresent = false;
  Send? _receivedPoemToday;
  Mood? _myMood;
  Mood? _partnerMood;
  MoodSuggestion? _partnerSuggestion;

  @override
  void initState() {
    super.initState();
    _initRealtime();
    WalletBalanceNotifier.instance.refresh();
    FeatureFlagsService.instance.refresh();
    GameCardInboxService.instance.refresh();
    UnreadTimelineService.instance.refresh(widget.user.id);
    _checkTodayActivity();
    _fetchTodayMood();
  }

  @override
  void dispose() {
    if (_subscribedBoxId != null) {
      RealtimeClient.instance.unsubscribeFromBox(
        _subscribedBoxId!,
        onEvent: _onRealtimeEvent,
        onPresenceChange: _onPresenceChange,
      );
    }
    super.dispose();
  }

  Future<void> _initRealtime() async {
    final box = await BoxService.instance.fetchCurrent();
    if (box == null || !mounted) return;
    _subscribedBoxId = box.id;
    _partnerId = box.partnerOf(widget.user.id)?.id;
    try {
      await RealtimeClient.instance.subscribeToBox(
        box.id,
        onEvent: _onRealtimeEvent,
        onPresenceChange: _onPresenceChange,
      );
    } catch (_) {
      // Best effort : sans temps réel, le Dashboard reste utilisable.
    }
  }

  void _onPresenceChange(Set<String> memberIds) {
    if (!mounted) return;
    final present = _partnerId != null && memberIds.contains(_partnerId);
    if (present != _partnerPresent) setState(() => _partnerPresent = present);
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.event == 'SendSeen') {
      // Marqué lu ailleurs (typiquement : on est déjà dans la discussion
      // concernée quand l'envoi arrive — voir GameCardThreadScreen/
      // SlideDetailScreen, qui marquent lu tout de suite dans ce cas) —
      // retire de la bulle de notification, qui ne doit représenter que ce
      // qui attend VRAIMENT une action pas encore vue.
      final sendId = event.data?['send_id'] as String?;
      if (sendId != null) GameCardInboxService.instance.removePending(sendId);
      return;
    }
    if (event.event == 'MoodShared') {
      final moodJson = event.data?['mood'] as Map<String, dynamic>?;
      if (moodJson == null) return;
      final mood = Mood.fromJson(moodJson);
      if (mood.userId == widget.user.id) return;
      if (mounted) setState(() => _partnerMood = mood);
      return;
    }
    if (event.event != 'SendCreated') return;
    final sendJson = event.data?['send'] as Map<String, dynamic>?;
    if (sendJson == null) return;

    final send = Send.fromJson(sendJson);
    _checkTodayActivity();

    if (send.recipientId == widget.user.id) {
      UnreadTimelineService.instance.increment();
    }

    // La bulle de notification (voir GameCardBubble) et la bannière
    // temporaire (voir InboxToast) couvrent les jeux, les poèmes-slides et
    // les battements de cœur — tout ce qui a une "vraie discussion" à
    // ouvrir en retour. Un envoi reçu pendant qu'on est déjà dans la
    // discussion concernée est retiré de la bulle presque aussitôt via
    // l'event SendSeen ci-dessus (marqué lu en direct par cet écran) — la
    // bannière, elle, reste affichée quelques secondes quoi qu'il arrive,
    // c'est une simple confirmation visuelle de réception.
    if ((send.isGameCard || send.isEmojiStory || send.isPack || send.isHeartbeat) &&
        send.recipientId == widget.user.id) {
      GameCardInboxService.instance.addPending(send);
      if (mounted) InboxToast.show(context, send);
    }
  }

  Future<void> _fetchTodayMood() async {
    try {
      final (mine, partner, _, partnerSuggestion) = await MoodService.instance.fetchToday();
      if (mounted) {
        setState(() {
          _myMood = mine;
          _partnerMood = partner;
          _partnerSuggestion = partnerSuggestion;
        });
      }
    } catch (_) {
      // best effort — la carte reste simplement en état "à remplir"
    }
  }

  Future<void> _openMoodScreen() async {
    final partner = BoxScope.of(context).currentBox?.partnerOf(widget.user.id);
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MoodScreen(user: widget.user, partnerName: partner?.prenom, partnerGender: partner?.gender),
      ),
    );
    if (changed == true) _fetchTodayMood();
  }

  /// Ouvre la modale de conseil/défi pour l'humeur du binôme (voir demande
  /// utilisateur) — rien à faire tant qu'aucune suggestion n'est disponible
  /// pour sa combinaison (ex. avant qu'elle ait rempli besoin+envie).
  void _openPartnerMoodSuggestion() {
    if (_partnerMood == null || _partnerSuggestion == null) return;
    final partner = BoxScope.of(context).currentBox?.partnerOf(widget.user.id);
    showMoodSuggestionModal(
      context,
      moodKey: _partnerMood!.moodKey,
      gender: partner?.gender,
      name: partner?.prenom,
      suggestion: _partnerSuggestion!,
    );
  }

  Future<void> _checkTodayActivity() async {
    try {
      final sends = await ContentService.instance.fetchSends(limit: 5);
      final today = DateTime.now();
      bool isToday(DateTime dt) =>
          dt.year == today.year &&
          dt.month == today.month &&
          dt.day == today.day;

      final sentToday = sends.any(
        (s) => s.senderId == widget.user.id && isToday(s.createdAt),
      );
      final receivedPoem = sends.where(
        (s) =>
            s.sendableType == 'slide' &&
            s.recipientId == widget.user.id &&
            isToday(s.createdAt),
      );

      if (mounted) {
        setState(() {
          _hasSentToday = sentToday;
          _receivedPoemToday = receivedPoem.isNotEmpty
              ? receivedPoem.first
              : null;
        });
      }
    } catch (_) {
      // best effort — la bannière reste simplement masquée si l'appel échoue
    }
  }

  void _openPacks() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PacksScreen()));
  }

  void _openTimeline() {
    // La Galerie est un onglet du même shell (voir MainTabScreen) : on
    // bascule dessus plutôt que de la pousser en second exemplaire — sinon
    // ce doublon sort de la portée de ThemeScope et plante. Index 1 depuis
    // que Duo est devenu le premier onglet (page d'accueil).
    widget.onNavigateToTab?.call(1);
  }

  @override
  Widget build(BuildContext context) {
    final box = BoxScope.of(context).currentBox;
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;
    final partner = box?.partnerOf(widget.user.id);

    return Scaffold(
      backgroundColor: theme.background,
      body: ThemedBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Fixe (hors de la liste défilable ci-dessous) — comme
              // WhatsApp/Facebook, l'en-tête reste toujours visible plutôt
              // que de défiler avec le contenu.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Row(
                  children: [
                    // Remplace l'ancien bouton menu/tiroir (retiré — voir
                    // SettingsScreen, qui reprend désormais "À propos" et
                    // "Se déconnecter") : la signature de l'app plutôt
                    // qu'une action, en plus imposant (comme le wordmark
                    // WhatsApp/Facebook) qu'un simple élément de navigation
                    // — theme.primary pour rester cohérent avec le thème
                    // personnel choisi (voir BinomeWordmark).
                    BinomeWordmark(
                      fontSize: 26,
                      color: theme.textOnBackground,
                      heartColor: theme.primary,
                    ),
                    // Centrés dans l'espace disponible, sans nom à côté —
                    // même traitement que l'en-tête de conversation (voir
                    // SlideDetailScreen), les avatars (+ le cœur qui passe
                    // au vert si présent·e, voir CoupleAvatarsBadge)
                    // suffisent à dire "à deux".
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
              Expanded(
                child: RefreshIndicator(
                  color: theme.primary,
                  backgroundColor: theme.surface,
                  onRefresh: () async {
                    await BoxService.instance.fetchCurrent();
                    await WalletBalanceNotifier.instance.refresh();
                    await FeatureFlagsService.instance.refresh();
                    await UnreadTimelineService.instance.refresh(widget.user.id);
                    await _checkTodayActivity();
                    await _fetchTodayMood();
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
                    children: [
                      DarkDayCounterCard(
                        box: box,
                        // Ouvre "Notre Bulle à nous" — même geste que les
                        // avatars du haut. Géré à l'intérieur de la carte
                        // (sur la zone texte uniquement, pas l'avatar/le
                        // crayon qui ont leurs propres actions) plutôt
                        // qu'en enveloppant toute la carte depuis ici :
                        // deux GestureDetector superposés se déclenchent
                        // TOUS LES DEUX sur un même tap en Flutter (pas de
                        // "stopPropagation" par défaut), ce qui aurait
                        // ouvert le sélecteur de photo ET la navigation
                        // d'un seul tap sur l'avatar.
                        onOpenProfile: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => CoupleProfileScreen(user: widget.user)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      MoodOfDayCard(
                        mine: _myMood,
                        partner: _partnerMood,
                        myName: widget.user.prenom,
                        myGender: widget.user.gender,
                        partnerGender: partner?.gender,
                        partnerName: partner?.prenom,
                        onTap: _openMoodScreen,
                        onTapPartner: _openPartnerMoodSuggestion,
                      ),
                      const SizedBox(height: 16),
                      SendThoughtCta(onTap: _openPacks),
                      if (_receivedPoemToday != null) ...[
                        const SizedBox(height: 16),
                        ReceivedPoemCard(
                          poem: _receivedPoemToday!,
                          onTap: _openTimeline,
                        ),
                      ],
                      const SizedBox(height: 16),
                      DarkNightlyPoemBanner(
                        box: box,
                        hasSentToday: _hasSentToday,
                        onTap: _openPacks,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        t('dashboard_quick_actions'),
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: theme.textOnBackground,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DarkQuickActionsGrid(
                        user: widget.user,
                        onNavigateToTab: widget.onNavigateToTab,
                      ),
                    ],
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
