import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/locale_scope.dart';
import '../../models/pack.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/empty_state.dart';
import 'content_service.dart';
import 'pack_categories.dart';
import 'pack_feed_screen.dart';

bool _isNetworkPath(String? path) =>
    path != null && (path.startsWith('http://') || path.startsWith('https://'));

/// Grille des packs d'une seule catégorie de Poèmes-Slides — atteinte en
/// tapant une carte de catégorie sur [PacksScreen]. Refetch et refiltre à
/// chaque retour d'un pack (déblocage possible) plutôt que de recevoir une
/// liste figée en paramètre. Suit le thème personnel choisi.
class CategoryPacksScreen extends StatefulWidget {
  final String category;

  /// Déjà résolu par [PacksScreen] (qui a dû charger la liste des
  /// catégories pour construire ses propres cartes) — évite un second
  /// aller-retour réseau ici juste pour le titre de l'AppBar.
  final String categoryLabel;

  /// Transmis depuis [PacksScreen] lorsqu'on est dans un parcours de
  /// réponse — voir sa doc pour le détail du flux.
  final String? replyToSendId;

  const CategoryPacksScreen({super.key, required this.category, required this.categoryLabel, this.replyToSendId});

  @override
  State<CategoryPacksScreen> createState() => _CategoryPacksScreenState();
}

class _CategoryPacksScreenState extends State<CategoryPacksScreen> {
  late Future<List<Pack>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Pack>> _fetch() async {
    final packs = await ContentService.instance.fetchPacks();
    return packs.where((p) => p.category == widget.category).toList();
  }

  Future<void> _refresh() async {
    final future = _fetch();
    setState(() { _future = future; });
    await future;
  }

  Future<void> _openPack(Pack pack) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PackFeedScreen(
          packId: pack.id,
          replyToSendId: widget.replyToSendId,
        ),
      ),
    );
    if (result == true) _refresh();
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
          widget.categoryLabel,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: theme.textOnBackground,
          ),
        ),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: RefreshIndicator(
            color: theme.primary,
            backgroundColor: theme.surface,
            onRefresh: _refresh,
            child: FutureBuilder<List<Pack>>(
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
                final packs = snapshot.data ?? [];
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
                return GridView.builder(
                  padding: const EdgeInsets.all(20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: packs.length,
                  itemBuilder: (context, index) {
                    final pack = packs[index];
                    return _PackTile(
                      pack: pack,
                      theme: theme,
                      onTap: () => _openPack(pack),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PackTile extends StatelessWidget {
  final Pack pack;
  final ThemePalette theme;
  final VoidCallback onTap;

  const _PackTile({
    required this.pack,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final visual = visualForCategory(pack.category);
    final gradient = visual.gradient(theme);

    return Material(
      color: theme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Cover choisie dans l'admin (hébergée sur le serveur)
                      // si elle existe, sinon repli sur l'illustration
                      // provisoire générique en attendant un visuel dédié.
                      if (_isNetworkPath(pack.coverPath))
                        Image.network(
                          pack.coverPath!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Image.asset(
                                'assets/images/hero_couple.jpg',
                                fit: BoxFit.cover,
                              ),
                        )
                      else
                        Image.asset(
                          'assets/images/hero_couple.jpg',
                          fit: BoxFit.cover,
                        ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              gradient.first.withValues(alpha: 0.55),
                              gradient.last.withValues(alpha: 0.78),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                pack.titleFor(LocaleScope.of(context).current.code),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: theme.textOnBackground,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
