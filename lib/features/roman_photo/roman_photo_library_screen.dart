import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/locale_scope.dart';
import '../../theme/theme_scope.dart';
import '../../widgets/coin_icon.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/wood_texture.dart';
import '../shop/subscription_status_notifier.dart';
import 'roman_photo_download_service.dart';
import 'roman_photo_local_db.dart';
import 'roman_photo_purchase_flow.dart';
import 'roman_photo_reader_screen.dart';
import 'roman_photo_service.dart';
import 'roman_photo_story.dart';

/// Filtre de l'étagère (voir demande utilisateur : "on peut filtrer par...
/// nouveau, télécharger") — `all`/`newOnly` sont résolus côté serveur (voir
/// RomanPhotoService.fetchLibraryPage `onlyNew`), `downloadedOnly` est
/// purement local (le serveur n'a aucune notion des téléchargements d'un
/// appareil précis), voir _loadDownloadedOnly.
enum _RomanPhotoFilter { all, newOnly, downloadedOnly }

/// Bibliothèque des romans-photo — les histoires posées sur des étagères,
/// comme de vrais livres. Chaque histoire peut compter un ou plusieurs
/// tomes : un seul tome ouvre directement le lecteur, plusieurs proposent
/// d'abord un choix (voir _openStory/_VolumePickerScreen). Gérée entièrement
/// depuis l'espace admin (voir RomanPhotoService).
///
/// Seule la couverture de chaque histoire est chargée par défaut (voir
/// RomanPhotoService.fetchLibraryPage) — les tomes/pages complets d'une
/// histoire ne sont récupérés qu'à l'ouverture de CETTE histoire (voir
/// _openStory), pour ne jamais télécharger d'un coup toutes les images de
/// toute la bibliothèque à la connexion (voir demande utilisateur). Le rayon
/// lui-même est paginé (voir _scrollController/_loadMore) : seules les
/// premières histoires sont chargées, les suivantes au fil du scroll.
class RomanPhotoLibraryScreen extends StatefulWidget {
  const RomanPhotoLibraryScreen({super.key});

  @override
  State<RomanPhotoLibraryScreen> createState() => _RomanPhotoLibraryScreenState();
}

