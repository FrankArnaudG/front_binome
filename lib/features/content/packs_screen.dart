import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/locale_scope.dart';
import '../../models/pack.dart';
import '../../models/pack_category.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/asset_or_fallback.dart';
import '../../widgets/empty_state.dart';
import 'category_packs_screen.dart';
import 'content_service.dart';
import 'favorite_packs_screen.dart';
import 'pack_categories.dart';

const double _kCardHeight = 128;
const double _kCardGap = 14;
const double _kItemExtent = _kCardHeight + _kCardGap;

/// Accueil de "Poèmes-Slides" — une liste dense de cartes de catégorie,
/// resserrées les unes sur les autres (façon menu d'activités) : la carte
/// la plus proche du centre de l'écran grossit et passe au premier plan
/// pendant le défilement, les autres rapetissent et s'estompent
/// légèrement — sans jamais créer de grand vide entre elles. Chaque
/// catégorie est une vraie destination qu'on choisit. Suit le thème
/// personnel choisi dans les Paramètres.
class PacksScreen extends StatefulWidget {
  /// Non nul lorsque cet écran est ouvert depuis la capsule d'un envoi reçu,
  /// pour "répondre avec un poème" : la slide choisie tout au bout du
  /// parcours (PacksScreen → CategoryPacksScreen → PackFeedScreen) sera
  /// envoyée en réponse à cet envoi plutôt qu'en envoi libre.
  final String? replyToSendId;

  const PacksScreen({super.key, this.replyToSendId});

  @override
  State<PacksScreen> createState() => _PacksScreenState();
}

// Nombre de "tours" de la liste réelle empilés pour simuler un défilement
// infini : assez grand pour qu'aucun utilisateur humain n'atteigne jamais
// un bord en scrollant (des dizaines de milliers de cartes dans chaque
// sens), tout en restant un nombre fini (ListView.builder l'exige).
const int _kLoopCount = 10000;

