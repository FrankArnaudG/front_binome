import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api_client.dart';
import '../../../core/feature_flags_service.dart';
import '../../../core/timeline_refresh_signal.dart';
import '../../../l10n/locale_scope.dart';
import '../../../models/app_user.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../../../widgets/coin_icon.dart';
import '../../box/box_scope.dart';
import '../../box/distance_screen.dart';
import '../../content/content_service.dart';
import '../../doodle/doodle_history_screen.dart';
import '../../content/gifts_screen.dart';
import '../../mood/mood_screen.dart';
import '../../shop/shop_screen.dart';
import '../../shop/wallet_balance_notifier.dart';
import '../../roman_photo/roman_photo_library_screen.dart';
import '../../sounds/shared_sounds_screen.dart';
import '../../vault/photo_vault_screen.dart';
import 'heart_burst.dart';

/// Grille d'actions rapides du Dashboard — suit le thème personnel choisi
/// (voir [ThemeScope]), utilisée uniquement par [DashboardTab].
class DarkActionItem {
  final String label;
  final IconData icon;
  final Color Function(ThemePalette) color;
  final void Function(BuildContext) onTap;

  /// Remplace l'icône Material par un widget sur mesure (ex. [CoinIcon]
  /// pour la Boutique) — si absent, [icon] est utilisé tel quel.
  final Widget Function(Color)? iconBuilder;

  /// Clé du feature flag associé (voir FeatureFlagsService) — tuile grisée
  /// et action bloquée tant qu'il est désactivé depuis le panel admin.
  final String featureKey;

  DarkActionItem(this.label, this.icon, this.color, this.onTap, this.featureKey, {this.iconBuilder});
}

class DarkQuickActionsGrid extends StatefulWidget {
  final AppUser user;
  final void Function(int tabIndex)? onNavigateToTab;

  const DarkQuickActionsGrid({super.key, required this.user, this.onNavigateToTab});

  @override
  State<DarkQuickActionsGrid> createState() => _DarkQuickActionsGridState();
}

class _DarkQuickActionsGridState extends State<DarkQuickActionsGrid> {
  bool _sendingHeartbeat = false;
  final _burstKey = GlobalKey<HeartBurstState>();
  Timer? _emojiRefreshTimer;
  int? _heartbeatPrice;

  /// Un émoji par heure (0h à 23h) — pas que des cœurs : ciel nocturne,
  /// fleurs (dont la rose), lever/coucher du soleil, petits gestes
  /// romantiques (bisou, coupe de champagne...), suivant l'ambiance de
  /// chaque moment de la journée plutôt qu'une icône figée à l'année.
  static const List<String> _heartbeatHourlyEmojis = [
    '🌙', '⭐', '🌌', '💫', '🌠', '🌃', // 0h–5h : nuit
    '🌅', '🩷', '🌸', '🌹', '💐', '☀️', // 6h–11h : aube → matinée
    '❤️', '😍', '🧡', '🌻', '🌼', '💛', // 12h–17h : midi → fin d'après-midi
    '🌇', '🌆', '💋', '😘', '🥂', '🌙', // 18h–23h : coucher de soleil → nuit
  ];

  String get _heartbeatEmoji => _heartbeatHourlyEmojis[DateTime.now().hour];

  @override
  void initState() {
    super.initState();
    _scheduleEmojiRefresh();
    _loadHeartbeatPrice();
  }

  // Réglable depuis l'espace admin (voir HeartbeatSetting) — affiché sur la
  // tuile pour que le coût soit visible avant l'envoi. Échec silencieux : la
  // tuile reste utilisable sans badge plutôt que de bloquer le Dashboard.
  Future<void> _loadHeartbeatPrice() async {
    try {
      final price = await ContentService.instance.fetchHeartbeatPrice();
      if (mounted) setState(() => _heartbeatPrice = price);
    } catch (_) {}
  }

  @override
  void dispose() {
    _emojiRefreshTimer?.cancel();
    super.dispose();
  }