class _RomanPhotoLibraryScreenState extends State<RomanPhotoLibraryScreen> {
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _openingStory = false;
  Object? _error;
  int _nextPage = 1;
  List<RomanPhotoStory> _stories = [];
  // Histoires ayant au moins un tome déjà téléchargé sur CET appareil (voir
  // RomanPhotoLocalDb.downloadedStoriesAmong) — pilote à la fois le badge
  // "Nouveau" (masqué une fois téléchargé) et le repère "déjà téléchargé"
  // sur chaque tuile (voir demande utilisateur).
  Set<String> _downloadedStoryIds = {};
  _RomanPhotoFilter _filter = _RomanPhotoFilter.all;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final position = _scrollController.position;
    // Même seuil que GameBoxHistoryScreen/EmojiStoryHistoryScreen — charge
    // la page suivante un peu avant d'atteindre le bas plutôt qu'au dernier
    // pixel.
    if (_hasMore && !_loadingMore && position.pixels >= position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _setFilter(_RomanPhotoFilter filter) {
    if (filter == _filter) return;
    setState(() {
      _filter = filter;
      _stories = [];
      _nextPage = 1;
      _hasMore = false;
    });
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    if (_filter == _RomanPhotoFilter.downloadedOnly) return _loadDownloadedOnly();

    // Le cache est vérifié AVANT d'afficher le spinner (pas en parallèle) —
    // dès qu'une première page a déjà été vue une fois, les ouvertures
    // suivantes affichent les couvertures instantanément, sans aucun flash
    // de chargement, pendant que la vraie requête réseau tourne en fond
    // (voir demande utilisateur). Seule la vue par défaut (sans filtre) a un
    // cache (voir RomanPhotoService.fetchLibraryPage).
    if (_filter == _RomanPhotoFilter.all) {
      final cached = await RomanPhotoService.instance.cachedFirstPage();
      if (!mounted) return;
      if (cached != null) {
        setState(() {
          _stories = cached;
          _loading = false;
          _error = null;
        });
        unawaited(_refreshDownloadedIds());
      } else {
        setState(() {
          _loading = true;
          _error = null;
        });
      }
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await RomanPhotoService.instance.fetchLibraryPage(1, onlyNew: _filter == _RomanPhotoFilter.newOnly);
      if (!mounted) return;
      setState(() {
        _stories = page.items;
        _hasMore = page.hasMore;
        _nextPage = 2;
        _loading = false;
        _error = null;
      });
      await _refreshDownloadedIds();
    } catch (e) {
      if (!mounted) return;
      if (_stories.isEmpty) setState(() => _error = e);
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final page = await RomanPhotoService.instance.fetchLibraryPage(
        _nextPage,
        onlyNew: _filter == _RomanPhotoFilter.newOnly,
      );
      if (!mounted) return;
      setState(() {
        _stories = [..._stories, ...page.items];
        _hasMore = page.hasMore;
        _nextPage++;
      });
      await _refreshDownloadedIds();
    } catch (_) {
      // Silencieux — le rayon garde ce qu'il a déjà, un nouveau scroll
      // relancera une tentative (voir _onScroll).
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Filtre "Téléchargés" — purement local (voir _RomanPhotoFilter), donc
  /// sans pagination serveur possible : parcourt les pages de l'étagère
  /// jusqu'à épuisement (plafonné, une bibliothèque personnelle reste de
  /// taille modeste) puis ne garde que les histoires déjà téléchargées.
  Future<void> _loadDownloadedOnly() async {
    setState(() {
      _loading = true;
      _error = null;
      _hasMore = false;
    });
    try {
      final all = <RomanPhotoStory>[];
      var page = 1;
      while (page <= 10) {
        final result = await RomanPhotoService.instance.fetchLibraryPage(page);
        all.addAll(result.items);
        if (!result.hasMore) break;
        page++;
      }
      final downloadedIds = await RomanPhotoLocalDb.instance.downloadedStoriesAmong(all.map((s) => s.id));
      if (!mounted) return;
      setState(() {
        _stories = all.where((s) => downloadedIds.contains(s.id)).toList();
        _downloadedStoryIds = downloadedIds;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _refreshDownloadedIds() async {
    final ids = await RomanPhotoLocalDb.instance.downloadedStoriesAmong(_stories.map((s) => s.id));
    if (mounted) setState(() => _downloadedStoryIds = ids);
  }

  static const _tileWidth = 96.0;
  static const _tileSpacing = 18.0;
  static const _horizontalPadding = 16.0;

  /// Charge le détail complet de l'histoire (tomes/pages/teaser) avant de
  /// naviguer — la couverture affichée sur l'étagère ne suffit jamais à
  /// décider où aller (voir RomanPhotoStory.volumes, vide tant que ce
  /// détail n'a pas été chargé).
  Future<void> _openStory(BuildContext context, RomanPhotoStory summary) async {
    if (_openingStory) return;
    setState(() => _openingStory = true);
    RomanPhotoStory story;
    try {
      story = await RomanPhotoService.instance.fetchStoryDetail(summary.id);
    } catch (e) {
      if (mounted) {
        setState(() => _openingStory = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(LocaleScope.of(context).t('roman_photo_load_error'))));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _openingStory = false);

    // Livre entier pas encore sorti — rien à choisir, direction la fiche
    // teaser (voir RomanPhotoStory.isTeaserOnly).
    if (story.isTeaserOnly) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _TeaserScreen(story: story)));
      return;
    }
    // 1 seul tome sorti ET rien à venir en teaser — direction le lecteur
    // sans détour (s'il y a un tome à venir, même avec un seul tome sorti,
    // on montre le choix pour laisser la ligne teaser accessible).
    if (story.volumes.length == 1 && !story.comingSoon) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RomanPhotoReaderScreen(volume: story.volumes.first, storyId: story.id)),
      );
      // Un téléchargement a pu avoir lieu dans le lecteur — le repère
      // "déjà téléchargé"/le badge "Nouveau" de la tuile doivent en tenir
      // compte au retour, sans attendre un rafraîchissement manuel.
      if (mounted) unawaited(_refreshDownloadedIds());
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _VolumePickerScreen(story: story)));
    if (mounted) unawaited(_refreshDownloadedIds());
  }

