import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:google_fonts/google_fonts.dart';

import '../../core/timeline_refresh_signal.dart';
import '../../l10n/locale_scope.dart';
import '../../models/app_user.dart';
import '../../models/gift.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/coin_balance_badge.dart';
import '../../widgets/coin_icon.dart';
import '../../widgets/empty_state.dart';
import '../box/box_scope.dart';
import '../shop/shop_service.dart';
import '../shop/subscription_status_notifier.dart';
import '../shop/wallet_balance_notifier.dart';
import 'widgets/eternal_rose.dart';
import 'widgets/quantum_love_heart.dart';
import 'widgets/realistic_black_rose.dart';
import 'widgets/sketched_love_heart.dart';
import 'widgets/word_heart.dart';

class _CategoryMeta {
  final String label;
  final IconData icon;
  final Color Function(ThemePalette) color;

  const _CategoryMeta(this.label, this.icon, this.color);
}

const Map<String, _CategoryMeta> _categories = {
  'romantic': _CategoryMeta('Romantique', Icons.favorite_rounded, _primary),
  'sweet': _CategoryMeta('Sucré', Icons.cake_rounded, _accent),
  'jewelry': _CategoryMeta('Bijoux', Icons.diamond_rounded, _secondary),
  'luxury': _CategoryMeta(
    'Luxe',
    Icons.workspace_premium_rounded,
    _primaryDeep,
  ),
  'cute': _CategoryMeta('Mignon', Icons.pets_rounded, _secondary),
  'special': _CategoryMeta('Spécial', Icons.celebration_rounded, _accent),
};

_CategoryMeta _metaFor(String category) =>
    _categories[category] ??
    const _CategoryMeta('Cadeaux', Icons.card_giftcard_rounded, _accent);

/// Or fixe, indépendant du thème — la monnaie garde toujours son identité
/// dorée reconnaissable, même sur la pastille sombre neutre du prix.
const _gold = Color(0xFFFFD37A);

Color _primary(ThemePalette t) => t.primary;
Color _accent(ThemePalette t) => t.accent;
Color _secondary(ThemePalette t) => t.secondary;
Color _primaryDeep(ThemePalette t) => t.primaryDeep;

bool _isNetworkPath(String? path) =>
    path != null && (path.startsWith('http://') || path.startsWith('https://'));

/// Illustration choisie dans l'admin (hébergée sur le serveur) si elle
/// existe, sinon repli sur l'icône affinée par mot-clé du nom du cadeau.
Widget _giftIcon(Gift gift, Color color, double size, {String? recipientName, bool isDark = true}) {
  if (gift.isQuantumLoveHeart) {
    // Animation générative en direct plutôt qu'une icône figée — même dans
    // la vignette, pour donner un aperçu vivant avant l'envoi. La taille du
    // conteneur circulaire est environ 2x la taille d'icône demandée (voir
    // les appels _giftIcon(..., 22) / (..., 30) plus bas).
    return QuantumLoveHeart(size: size * 2, name: recipientName);
  }
  if (gift.isSketchedHeart) {
    return SketchedLoveHeart(size: size * 2);
  }
  if (gift.isEternalRose) {
    return EternalRose(size: size * 2);
  }
  if (gift.isBlackRose) {
    // interactive: false dans la grille — le glissement au doigt doit
    // faire défiler la boutique ici, pas pivoter la rose (réservé à la
    // vue plein écran du Carnet de bord).
    return RealisticBlackRose(size: size * 2, interactive: false);
  }
  if (gift.isWordHeart) {
    return WordHeart(size: size * 2, interactive: false, isDark: isDark);
  }
  if (_isNetworkPath(gift.iconPath)) {
    // BoxFit.cover pour remplir tout le cercle (pas de bande de couleur
    // teintée qui dépasse autour) — le parent doit rester clipBehavior:
    // Clip.antiAlias pour respecter la forme circulaire.
    return Image.network(
      gift.iconPath!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, error, stackTrace) => Icon(_iconForGift(gift), color: color, size: size),
    );
  }
  return Center(child: Icon(_iconForGift(gift), color: color, size: size));
}