  /// Reprogrammé à chaque heure pile, plutôt qu'un Timer.periodic à
  /// intervalle fixe (qui dériverait au fil du temps) — l'émoji change
  /// tout seul pendant que l'écran reste ouvert, sans attendre qu'un autre
  /// événement (envoi, retour sur l'écran...) déclenche un rebuild.
  void _scheduleEmojiRefresh() {
    final now = DateTime.now();
    final nextHour = DateTime(now.year, now.month, now.day, now.hour).add(const Duration(hours: 1));
    _emojiRefreshTimer = Timer(nextHour.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _scheduleEmojiRefresh();
    });
  }

  Future<void> _sendHeartbeat({String? message}) async {
    if (_sendingHeartbeat) return;
    // Joue instantanément, indépendamment du temps que prendra l'appel
    // réseau ci-dessous — le retour tactile ne doit jamais attendre le serveur.
    _burstKey.currentState?.trigger();
    setState(() => _sendingHeartbeat = true);

    try {
      final send = await ContentService.instance.sendHeartbeat(message: message);
      // Coûte des pièces désormais (voir HeartbeatController::COIN_COST) —
      // même geste de rafraîchissement que pour un envoi de poème/cadeau,
      // pour que le badge de solde du Dashboard reste à jour.
      await WalletBalanceNotifier.instance.refresh();
      // Sinon le Carnet de bord (gardé en mémoire dans l'IndexedStack, voir
      // MainTabScreen) affiche encore l'ancienne liste tant qu'on ne
      // l'actualise pas manuellement — un envoi depuis Duo doit s'y
      // refléter immédiatement, comme au tap sur une notification push
      // (voir TimelineRefreshSignal).
      TimelineRefreshSignal.instance.requestRefresh();
      if (!mounted) return;
      final localeCode = LocaleScope.of(context).current.code;
      final t = LocaleScope.of(context).t;
      final partnerName = BoxScope.of(context).currentBox?.partnerOf(widget.user.id)?.prenom ?? t('common_partner_fallback');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('heartbeat_sent_snackbar', {'message': send.heartbeatMessageFor(localeCode) ?? '', 'name': partnerName}))),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sendingHeartbeat = false);
    }
  }

  /// Appui long sur la tuile : plutôt que d'envoyer directement un mot
  /// aléatoire (le geste du double-tap), on laisse le choix entre la
  /// surprise habituelle et une déclaration composée à la main.
  Future<void> _openHeartbeatOptions() async {
    if (_sendingHeartbeat) return;
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;
    HapticFeedback.selectionClick();
    // Un sous-titre différent tiré au hasard parmi 4 à chaque ouverture de
    // la feuille (voir demande utilisateur).
    final randomSubtitleKey = 'heartbeat_option_random_subtitle_${math.Random().nextInt(4) + 1}';
    final customSubtitleKey = 'heartbeat_option_custom_subtitle_${math.Random().nextInt(4) + 1}';

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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t('heartbeat_label'),
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: theme.textOnBackground),
                    ),
                  ),
                  // Les deux options coûtent le même prix (voir
                  // HeartbeatController::send, même coin_cost quel que soit
                  // le choix) — un seul badge ici plutôt que répété sur
                  // chaque tuile en dessous.
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

  void _showLocked(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(LocaleScope.of(context).t('common_coming_soon'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Réagit en direct si les flags changent pendant que le Dashboard est
    // déjà affiché (ex. pull-to-refresh) sans devoir tout reconstruire.
    return AnimatedBuilder(
      animation: FeatureFlagsService.instance,
      builder: (context, _) => _buildGrid(context),
    );
  }

  Widget _buildGrid(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final tr = LocaleScope.of(context).t;
    final flags = FeatureFlagsService.instance;

    // Galerie et Jeux sont des onglets du même shell (voir MainTabScreen) :
    // on bascule dessus via [onNavigateToTab] plutôt que de les pousser en
    // second exemplaire — sinon ce doublon sort de la portée de ThemeScope
    // et plante (ces deux écrans en dépendent).
    final items = [
      // "Notre Humeur du Jour" (voir demande utilisateur) — remplace ici la
      // tuile "Carnet de bord", redondante avec le premier onglet du bas
      // (toujours accessible), au profit d'un écran dédié (voir MoodScreen).
      DarkActionItem(
        tr('action_mood'),
        Icons.emoji_emotions_rounded,
        (t) => t.secondary,
        (ctx) => Navigator.of(ctx).push(
          MaterialPageRoute(
            builder: (_) {
              final partner = BoxScope.of(ctx).currentBox?.partnerOf(widget.user.id);
              return MoodScreen(user: widget.user, partnerName: partner?.prenom, partnerGender: partner?.gender);
            },
          ),
        ),
        'mood',
      ),
      DarkActionItem(
        tr('action_gifts'),
        Icons.card_giftcard_rounded,
        (t) => t.accent,
        (ctx) => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => GiftsScreen(user: widget.user))),
        'gifts',
      ),
      DarkActionItem(
        tr('action_shop'),
        Icons.monetization_on_rounded,
        (t) => t.primaryDeep,
        (ctx) => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const ShopScreen())),
        'shop',
        iconBuilder: (color) => CoinIcon(size: 26, fallbackColor: color),
      ),
      DarkActionItem(
        tr('action_games'),
        Icons.sports_esports_rounded,
        (t) => t.secondary,
        (ctx) => widget.onNavigateToTab?.call(2),
        'games',
      ),
      DarkActionItem(
        tr('action_vault'),
        Icons.lock_rounded,
        (t) => t.textOnBackgroundMuted,
        (ctx) => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const PhotoVaultScreen())),
        'vault',
      ),
      DarkActionItem(
        tr('action_sounds'),
        Icons.music_note_rounded,
        (t) => t.accent,
        (ctx) => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => SharedSoundsScreen(user: widget.user))),
        'sounds',
      ),
      // Prototype front-end pur (voir demande utilisateur) : pas de
      // FeatureFlagsService.isEnabled('roman_photo') défini côté admin —
      // isEnabled() retombe alors sur `true` par défaut (voir
      // FeatureFlagsService), donc la tuile n'est jamais verrouillée sans
      // qu'il faille toucher au backend pour ce test.
      DarkActionItem(
        'Roman-photo',
        Icons.auto_stories_rounded,
        (t) => t.primary,
        (ctx) => Navigator.of(ctx).push(
          MaterialPageRoute(builder: (_) => const RomanPhotoLibraryScreen()),
        ),
        'roman_photo',
      ),
      // Doodle envoyé au binôme (voir demande utilisateur) — s'affiche en
      // plein écran chez l'autre (voir DoodleViewScreen/DoodleOverlay).
      DarkActionItem(
        tr('action_doodle'),
        Icons.brush_rounded,
        (t) => t.secondary,
        (ctx) => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => DoodleHistoryScreen(user: widget.user))),
        'doodle',
      ),
      // "Notre distance" (voir demande utilisateur) — partage PONCTUEL de
      // position, jamais un suivi continu (voir DistanceScreen).
      DarkActionItem(
        tr('action_distance'),
        Icons.flight_rounded,
        (t) => t.primary,
        (ctx) => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => DistanceScreen(user: widget.user))),
        'distance',
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: items.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          final heartbeatLocked = !flags.isEnabled('heartbeat');
          return HeartBurst(
            key: _burstKey,
            child: _DarkTile(
              theme: theme,
              // Boîte de taille fixe, identique à celle d'un Icon(size: 26) :
              // un émoji a une hauteur de ligne naturelle plus grande qu'une
              // icône Material de même taille nominale, d'où le débordement
              // d'une fraction de pixel sans ce cadrage.
              iconBuilder: (color) => SizedBox(
                height: 26,
                width: 26,
                child: Center(
                  child: Text(
                    _heartbeatEmoji,
                    style: const TextStyle(fontSize: 22, height: 1),
                  ),
                ),
              ),
              iconColor: theme.primary,
              label: tr('heartbeat_label'),
              hint: tr('heartbeat_hint'),
              loading: _sendingHeartbeat,
              locked: heartbeatLocked,
              priceBadge: _heartbeatPrice != null ? _PriceBadge(coinPrice: _heartbeatPrice!) : null,
              onTap: heartbeatLocked ? () => _showLocked(context) : null,
              onDoubleTap: (_sendingHeartbeat || heartbeatLocked) ? null : () => _sendHeartbeat(),
              onLongPress: (_sendingHeartbeat || heartbeatLocked) ? null : _openHeartbeatOptions,
            ),
          );
        }
        final item = items[index - 1];
        final locked = !flags.isEnabled(item.featureKey);
        return _DarkTile(
          theme: theme,
          icon: item.icon,
          iconColor: item.color(theme),
          iconBuilder: item.iconBuilder,
          label: item.label,
          locked: locked,
          onTap: locked ? () => _showLocked(context) : () => item.onTap(context),
        );
      },
    );
  }
}