  // Vrai grain de bois clair (voir WoodTexture) plutôt qu'un aplat sombre.
  // Deux teintes : le lambris du fond (plus profond, avec joints de
  // planches) et la planche de chaque étagère (plus claire, sans joints —
  // c'est une pièce continue).
  static const _wallWoodLight = Color(0xFFC98F52);
  static const _wallWoodDark = Color(0xFF8A5A30);
  static const _shelfWoodLight = Color(0xFFE3B77E);
  static const _shelfWoodDark = Color(0xFFB27C46);
  // Texte sombre plutôt que blanc — le bois clair choisi ici n'offre pas
  // assez de contraste pour du texte blanc.
  static const _onWood = Color(0xFF2E1D0F);
  static const _onWoodMuted = Color(0xB32E1D0F);

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return Scaffold(
      backgroundColor: _wallWoodDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle.copyWith(
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        foregroundColor: _onWood,
        title: Text(
          'Romans-photo',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: _onWood),
        ),
      ),
      body: WoodTexture(
        light: _wallWoodLight,
        dark: _wallWoodDark,
        seed: 7,
        showPlankSeams: true,
        plankHeight: 120,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(_horizontalPadding, 8, _horizontalPadding, 4),
                child: Row(
                  children: [
                    _FilterChip(
                      label: t('roman_photo_filter_all'),
                      selected: _filter == _RomanPhotoFilter.all,
                      onTap: () => _setFilter(_RomanPhotoFilter.all),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: t('roman_photo_filter_new'),
                      selected: _filter == _RomanPhotoFilter.newOnly,
                      onTap: () => _setFilter(_RomanPhotoFilter.newOnly),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: t('roman_photo_filter_downloaded'),
                      selected: _filter == _RomanPhotoFilter.downloadedOnly,
                      onTap: () => _setFilter(_RomanPhotoFilter.downloadedOnly),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: _onWood,
                  backgroundColor: _shelfWoodLight,
                  onRefresh: _loadFirstPage,
                  child: _loading
                      ? const Center(child: CircularProgressIndicator(color: _onWood))
                      : (_error != null
                            ? ListView(
                                children: [
                                  EmptyState(icon: Icons.wifi_off_rounded, message: t('roman_photo_load_error')),
                                ],
                              )
                            : (_stories.isEmpty
                                  ? Center(
                                      child: Text(
                                        'Aucun roman-photo pour l\'instant.',
                                        style: GoogleFonts.nunito(color: _onWoodMuted),
                                      ),
                                    )
                                  : LayoutBuilder(
                                builder: (context, constraints) {
                                  // Nombre de livres par étagère calculé
                                  // depuis la largeur réelle de l'écran
                                  // plutôt qu'une valeur fixe.
                                  final available = constraints.maxWidth - _horizontalPadding * 2;
                                  final booksPerShelf = ((available + _tileSpacing) / (_tileWidth + _tileSpacing))
                                      .floor()
                                      .clamp(1, _stories.length);

                                  final shelves = <List<RomanPhotoStory>>[];
                                  for (var i = 0; i < _stories.length; i += booksPerShelf) {
                                    shelves.add(_stories.sublist(i, (i + booksPerShelf).clamp(0, _stories.length)));
                                  }

                                  return ListView.builder(
                                    controller: _scrollController,
                                    padding: const EdgeInsets.fromLTRB(_horizontalPadding, 20, _horizontalPadding, 32),
                                    itemCount: shelves.length + (_loadingMore ? 1 : 0),
                                    itemBuilder: (context, shelfIndex) {
                                      if (shelfIndex >= shelves.length) {
                                        return const Padding(
                                          padding: EdgeInsets.symmetric(vertical: 16),
                                          child: Center(child: CircularProgressIndicator(color: _onWood)),
                                        );
                                      }
                                      final books = shelves[shelfIndex];
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 28),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                for (var i = 0; i < books.length; i++) ...[
                                                  if (i > 0) const SizedBox(width: _tileSpacing),
                                                  _BookTile(
                                                    story: books[i],
                                                    downloaded: _downloadedStoryIds.contains(books[i].id),
                                                    onTap: () => _openStory(context, books[i]),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 10),
                                            // La planche de l'étagère — vrai
                                            // grain de bois (voir
                                            // WoodTexture) plutôt qu'un
                                            // dégradé plat.
                                            DecoratedBox(
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(3),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withValues(alpha: 0.35),
                                                    blurRadius: 8,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ],
                                              ),
                                              child: WoodTexture(
                                                light: _shelfWoodLight,
                                                dark: _shelfWoodDark,
                                                seed: shelfIndex + 1,
                                                borderRadius: BorderRadius.circular(3),
                                                child: const SizedBox(height: 14, width: double.infinity),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                              ))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  final RomanPhotoStory story;
  // Voir RomanPhotoLibraryScreen._downloadedStoryIds — vrai si au moins un
  // tome de cette histoire est déjà téléchargé sur cet appareil. Masque le
  // badge "Nouveau" (voir demande utilisateur) et affiche un repère visuel
  // dédié.
  final bool downloaded;
  final VoidCallback onTap;

  const _BookTile({required this.story, required this.downloaded, required this.onTap});

  static const _tileHeight = 136.0;
  // Fine tranche de pages sur le bord droit (voir capture de référence
  // utilisateur : un vrai livre 3D, couverture pleine largeur + léger bord
  // clair suggérant l'épaisseur des pages).
  static const _pageEdgeWidth = 4.0;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final localeCode = LocaleScope.of(context).current.code;
    final volumeCount = story.volumeCountResolved;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: _BookTile._tileHeight,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              // Coins uniformément arrondis (voir capture de référence
              // utilisateur, une vraie couverture de livre 3D) — pas
              // d'angles asymétriques.
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                // Ombre douce et large plutôt qu'un simple décalage net —
                // donne l'impression que le livre repose sur l'étagère
                // (voir capture de référence).
                BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 8)),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: 0,
                  right: _BookTile._pageEdgeWidth,
                  top: 0,
                  bottom: 0,
                  child: CachedNetworkImage(
                    imageUrl: story.coverAsset,
                    fit: BoxFit.cover,
                    // Mise en cache disque (voir cached_network_image, déjà
                    // utilisé par le coffre-fort photo) — sans ça, chaque
                    // ouverture de cet écran retéléchargeait toutes les
                    // couvertures depuis zéro, quelques secondes de
                    // rectangles vides à chaque fois (voir capture
                    // utilisateur) même pour des histoires déjà vues.
                    placeholder: (context, url) =>
                        DecoratedBox(decoration: BoxDecoration(color: theme.primary.withValues(alpha: 0.15))),
                    errorWidget: (context, url, error) => DecoratedBox(
                      decoration: BoxDecoration(gradient: LinearGradient(colors: [theme.primary, theme.secondary])),
                      child: const Center(
                        child: Icon(Icons.auto_stories_rounded, color: Colors.white, size: 28),
                      ),
                    ),
                  ),
                ),
                // Tranche de pages côté droit — dégradé clair/gris plutôt
                // qu'un à-plat, pour suggérer l'épaisseur du livre vu de
                // biais (voir capture de référence utilisateur).
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: _BookTile._pageEdgeWidth,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFE4DDD0), Color(0xFFFAF7EF)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                ),
                // Repère "déjà téléchargé" + badge nombre de tomes, groupés
                // dans le même coin (voir demande utilisateur : "ce qui est
                // déjà téléchargé on doit savoir").
                if (downloaded || volumeCount > 1)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (downloaded)
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            // Rouge de l'app (voir ThemeScope, s'adapte à
                            // chaque thème) plutôt que blanc — demande
                            // utilisateur : le repère "déjà téléchargé" doit
                            // reprendre la couleur de l'app.
                            child: Icon(Icons.download_done_rounded, color: theme.primary, size: 11),
                          ),
                        if (downloaded && volumeCount > 1) const SizedBox(width: 4),
                        if (volumeCount > 1)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$volumeCount tomes',
                              style: GoogleFonts.nunito(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                // Badge "Nouveau" (voir espace admin) — masqué dès que
                // téléchargé sur cet appareil (voir demande utilisateur).
                if (story.isNew && !downloaded)
                  Positioned(
                    left: 0,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE0324B),
                        borderRadius: BorderRadius.only(topRight: Radius.circular(4), bottomRight: Radius.circular(4)),
                      ),
                      child: Text(
                        LocaleScope.of(context).t('roman_photo_badge_new').toUpperCase(),
                        style: GoogleFonts.nunito(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                // Prix affiché sur la couverture seulement pour une
                // histoire à un seul tome — au-delà, le prix varie par
                // tome et n'apparaît que dans le choix (voir
                // _VolumePickerScreen).
                if (volumeCount == 1 && story.firstVolumePrice != null)
                  Positioned(left: 4, bottom: 4, child: _PriceBadge(coinPrice: story.firstVolumePrice!)),
                // Bandeau "Bientôt" sur toute la couverture seulement si
                // AUCUN tome n'est encore sorti — sinon (tomes 1/2 sortis
                // + un teaser pour le tome suivant), le bandeau donnerait
                // l'impression que le livre entier n'est pas encore
                // disponible. Dans ce cas, le teaser n'apparaît que comme
                // une ligne de plus dans le choix du tome.
                if (story.isTeaserOnly)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      color: Colors.black.withValues(alpha: 0.6),
                      child: Text(
                        'Bientôt',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.nunito(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Hauteur fixe (toujours la place de 2 lignes, même si le titre
          // tient sur une seule) — sinon la Row alignée par le bas (voir
          // crossAxisAlignment.end) remonte les couvertures dont le titre
          // est court, au lieu de les garder toutes au même niveau.
          SizedBox(
            width: 96,
            height: 30,
            child: Text(
              story.titleFor(localeCode),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _RomanPhotoLibraryScreenState._onWood,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Puce de filtre de l'étagère (voir _RomanPhotoFilter) — style pilule,
/// couleur pleine quand sélectionnée, contour discret sinon.
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const onWood = _RomanPhotoLibraryScreenState._onWood;

    return Material(
      color: selected ? onWood : Colors.white.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : onWood,
            ),
          ),
        ),
      ),
    );
  }
}

/// Badge "Gratuit" ou prix en tokens — juste l'indication pour l'instant,
/// aucun débit ni verrouillage réel (voir RomanPhotoVolume.coinPrice).
class _PriceBadge extends StatelessWidget {
  final int coinPrice;

  const _PriceBadge({required this.coinPrice});

  @override
  Widget build(BuildContext context) {
    // Abonnement actif : le tome est gratuit et illimité (voir
    // RomanPhotoVolume.needsPurchase et RomanPhotoPurchaseController côté
    // backend) — plus aucune raison d'afficher un prix en tokens (voir
    // demande utilisateur : "rien ne doit apparaître").
    if (coinPrice > 0 && SubscriptionStatusNotifier.instance.isActive) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: coinPrice <= 0
          ? Text('Gratuit', style: GoogleFonts.nunito(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CoinIcon(size: 12),
                const SizedBox(width: 3),
                Text(
                  '$coinPrice',
                  style: GoogleFonts.nunito(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ],
            ),
    );
  }
}

/// Choix du tome — uniquement pour une histoire à plusieurs tomes (voir
/// RomanPhotoLibraryScreen._openStory) : liste simple, pas une 2ᵉ étagère,
/// pour rester rapide à parcourir même avec beaucoup de tomes.
class _VolumePickerScreen extends StatelessWidget {
  final RomanPhotoStory story;

  const _VolumePickerScreen({required this.story});

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
          story.titleFor(localeCode),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          // Une ligne de plus si un tome à venir est teasé (voir
          // RomanPhotoStory.comingSoon), en premier, avant les tomes déjà
          // sortis.
          itemCount: story.volumes.length + (story.comingSoon ? 1 : 0),
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (story.comingSoon) {
              if (index == 0) return _TeaserRow(story: story);
              return _VolumeRow(volume: story.volumes[index - 1], storyId: story.id);
            }
            return _VolumeRow(volume: story.volumes[index], storyId: story.id);
          },
        ),
      ),
    );
  }
}

