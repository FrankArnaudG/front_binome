import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/token_storage.dart';
import '../../l10n/locale_scope.dart';
import '../../models/app_user.dart';
import '../../models/pack.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/empty_state.dart';
import 'content_service.dart';
import 'pack_favorite_storage.dart';
import 'pack_feed_screen.dart';
import 'widgets/pack_tile.dart';

/// Grille des poèmes-slides mis en favori (voir [PackFavoriteStorage]) —
/// atteinte depuis le bouton étoile de [PacksScreen], même mise en page
/// que [CategoryPacksScreen] (voir demande utilisateur : "la liste des
/// favoris peut être retrouvée dès l'entrée où y'a liste des différents
/// poème slide"). Refetch et refiltre à chaque retour d'un pack, comme
/// CategoryPacksScreen : un favori retiré depuis le feed doit disparaître
/// d'ici sans avoir à revenir plus loin en arrière.
class FavoritePacksScreen extends StatefulWidget {
  final String? replyToSendId;

  const FavoritePacksScreen({super.key, this.replyToSendId});

  @override
  State<FavoritePacksScreen> createState() => _FavoritePacksScreenState();
}

class _FavoritePacksScreenState extends State<FavoritePacksScreen> {
  late Future<List<Pack>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Pack>> _fetch() async {
    final userJson = await TokenStorage.instance.readUserJson();
    if (userJson == null) return const [];
    final user = AppUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
    final favoriteIds = await PackFavoriteStorage.instance.getFavoriteIds(user.id);
    if (favoriteIds.isEmpty) return const [];

    final packs = await ContentService.instance.fetchPacks();
    return packs.where((p) => favoriteIds.contains(p.id)).toList();
  }

  Future<void> _refresh() async {
    final future = _fetch();
    setState(() {
      _future = future;
    });
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
          t('favorite_packs_title'),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
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
                final packs = snapshot.data ?? [];
                if (packs.isEmpty) {
                  return ListView(
                    children: [
                      EmptyState(
                        icon: Icons.star_border_rounded,
                        message: t('favorite_packs_empty'),
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