/// Icône affinée par mot-clé du nom du cadeau — repli tant qu'aucune
/// illustration n'a été choisie dans l'admin (voir [_giftIcon]).
IconData _iconForGift(Gift gift) {
  final n = gift.name.toLowerCase();
  if (n.contains('lettre')) return Icons.mail_rounded;
  if (n.contains('bouquet') ||
      n.contains('tulipe') ||
      n.contains('rose') ||
      n.contains('fleur')) {
    return Icons.local_florist_rounded;
  }
  if (n.contains('coucher de soleil')) return Icons.wb_twilight_rounded;
  if (n.contains('bougie')) return Icons.local_fire_department_rounded;
  if (n.contains('chocolat') || n.contains('macaron') || n.contains('fraise')) {
    return Icons.cookie_rounded;
  }
  if (n.contains('glace')) return Icons.icecream_rounded;
  if (n.contains('cupcake') || n.contains('gâteau') || n.contains('gateau')) {
    return Icons.cake_rounded;
  }
  if (n.contains('montre')) return Icons.watch_rounded;
  if (n.contains('bracelet') ||
      n.contains('boucle') ||
      n.contains('collier') ||
      n.contains('bague') ||
      n.contains('diamant')) {
    return Icons.diamond_rounded;
  }
  if (n.contains('parfum')) return Icons.spa_rounded;
  if (n.contains('sac')) return Icons.shopping_bag_rounded;
  if (n.contains('yacht')) return Icons.sailing_rounded;
  if (n.contains('voiture')) return Icons.directions_car_filled_rounded;
  if (n.contains('villa') || n.contains('château') || n.contains('chateau')) {
    return Icons.villa_rounded;
  }
  if (n.contains('bisou')) return Icons.emoji_emotions_rounded;
  if (n.contains('ballon') ||
      n.contains('feu d\'artifice') ||
      n.contains('feu d’artifice')) {
    return Icons.celebration_rounded;
  }
  if (n.contains('nounours')) return Icons.toys_rounded;
  if (n.contains('chaton') || n.contains('chiot') || n.contains('panda')) {
    return Icons.pets_rounded;
  }
  if (n.contains('couronne')) return Icons.workspace_premium_rounded;
  if (n.contains('voyage')) return Icons.flight_rounded;
  if (n.contains('cœur') || n.contains('coeur')) return Icons.favorite_rounded;
  return _metaFor(gift.category).icon;
}

class GiftsScreen extends StatefulWidget {
  final AppUser? user;

  const GiftsScreen({super.key, this.user});

  @override
  State<GiftsScreen> createState() => _GiftsScreenState();
}