/// Une ligne "tome déjà sorti" du choix (voir _VolumePickerScreen) —
/// extraite pour être réutilisée qu'il y ait ou non une ligne teaser en
/// tête de liste. Porte aussi le bouton de téléchargement (voir
/// RomanPhotoDownloadService) : icône nuage tant que rien n'est téléchargé,
/// anneau de progression pendant le téléchargement, coche une fois terminé.
class _VolumeRow extends StatefulWidget {
  final RomanPhotoVolume volume;
  final String storyId;

  const _VolumeRow({required this.volume, required this.storyId});

  @override
  State<_VolumeRow> createState() => _VolumeRowState();
}

class _VolumeRowState extends State<_VolumeRow> {
  bool? _downloaded;

  @override
  void initState() {
    super.initState();
    _refreshDownloaded();
  }

  Future<void> _refreshDownloaded() async {
    final downloaded = await RomanPhotoLocalDb.instance.isDownloaded(widget.volume.id);
    if (mounted) setState(() => _downloaded = downloaded);
  }

  Future<void> _download() async {
    // Achat obligatoire AVANT le téléchargement pour un tome payant (voir
    // demande utilisateur) — no-op immédiat si gratuit ou déjà acheté.
    if (!await ensureRomanPhotoVolumePurchased(context, widget.volume)) return;
    if (!mounted) return;
    try {
      await RomanPhotoDownloadService.instance.download(widget.volume, widget.storyId);
      await _refreshDownloaded();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(LocaleScope.of(context).t('roman_photo_download_error'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final localeCode = LocaleScope.of(context).current.code;

    return Material(
      color: theme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RomanPhotoReaderScreen(volume: widget.volume, storyId: widget.storyId),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.auto_stories_rounded, color: theme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.volume.titleFor(localeCode),
                  style: GoogleFonts.nunito(fontWeight: FontWeight.w700, color: theme.textOnBackground),
                ),
              ),
              _PriceBadge(coinPrice: widget.volume.coinPrice),
              const SizedBox(width: 8),
              ValueListenableBuilder<double?>(
                valueListenable: RomanPhotoDownloadService.instance.progressFor(widget.volume.id),
                builder: (context, progress, _) {
                  if (progress != null) {
                    return SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, value: progress, color: theme.primary),
                    );
                  }
                  if (_downloaded == true) {
                    return Icon(Icons.download_done_rounded, color: theme.primary, size: 22);
                  }
                  return InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: _download,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.download_rounded, color: theme.textOnBackgroundMuted, size: 22),
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: theme.textOnBackgroundMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ligne "à venir" ajoutée en tête du choix du tome (voir
/// _VolumePickerScreen) — même gabarit que les tomes déjà sortis, mais un
/// contour en pointillés et un badge plutôt qu'un prix, pour qu'on
/// comprenne d'un coup d'œil qu'elle mène à un aperçu et pas à un vrai
/// tome. Le nom vient de RomanPhotoStory.teaserTitle (jamais "Tome N"
/// générique).
class _TeaserRow extends StatelessWidget {
  final RomanPhotoStory story;

  const _TeaserRow({required this.story});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final localeCode = LocaleScope.of(context).current.code;

    return Material(
      color: theme.surface.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _TeaserScreen(story: story))),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.textOnBackgroundMuted.withValues(alpha: 0.4), style: BorderStyle.solid),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: theme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  story.teaserTitleFor(localeCode) ?? 'Bientôt disponible',
                  style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w700,
                    fontStyle: FontStyle.italic,
                    color: theme.textOnBackgroundMuted,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: theme.primary, borderRadius: BorderRadius.circular(999)),
                child: Text(
                  'Disponible',
                  style: GoogleFonts.nunito(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: theme.textOnBackgroundMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fiche teaser d'une histoire "bientôt disponible" (voir
/// RomanPhotoStory.comingSoon) — une ou plusieurs images à feuilleter, un
/// court texte pour donner envie, aucune action réelle. Même mise en scène
/// immersive que RomanPhotoReaderScreen, pour rester cohérent visuellement.
class _TeaserScreen extends StatefulWidget {
  final RomanPhotoStory story;

  const _TeaserScreen({required this.story});

  @override
  State<_TeaserScreen> createState() => _TeaserScreenState();
}

class _TeaserScreenState extends State<_TeaserScreen> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final localeCode = LocaleScope.of(context).current.code;
    final images = widget.story.teaserImages;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle.copyWith(
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: images.length <= 1
                  ? Center(
                      child: CachedNetworkImage(
                        imageUrl: images.isNotEmpty ? images.first : '',
                        fit: BoxFit.contain,
                        placeholder: (context, url) =>
                            const Center(child: CircularProgressIndicator(color: Colors.white38)),
                        errorWidget: (context, url, error) =>
                            const Icon(Icons.auto_stories_rounded, color: Colors.white38, size: 64),
                      ),
                    )
                  : PageView.builder(
                      itemCount: images.length,
                      onPageChanged: (index) => setState(() => _page = index),
                      itemBuilder: (context, index) => Center(
                        child: CachedNetworkImage(
                          imageUrl: images[index],
                          fit: BoxFit.contain,
                          placeholder: (context, url) =>
                              const Center(child: CircularProgressIndicator(color: Colors.white38)),
                          errorWidget: (context, url, error) =>
                              const Icon(Icons.auto_stories_rounded, color: Colors.white38, size: 64),
                        ),
                      ),
                    ),
            ),
            if (images.length > 1) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(images.length, (index) {
                  final active = index == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active ? theme.primary : Colors.white24,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: theme.primary, borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      'Disponible',
                      style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.story.teaserTitleFor(localeCode) ?? widget.story.titleFor(localeCode),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  if (widget.story.teaserTextFor(localeCode) != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.story.teaserTextFor(localeCode)!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(fontSize: 13.5, height: 1.5, color: Colors.white70),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
