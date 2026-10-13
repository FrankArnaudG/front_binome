import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screen_protector/screen_protector.dart';

import '../../core/api_client.dart';
import '../../core/token_storage.dart';
import '../../l10n/locale_scope.dart';
import '../../models/app_user.dart';
import '../../models/pack.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/coin_icon.dart';
import '../shop/subscription_status_notifier.dart';
import '../shop/wallet_balance_notifier.dart';
import 'content_service.dart';
import 'pack_favorite_storage.dart';
import 'slide_detail_screen.dart';
import 'widgets/slide_visual_card.dart';

/// Feed vertical façon TikTok : on parcourt les slides d'un poème, puis on
/// envoie le pack ENTIER d'un coup au/à la partenaire (pas carte par carte)
/// — un seul prix pour tout le poème (voir Pack.sendCoinPrice et son badge
/// fixe en haut).
class PackFeedScreen extends StatefulWidget {
  final String packId;

  /// Non nul lorsqu'on arrive ici depuis la capsule d'un envoi pour
  /// "répondre avec un poème" (voir [PacksScreen]) : le prochain envoi
  /// réussi sera taggé comme réponse, puis referme tout le parcours de
  /// sélection d'un coup pour revenir directement sur la capsule d'origine.
  final String? replyToSendId;

  const PackFeedScreen({super.key, required this.packId, this.replyToSendId});

  @override
  State<PackFeedScreen> createState() => _PackFeedScreenState();
}

