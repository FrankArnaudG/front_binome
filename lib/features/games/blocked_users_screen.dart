import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../models/public_profile.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/empty_state.dart';
import 'game_service.dart';

/// Voir demande utilisateur : "on peut voir la liste des personnes qu'on a
/// bloqué et débloquer si on veut" — accessible depuis FriendsListScreen.
/// Jamais l'inverse (qui m'a bloqué·e) — FriendController::blocked() ne
/// renvoie que MES blocages.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  late Future<List<PublicProfile>> _blockedFuture;

  @override
  void initState() {
    super.initState();
    _blockedFuture = GameService.instance.fetchBlockedUsers();
  }

  Future<void> _refresh() async {
    final future = GameService.instance.fetchBlockedUsers();
    setState(() => _blockedFuture = future);
    await future;
  }

  Future<void> _unblock(PublicProfile user) async {
    try {
      await GameService.instance.unblockUser(user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${user.fullName} débloqué·e.')));
      _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Une erreur est survenue, réessaie.')));
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
          'Personnes bloquées',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: FutureBuilder<List<PublicProfile>>(
            future: _blockedFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Center(child: CircularProgressIndicator(color: theme.primary));
              }
              if (snapshot.hasError) {
                final message = snapshot.error is ApiException
                    ? (snapshot.error as ApiException).message
                    : 'Impossible de charger la liste, réessaie.';
                return RefreshIndicator(
                  color: theme.primary,
                  onRefresh: _refresh,
                  child: ListView(
                    children: [EmptyState(icon: Icons.error_outline_rounded, message: message)],
                  ),
                );
              }

              final blocked = snapshot.data!;
              if (blocked.isEmpty) {
                return RefreshIndicator(
                  color: theme.primary,
                  onRefresh: _refresh,
                  child: ListView(
                    children: const [
                      EmptyState(
                        icon: Icons.block_rounded,
                        message: "Personne n'est bloqué pour l'instant.",
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                color: theme.primary,
                onRefresh: _refresh,
                child: ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: blocked.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final user = blocked[index];
                    return Material(
                      color: theme.surface.withValues(alpha: theme.isDark ? 0.5 : 0.75),
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: theme.primary.withValues(alpha: 0.16),
                              backgroundImage: (user.avatar != null && user.avatar!.isNotEmpty)
                                  ? CachedNetworkImageProvider(user.avatar!)
                                  : null,
                              child: (user.avatar == null || user.avatar!.isEmpty)
                                  ? Text(
                                      user.prenom.isNotEmpty ? user.prenom[0].toUpperCase() : '?',
                                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.primary, fontSize: 14),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                user.fullName,
                                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: theme.textOnBackground),
                              ),
                            ),
                            OutlinedButton(
                              onPressed: () => _unblock(user),
                              child: const Text('Débloquer'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