class _PacksScreenState extends State<PacksScreen> {
  late Future<(List<Pack>, List<PackCategory>)> _future;
  ScrollController? _scrollController;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<Pack>, List<PackCategory>)> _load() async {
    final results = await Future.wait([
      ContentService.instance.fetchPacks(),
      ContentService.instance.fetchPackCategories(),
    ]);
    return (results[0] as List<Pack>, results[1] as List<PackCategory>);
  }

  @override
  void dispose() {
    _scrollController?.dispose();
    super.dispose();
  }

  /// Créé une seule fois, dès que le nombre réel de catégories est connu —
  /// démarre au milieu de la plage "infinie" pour pouvoir défiler très
  /// longtemps aussi bien vers le haut que vers le bas.
  ScrollController _scrollControllerFor(int categoryCount) {
    // Avec une seule catégorie non vide, boucler n'a aucun sens : ça
    // remplit l'écran de cartes identiques (voir demande utilisateur,
    // capture montrant "Séduction" répétée 4 fois) plutôt que de donner
    // l'illusion d'un défilement infini entre plusieurs catégories.
    if (categoryCount <= 1) {
      return _scrollController ??= ScrollController();
    }
    return _scrollController ??= ScrollController(
      initialScrollOffset: (categoryCount * (_kLoopCount ~/ 2)) * _kItemExtent,
    );
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _future = future;
    });
    await future;
  }

  void _openCategory(String category, String categoryLabel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryPacksScreen(
          category: category,
          categoryLabel: categoryLabel,
          replyToSendId: widget.replyToSendId,
        ),
      ),
    );
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
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(
          t('action_poems'),
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: theme.textOnBackground,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.star_rounded),
            tooltip: t('favorite_packs_tooltip'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    FavoritePacksScreen(replyToSendId: widget.replyToSendId),
              ),
            ),
          ),
        ],
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: RefreshIndicator(
            color: theme.primary,
            backgroundColor: theme.surface,
            onRefresh: _refresh,
            child: FutureBuilder<(List<Pack>, List<PackCategory>)>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return ListView(
                    children: [
                      EmptyState(
                        icon: Icons.wifi_off_rounded,
                        message: t('poems_load_error'),
                      ),
                    ],
                  );
                }
                final (packs, categories) =
                    snapshot.data ?? (const <Pack>[], const <PackCategory>[]);
                if (packs.isEmpty) {
                  return ListView(
                    children: [
                      EmptyState(
                        icon: Icons.auto_stories_rounded,
                        message: t('poems_empty'),
                      ),
                    ],
                  );
                }

                // Ordre venu de l'admin (PackCategory.sort_order, voir
                // ContentService.fetchPackCategories) — une catégorie
                // référencée par un pack mais introuvable côté admin (ex.
                // supprimée depuis) part en fin de liste plutôt que de
                // planter.
                final categorySlugOrder = categories
                    .map((c) => c.slug)
                    .toList();
                final categoryBySlug = {for (final c in categories) c.slug: c};
                final presentCategories =
                    packs.map((p) => p.category).toSet().toList()..sort(
                      (a, b) => categorySlugOrder
                          .indexOf(a)
                          .compareTo(categorySlugOrder.indexOf(b)),
                    );
                final categoryCount = presentCategories.length;
                final scrollController = _scrollControllerFor(categoryCount);

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 10),
                      child: Column(
                        children: [
                          Text(
                            t('poems_hero_title'),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: theme.textOnBackground,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            t('poems_hero_subtitle'),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.nunito(
                              fontSize: 13,
                              color: theme.textOnBackgroundMuted,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final viewportHeight = constraints.maxHeight;
                          // Pas de grande marge haut/bas cette fois : la liste
                          // démarre juste sous l'en-tête, sans grand vide — la
                          // 1ère/dernière carte n'a pas besoin d'atteindre le
                          // centre exact pour que l'effet reste convaincant.
                          const topInset = 4.0;

                          return ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.only(
                              top: topInset,
                              bottom: 24,
                            ),
                            itemExtent: _kItemExtent,
                            // Un très grand nombre fini d'éléments (voir
                            // _kLoopCount) plutôt qu'un vrai "infini" — Flutter
                            // n'accepte pas itemCount: null avec itemExtent ;
                            // l'index réel boucle sur les vraies catégories.
                            // Pas de boucle avec une seule catégorie (voir
                            // _scrollControllerFor) : une carte, pas de
                            // répétition à l'écran.
                            itemCount: categoryCount <= 1
                                ? categoryCount
                                : categoryCount * _kLoopCount,
                            itemBuilder: (context, index) {
                              final category =
                                  presentCategories[index % categoryCount];
                              final count = packs
                                  .where((p) => p.category == category)
                                  .length;
                              final localeCode = LocaleScope.of(
                                context,
                              ).current.code;
                              final categoryLabel =
                                  categoryBySlug[category]?.labelFor(
                                    localeCode,
                                  ) ??
                                  category;
                              final categoryTagline =
                                  categoryBySlug[category]?.taglineFor(
                                    localeCode,
                                  ) ??
                                  '';

                              return AnimatedBuilder(
                                animation: scrollController,
                                builder: (context, child) {
                                  double t = 0;
                                  if (scrollController.hasClients) {
                                    final itemCenter =
                                        topInset +
                                        index * _kItemExtent +
                                        _kItemExtent / 2 -
                                        scrollController.offset;
                                    final viewportCenter = viewportHeight / 2;
                                    // Distance courte : l'effet retombe vite,
                                    // pour un contraste net entre la carte
                                    // centrale et ses voisines immédiates.
                                    const maxDistance = _kItemExtent * 1.6;
                                    t =
                                        ((itemCenter - viewportCenter).abs() /
                                                maxDistance)
                                            .clamp(0.0, 1.0);
                                  }
                                  return Center(
                                    child: Opacity(
                                      // Chute d'opacité légère seulement : les
                                      // cartes doivent rester des "fenêtres"
                                      // opaques et lisibles même loin du
                                      // centre, quelle que soit la densité
                                      // d'étoiles derrière — la profondeur se
                                      // lit surtout via l'échelle ci-dessous.
                                      opacity: 1 - t * 0.18,
                                      child: Transform.scale(
                                        scale: 1 - t * 0.32,
                                        child: child,
                                      ),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: _kCardGap / 2,
                                  ),
                                  child: _CategoryCard(
                                    visual: visualForCategory(category),
                                    label: categoryLabel,
                                    tagline: categoryTagline,
                                    theme: theme,
                                    packCount: count,
                                    onTap: () =>
                                        _openCategory(category, categoryLabel),
                                  ),
                                ),
                              );
                            },
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
      ),
    );
  }
}

class _CategoryCard extends StatefulWidget {
  final PackCategoryVisual visual;
  final String label;
  final String tagline;
  final ThemePalette theme;
  final int packCount;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.visual,
    required this.label,
    required this.tagline,
    required this.theme,
    required this.packCount,
    required this.onTap,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final visual = widget.visual;
    final theme = widget.theme;
    final t = LocaleScope.of(context).t;
    final packCount = widget.packCount;
    final gradient = visual.gradient(theme);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            height: _kCardHeight,
            padding: const EdgeInsets.all(1.4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              // Bordure fine en dégradé "or rose" — fait ressortir la carte
              // sur le fond étoilé et souligne l'effet glassmorphism.
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFF6D9B3),
                  Color(0xFFE8A9A0),
                  Color(0xFFF6D9B3),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: gradient.first.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22.6),
                gradient: LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: [
                  // Illustration qui déborde légèrement en bas à droite — retombe
                  // sur une grande icône semi-transparente tant que l'image n'a
                  // pas été livrée (voir assets/images/{visual.assetName}).
                  Positioned(
                    right: -6,
                    bottom: -6,
                    child: SizedBox(
                      width: 100,
                      height: 100,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Teinte très légère de la couleur signature du
                          // thème actif sur l'icône elle-même — crée un lien
                          // visuel avec le reste de l'app sans halo sombre
                          // derrière, en s'harmonisant avec chaque thème.
                          AssetOrFallback(
                            assetPath: 'assets/images/${visual.assetName}',
                            fit: BoxFit.contain,
                            fallback: Icon(
                              visual.icon,
                              size: 68,
                              color: Color.lerp(
                                Colors.white,
                                theme.primary,
                                0.25,
                              )!.withValues(alpha: 0.24),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      t(
                                        packCount > 1
                                            ? 'pack_count_other'
                                            : 'pack_count_one',
                                        {'count': '$packCount'},
                                      ),
                                      style: GoogleFonts.nunito(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                widget.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1.1,
                                  // Ombre plus marquée que le sous-titre — le
                                  // titre doit être l'élément le plus visible
                                  // de la carte, quel que soit le fond derrière.
                                  shadows: const [
                                    Shadow(
                                      color: Colors.black54,
                                      blurRadius: 8,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                widget.tagline,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.nunito(
                                  fontSize: 11.5,
                                  color: Colors.white.withValues(alpha: 0.9),
                                  height: 1.25,
                                  shadows: const [
                                    Shadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 56),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 14,
                    top: 14,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white,
                        size: 17,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