class _DarkTile extends StatelessWidget {
  final ThemePalette theme;
  final IconData? icon;
  final Color iconColor;
  final Widget Function(Color)? iconBuilder;
  final String label;
  final String? hint;
  final bool loading;
  final bool locked;
  final Widget? priceBadge;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;

  const _DarkTile({
    required this.theme,
    this.icon,
    required this.iconColor,
    this.iconBuilder,
    required this.label,
    this.hint,
    this.loading = false,
    this.locked = false,
    this.priceBadge,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    // Grisée plutôt que retirée : montre que la fonctionnalité existe mais
    // n'est pas encore ouverte, sans faire sauter toute la grille de mise
    // en page pendant qu'une fonctionnalité est en préparation.
    return Opacity(
      opacity: locked ? 0.45 : 1,
      child: Material(
        color: theme.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: (theme.isDark ? Colors.white : Colors.black).withValues(alpha: 0.06)),
            ),
            child: Stack(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (loading)
                      SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: theme.primary),
                      )
                    else if (iconBuilder != null)
                      iconBuilder!(iconColor)
                    else
                      Icon(icon, color: iconColor, size: 26),
                    const SizedBox(height: 8),
                    // Hauteur fixe (2 lignes) : sans ça, une tuile au libellé
                    // plus court (ex. "Cadeaux") centre son icône plus bas
                    // qu'une tuile à libellé sur 2 lignes (ex. "Carnet de
                    // bord") — les icônes de la grille ne s'alignaient pas
                    // entre elles d'une tuile à l'autre.
                    SizedBox(
                      height: 32,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w600, color: theme.textOnBackground),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Réservée même sans indice, pour la même raison.
                    SizedBox(
                      height: 12,
                      child: (hint != null && !locked)
                          ? Text(
                              hint!,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.nunito(fontSize: 10, color: theme.textOnBackgroundMuted),
                            )
                          : null,
                    ),
                  ],
                ),
                if (locked)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Icon(Icons.lock_rounded, size: 14, color: theme.textOnBackgroundMuted),
                  ),
                if (priceBadge != null && !locked)
                  Positioned(top: 0, left: 0, child: priceBadge!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Petit badge de prix affiché en haut à gauche d'une tuile (ex. "Faire
/// battre son cœur") — même esprit que _FixedPriceBadge de pack_feed_screen,
/// en plus compact pour tenir sur une tuile de grille 3 colonnes.
class _PriceBadge extends StatelessWidget {
  final int coinPrice;

  /// Plus grand dans l'en-tête de la modale (plus d'espace, doit se lire
  /// au premier coup d'œil) que sur la tuile compacte de la grille 3
  /// colonnes, où la place est comptée.
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

/// Une des deux options du bottom sheet ouvert par l'appui long sur la
/// tuile "Faire battre son cœur" (voir [_DarkQuickActionsGridState._openHeartbeatOptions]).
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