class _GiftsScreenState extends State<GiftsScreen> {
  late Future<List<Gift>> _future;
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _future = ShopService.instance.fetchGifts();
  }

  Future<void> _sendGift(Gift gift) async {
    final theme = ThemeScope.paletteOf(context);
    final myId = widget.user?.id;
    final partnerName = myId != null
        ? BoxScope.of(context).currentBox?.partnerOf(myId)?.prenom
        : null;
    final messageController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => _GiftConfirmDialog(
        gift: gift,
        partnerName: partnerName ?? 'ton/ta partenaire',
        messageController: messageController,
        theme: theme,
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ShopService.instance.sendGift(
        gift.id,
        message: messageController.text.trim(),
      );
      await WalletBalanceNotifier.instance.refresh();
      // Sinon le Carnet de bord (gardé en mémoire, voir MainTabScreen)
      // n'affiche ce cadeau qu'après une actualisation manuelle.
      TimelineRefreshSignal.instance.requestRefresh();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('« ${gift.name} » envoyé 💕')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LocaleScope.of(context).t('common_network_error'))),
      );
    }
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
          'Cadeaux',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: theme.textOnBackground,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: CoinBalanceBadge()),
          ),
        ],
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: FutureBuilder<List<Gift>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const EmptyState(
                  icon: Icons.wifi_off_rounded,
                  message: 'Impossible de charger les cadeaux.',
                );
              }
              final gifts = snapshot.data ?? [];
              if (gifts.isEmpty) {
                return const EmptyState(
                  icon: Icons.card_giftcard_rounded,
                  message: "Aucun cadeau disponible pour l'instant.",
                );
              }

              final presentCategories =
                  gifts.map((g) => g.category).toSet().toList()..sort(
                    (a, b) => _categories.keys
                        .toList()
                        .indexOf(a)
                        .compareTo(_categories.keys.toList().indexOf(b)),
                  );
              final visible = _selectedCategory == null
                  ? gifts
                  : gifts
                        .where((g) => g.category == _selectedCategory)
                        .toList();

              return Column(
                children: [
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        _GlassChip(
                          label: 'Tous',
                          icon: Icons.grid_view_rounded,
                          color: theme.textOnBackground,
                          selected: _selectedCategory == null,
                          theme: theme,
                          onTap: () => setState(() => _selectedCategory = null),
                        ),
                        for (final category in presentCategories) ...[
                          const SizedBox(width: 8),
                          _GlassChip(
                            label: _metaFor(category).label,
                            icon: _metaFor(category).icon,
                            color: _metaFor(category).color(theme),
                            selected: _selectedCategory == category,
                            theme: theme,
                            onTap: () =>
                                setState(() => _selectedCategory = category),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(20),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 0.78,
                          ),
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final gift = visible[index];
                        return _GiftTile(
                          gift: gift,
                          onTap: () => _sendGift(gift),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Pilule translucide (verre dépoli) pour les filtres de catégorie — une
/// lueur diffuse dans la couleur de la catégorie souligne l'onglet actif,
/// pour se détacher du fond étoilé sans un simple aplat de couleur.
class _GlassChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final ThemePalette theme;
  final VoidCallback onTap;

  const _GlassChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            // La bordure/lueur suit la couleur dominante du thème choisi
            // (pas la couleur de la catégorie) — montre que l'onglet actif
            // "vit" avec le thème plutôt que d'être un simple remplissage.
            border: Border.all(
              color: selected
                  ? theme.primary.withValues(alpha: 0.7)
                  : (theme.isDark ? Colors.white : Colors.black).withValues(
                      alpha: 0.1,
                    ),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: theme.primary.withValues(alpha: 0.5),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? color : theme.textOnBackgroundMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? color : theme.textOnBackgroundMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tuile de cadeau glassmorphism : illustration (ou icône affinée en
/// attendant), prix mis en avant dans une pastille dorée. Au tap, un
/// grossissement + une brève lueur avant l'ouverture de la modale de
/// confirmation — un cadeau qu'on choisit doit réagir, pas juste s'ouvrir.
class _GiftTile extends StatefulWidget {
  final Gift gift;
  final VoidCallback onTap;

  const _GiftTile({required this.gift, required this.onTap});

  @override
  State<_GiftTile> createState() => _GiftTileState();
}

class _GiftTileState extends State<_GiftTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _scale = TweenSequence([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.1,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 45,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.1,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 55,
    ),
  ]).animate(_controller);
  late final Animation<double> _glow = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 60),
  ]).animate(_controller);

  Future<void> _handleTap() async {
    HapticFeedback.lightImpact();
    _controller.forward(from: 0);
    await Future.delayed(const Duration(milliseconds: 160));
    if (mounted) widget.onTap();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final meta = _metaFor(widget.gift.category);
    final color = meta.color(theme);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _handleTap,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) =>
              Transform.scale(scale: _scale.value, child: child),
          child: Container(
            clipBehavior: Clip.antiAlias,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: (theme.isDark ? Colors.white : Colors.black).withValues(
                  alpha: 0.07,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: _giftIcon(widget.gift, color, 22, isDark: theme.isDark),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.gift.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.nunito(
                        fontWeight: FontWeight.w500,
                        fontSize: 12.5,
                        color: theme.textOnBackground,
                      ),
                    ),
                    // Micro-copy émotionnel — transforme la fiche produit en
                    // vitrine de sentiments plutôt qu'une liste d'objets.
                    if (widget.gift.description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.gift.description!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(
                          fontSize: 10.5,
                          fontStyle: FontStyle.italic,
                          color: theme.textOnBackgroundMuted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Abonnement actif : le cadeau est gratuit et illimité
                    // (voir GiftController côté backend, aucun débit pour
                    // un abonné) — plus aucune raison d'afficher son prix
                    // (voir demande utilisateur : "rien ne doit
                    // apparaître").
                    if (!SubscriptionStatusNotifier.instance.isActive)
                      // Pastille sombre neutre (pas teintée du thème) : le
                      // token doré s'y détache et "brille" par contraste,
                      // plutôt que de se fondre dans un aplat coloré.
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.34),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: _gold.withValues(alpha: 0.25),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CoinIcon(size: 14, fallbackColor: _gold),
                            const SizedBox(width: 4),
                            Text(
                              '${widget.gift.coinPrice}',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: _gold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _glow,
                    builder: (context, _) => IgnorePointer(
                      child: Opacity(
                        opacity: _glow.value * 0.5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: color,
                          ),
                        ),
                      ),
                    ),
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

/// Modale de confirmation d'envoi — remplace l'AlertDialog générique.
class _GiftConfirmDialog extends StatefulWidget {
  final Gift gift;
  final String partnerName;
  final TextEditingController messageController;
  final ThemePalette theme;

  const _GiftConfirmDialog({
    required this.gift,
    required this.partnerName,
    required this.messageController,
    required this.theme,
  });

  @override
  State<_GiftConfirmDialog> createState() => _GiftConfirmDialogState();
}

class _GiftConfirmDialogState extends State<_GiftConfirmDialog>
    with SingleTickerProviderStateMixin {
  // Rebond à l'ouverture — l'icône dépasse légèrement sa taille finale puis
  // revient, façon "pop" plutôt qu'une simple apparition statique.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  )..forward();
  late final Animation<double> _bounce = CurvedAnimation(
    parent: _controller,
    curve: Curves.elasticOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final gift = widget.gift;
    final meta = _metaFor(gift.category);
    final color = meta.color(theme);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _bounce,
              child: Container(
                width: 64,
                height: 64,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: _giftIcon(
                  gift,
                  color,
                  30,
                  // Pas de fallback générique ici : si le prénom n'est pas
                  // encore chargé, mieux vaut un cœur sans nom qu'un
                  // "ton/ta partenaire" écrit en toutes lettres dessus.
                  recipientName: widget.partnerName == 'ton/ta partenaire'
                      ? null
                      : widget.partnerName,
                  isDark: widget.theme.isDark,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              // Personnalisé par cadeau plutôt qu'une formule générique —
              // les guillemets évitent le piège de l'accord "ce/cette"
              // (le genre du nom du cadeau n'est pas connu côté app).
              'Tu veux offrir « ${gift.name} » à ${widget.partnerName} ?',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: theme.textOnBackground,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),
            // Abonnement actif : le cadeau est gratuit et illimité (voir
            // GiftController côté backend, aucun débit pour un abonné) —
            // plus aucune raison d'afficher son prix (voir demande
            // utilisateur : "rien ne doit apparaître").
            if (!SubscriptionStatusNotifier.instance.isActive)
              // Le prix est "l'attention qu'on offre" — le chiffre doit
              // sauter aux yeux, pas juste la phrase entière.
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  CoinIcon(size: 17, fallbackColor: _gold),
                  const SizedBox(width: 5),
                  Text(
                    '${gift.coinPrice}',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _gold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Tokens',
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: theme.textOnBackgroundMuted,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 18),
            // Zone de texte à fond délimité — se distingue du reste de la
            // modale plutôt qu'une simple ligne soulignée.
            Container(
              decoration: BoxDecoration(
                color: (theme.isDark ? Colors.white : Colors.black).withValues(
                  alpha: 0.06,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: TextField(
                controller: widget.messageController,
                maxLength: 200,
                maxLines: 2,
                minLines: 1,
                style: GoogleFonts.nunito(color: theme.textOnBackground),
                decoration: InputDecoration(
                  hintText: 'Ajoute une tendre pensée...',
                  hintStyle: GoogleFonts.nunito(
                    color: theme.textOnBackgroundMuted,
                    fontStyle: FontStyle.italic,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            Row(
              children: [
                // Discret : l'attention doit rester sur "Confirmer".
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    'Annuler',
                    style: GoogleFonts.nunito(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      color: theme.textOnBackgroundMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => Navigator.of(context).pop(true),
                      child: Ink(
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: LinearGradient(
                            colors: [theme.primary, _gold],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: theme.primary.withValues(alpha: 0.5),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            'Confirmer 💝',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