class _PackFeedScreenState extends State<PackFeedScreen> {
  Pack? _pack;
  bool _loading = true;
  String? _error;
  bool _changed = false;
  bool _sendingPack = false;
  bool _packJustSent = false;
  final _pageController = PageController();
  int _currentSlideIndex = 0;
  // Favori (voir PackFavoriteStorage et demande utilisateur : "à la place
  // du bouton partager... un bouton pour mettre un poème slide en
  // favori") — purement local, pas de champ côté Pack/backend.
  String? _userId;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadFavorite();
    // Capture d'écran bloquée tant que cet écran est ouvert (voir demande
    // utilisateur : "impossible de faire capture d'écran des poème
    // slide") — même mécanisme que RomanPhotoReaderScreen : best-effort,
    // réellement empêché sur Android, seulement détecté sur iOS (voir doc
    // du plugin screen_protector).
    _enableScreenshotProtection();
  }

  Future<void> _enableScreenshotProtection() async {
    try {
      await ScreenProtector.preventScreenshotOn();
    } catch (_) {
      // Plateforme non supportée par le plugin (desktop/web) — la lecture
      // reste possible, juste sans cette protection.
    }
  }

  Future<void> _disableScreenshotProtection() async {
    try {
      await ScreenProtector.preventScreenshotOff();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disableScreenshotProtection();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadFavorite() async {
    final userJson = await TokenStorage.instance.readUserJson();
    if (!mounted || userJson == null) return;
    final user = AppUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
    final isFavorite = await PackFavoriteStorage.instance.isFavorite(
      user.id,
      widget.packId,
    );
    if (!mounted) return;
    setState(() {
      _userId = user.id;
      _isFavorite = isFavorite;
    });
  }

  Future<void> _toggleFavorite() async {
    final userId = _userId;
    if (userId == null) return;
    final nowFavorite = await PackFavoriteStorage.instance.toggleFavorite(
      userId,
      widget.packId,
    );
    if (!mounted) return;
    setState(() => _isFavorite = nowFavorite);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pack = await ContentService.instance.fetchPack(widget.packId);
      if (!mounted) return;
      setState(() {
        _pack = pack;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _sendPack() async {
    if (_sendingPack) return;
    setState(() => _sendingPack = true);
    try {
      final send = await ContentService.instance.sendPack(
        widget.packId,
        replyToSendId: widget.replyToSendId,
      );
      _changed = true;
      if (!mounted) return;
      // Envoyer un poème coûte des tokens (voir CoinPack.sendCoinPrice) —
      // sans ce rafraîchissement, le badge de solde affiché ailleurs
      // (Dashboard, discussion...) restait figé sur l'ancien montant tant
      // qu'on ne rouvrait pas manuellement l'écran (constaté en réel, voir
      // demande utilisateur — même correctif déjà en place pour l'envoi
      // d'une pensée, voir GameCardThreadScreen._sendHeartbeatReply).
      unawaited(WalletBalanceNotifier.instance.refresh());
      if (widget.replyToSendId != null) {
        // Mode réponse : un seul envoi suffit, on referme tout le parcours
        // de sélection (Packs → Catégorie → Feed) d'un coup pour revenir
        // directement sur la capsule d'origine.
        final navigator = Navigator.of(context);
        navigator.popUntil((route) => route.settings.name == 'reply-root');
        navigator.pop(true);
        return;
      }
      setState(() {
        _sendingPack = false;
        _packJustSent = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LocaleScope.of(context).t('pack_feed_sent_snackbar')),
        ),
      );
      // Redirige directement vers la discussion concernée par cet envoi
      // (même écran que le Carnet de bord, voir TimelineScreen._openSend)
      // plutôt que de laisser l'utilisateur sur le feed déjà envoyé.
      final userJson = await TokenStorage.instance.readUserJson();
      if (!mounted || userJson == null) return;
      final user = AppUser.fromJson(
        jsonDecode(userJson) as Map<String, dynamic>,
      );
      // pushReplacement (et non push + await + _pop()) : remplace CE feed
      // par la discussion dans le MÊME geste de navigation, sans fenêtre où
      // ce widget resterait monté avec une Navigator.pop() en attente. Avec
      // l'ancien push+await, un tap sur un onglet de la barre de nav pendant
      // que la discussion était affichée (AppShell.popUntil((r) =>
      // r.isFirst)) fermait la discussion ET ce feed d'un coup — le pop()
      // différé s'exécutait alors sur un Navigator déjà vidé, cassant la
      // navigation (écran blanc, app à redémarrer — constaté en réel, voir
      // demande utilisateur).
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              SlideDetailScreen(send: send, isMine: true, user: user),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sendingPack = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _pop() => Navigator.of(context).pop(_changed);

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _pop();
      },
      child: Scaffold(
        backgroundColor: theme.background,
        body: ThemedBackground(child: SafeArea(child: _buildBody(theme))),
      ),
    );
  }

  Widget _buildBody(ThemePalette theme) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: theme.primary));
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: GoogleFonts.nunito(color: theme.textOnBackground),
        ),
      );
    }

    final pack = _pack!;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              IconButton(
                onPressed: _pop,
                icon: Icon(
                  Icons.chevron_left_rounded,
                  color: theme.textOnBackground,
                ),
              ),
              Expanded(
                child: Text(
                  pack.titleFor(LocaleScope.of(context).current.code),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: theme.textOnBackground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
        Expanded(child: _buildFeed(pack, theme)),
      ],
    );
  }

  Widget _buildFeed(Pack pack, ThemePalette theme) {
    if (pack.slides.isEmpty) {
      return Center(
        child: Text(
          LocaleScope.of(context).t('pack_feed_no_slides'),
          style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
        ),
      );
    }

    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.horizontal,
          itemCount: pack.slides.length,
          onPageChanged: (index) => setState(() => _currentSlideIndex = index),
          itemBuilder: (context, index) {
            final slide = pack.slides[index];

            return Container(
              margin: const EdgeInsets.all(16),
              child: SlideVisualCard(
                slide: slide,
                theme: theme,
                category: pack.category,
                // La personne qui parcourt le pack est celle qui l'enverra.
                senderGender: TokenStorage.currentGender,
                // Laisse de la place à droite pour la barre d'actions
                // verticale empilée par-dessus.
                captionRightPadding: 96,
                overlay: Positioned(
                  right: 16,
                  bottom: 28,
                  child: _ActionRail(
                    sent: _packJustSent,
                    loading: _sendingPack,
                    onSend: _packJustSent ? null : _sendPack,
                    favorite: _isFavorite,
                    onFavorite: _toggleFavorite,
                  ),
                ),
              ),
            );
          },
        ),
        // Prix fixe en haut, en dehors du PageView : ne bouge pas pendant le
        // swipe (contrairement à un badge posé sur chaque page). Un seul
        // prix pour le pack entier (Pack.sendCoinPrice), envoyé d'un coup.
        Positioned(
          top: 24,
          right: 24,
          child: IgnorePointer(
            child: _FixedPriceBadge(coinPrice: pack.sendCoinPrice),
          ),
        ),
        // Cœurs de progression, fixes en bas — en dehors du PageView, ils
        // ne se déplacent pas quand on swipe horizontalement.
        Positioned(
          left: 0,
          right: 0,
          bottom: 10,
          child: IgnorePointer(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(pack.slides.length, (i) {
                final reached = i <= _currentSlideIndex;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Icon(
                    reached
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 13,
                    color: Colors.white.withValues(
                      alpha: reached ? 0.95 : 0.45,
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    );
  }
}

class _FixedPriceBadge extends StatelessWidget {
  final int coinPrice;

  const _FixedPriceBadge({required this.coinPrice});

  @override
  Widget build(BuildContext context) {
    // Abonnement actif : l'envoi d'un poème-slide est gratuit et illimité
    // (voir SendController côté backend, aucun débit pour un abonné) —
    // plus aucune raison d'afficher son prix (voir demande utilisateur :
    // "rien ne doit apparaître").
    if (SubscriptionStatusNotifier.instance.isActive)
      return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Barre d'actions verticale façon TikTok, empilée à droite du feed. Le
/// cœur envoie le pack ENTIER (toutes ses cartes, pas juste celle
/// affichée) au/à la partenaire ; l'étoile marque/démarque ce poème
/// comme favori (voir PackFavoriteStorage, purement local) — remplace
/// l'ancien bouton "Partager" (voir demande utilisateur).
class _ActionRail extends StatelessWidget {
  final bool sent;
  final bool loading;
  final VoidCallback? onSend;
  final bool favorite;
  final VoidCallback onFavorite;

  const _ActionRail({
    required this.sent,
    required this.loading,
    required this.onSend,
    required this.favorite,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final t = LocaleScope.of(context).t;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RailButton(
          onTap: onSend,
          loading: loading,
          background: sent
              ? Colors.white.withValues(alpha: 0.25)
              : const Color(0xFFFF3B5C),
          icon: Icons.favorite_rounded,
          label: sent ? t('pack_feed_sent') : t('pack_feed_send'),
        ),
        const SizedBox(height: 18),
        _RailButton(
          onTap: onFavorite,
          background: favorite
              ? const Color(0xFFFFB020)
              : Colors.white.withValues(alpha: 0.18),
          icon: favorite ? Icons.star_rounded : Icons.star_border_rounded,
          label: t('pack_feed_favorite'),
        ),
      ],
    );
  }
}

class _RailButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool loading;
  final Color background;
  final IconData icon;
  final String label;

  const _RailButton({
    required this.onTap,
    this.loading = false,
    required this.background,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: loading ? null : onTap,
            child: Container(
              width: 50,
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(icon, color: Colors.white, size: 23),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.nunito(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            shadows: const [
              Shadow(
                color: Colors.black45,
                blurRadius: 6,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
