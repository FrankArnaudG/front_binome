import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/locale_scope.dart';
import '../../models/pack.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/empty_state.dart';
import 'content_service.dart';
import 'pack_feed_screen.dart';
import 'widgets/pack_tile.dart';

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
                    return PackTile(
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

