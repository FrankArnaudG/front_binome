import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../l10n/locale_scope.dart';
import '../../models/app_user.dart';
import '../../models/game.dart';
import '../../models/public_profile.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/empty_state.dart';
import 'blocked_users_screen.dart';
import 'friend_challenge_support.dart';
import 'game_invite_waiting_screen.dart';
import 'game_service.dart';

/// Liste des "amis de jeu" (voir FriendChallengeScreen) — se constitue
/// automatiquement dès qu'un défi hors-Box est accepté (voir
/// GameInviteController::accept), jamais via une demande d'ami explicite.
/// Voir demande utilisateur : taper sur un·e ami·e propose directement de
/// le/la défier (choix du jeu, sans ressaisir son code — voir
/// GameService.createGameInvite(friendUserId:)) ; l'action "voir/débloquer"
/// vit dans BlockedUsersScreen, accessible depuis la barre du haut.
class FriendsListScreen extends StatefulWidget {
  final AppUser user;

  const FriendsListScreen({super.key, required this.user});

  @override
  State<FriendsListScreen> createState() => _FriendsListScreenState();
}

class _FriendsListScreenState extends State<FriendsListScreen> {
  late Future<List<PublicProfile>> _friendsFuture;
  bool _challenging = false;

  @override
  void initState() {
    super.initState();
    _friendsFuture = GameService.instance.fetchFriends();
  }

  Future<void> _refresh() async {
    final future = GameService.instance.fetchFriends();
    setState(() => _friendsFuture = future);
    await future;
  }

  Future<void> _challengeFriend(PublicProfile friend) async {
    final theme = ThemeScope.paletteOf(context);
    final games = await GameService.instance.fetchGames();
    final challengeable = friendChallengeableGames(games);
    if (!mounted || challengeable.isEmpty) return;

    final game = await showModalBottomSheet<Game>(
      context: context,
      // Voir demande utilisateur (capture : les 7 jeux débordaient en bas
      // de l'écran, bande jaune/noire de Flutter visible) — la feuille
      // doit pouvoir dépasser sa hauteur par défaut (mi-écran) et devenir
      // scrollable au lieu de déborder silencieusement.
      isScrollControlled: true,
      backgroundColor: theme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _GamePickerSheet(friend: friend, games: challengeable, theme: theme),
    );
    if (game == null || !mounted) return;

    setState(() => _challenging = true);
    try {
      final invite = await GameService.instance.createGameInvite(
        game.id,
        sessionType: game.sessionType,
        payload: friendChallengePayloadFor(game),
        friendUserId: friend.id,
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GameInviteWaitingScreen(invite: invite, user: widget.user)),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Une erreur est survenue, réessaie.')));
    } finally {
      if (mounted) setState(() => _challenging = false);
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
          'Mes amis de jeu',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.block_rounded),
            tooltip: 'Personnes bloquées',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BlockedUsersScreen()),
            ),
          ),
        ],
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: Stack(
            children: [
              FutureBuilder<List<PublicProfile>>(
                future: _friendsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Center(child: CircularProgressIndicator(color: theme.primary));
                  }
                  if (snapshot.hasError) {
                    final message = snapshot.error is ApiException
                        ? (snapshot.error as ApiException).message
                        : 'Impossible de charger tes amis, réessaie.';
                    return RefreshIndicator(
                      color: theme.primary,
                      onRefresh: _refresh,
                      child: ListView(
                        children: [EmptyState(icon: Icons.error_outline_rounded, message: message)],
                      ),
                    );
                  }

                  final friends = snapshot.data!;
                  if (friends.isEmpty) {
                    return RefreshIndicator(
                      color: theme.primary,
                      onRefresh: _refresh,
                      child: ListView(
                        children: const [
                          EmptyState(
                            icon: Icons.people_outline_rounded,
                            message:
                                "Aucun ami de jeu pour l'instant. Défie quelqu'un avec son code, ça se remplit automatiquement dès que le défi est accepté.",
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
                      itemCount: friends.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final friend = friends[index];
                        return Material(
                          color: theme.surface.withValues(alpha: theme.isDark ? 0.5 : 0.75),
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: _challenging ? null : () => _challengeFriend(friend),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: theme.primary.withValues(alpha: 0.16),
                                    backgroundImage: (friend.avatar != null && friend.avatar!.isNotEmpty)
                                        ? CachedNetworkImageProvider(friend.avatar!)
                                        : null,
                                    child: (friend.avatar == null || friend.avatar!.isEmpty)
                                        ? Text(
                                            friend.prenom.isNotEmpty ? friend.prenom[0].toUpperCase() : '?',
                                            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.primary, fontSize: 16),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      friend.fullName,
                                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: theme.textOnBackground),
                                    ),
                                  ),
                                  Icon(Icons.sports_esports_rounded, color: theme.textOnBackgroundMuted, size: 20),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
              if (_challenging)
                Container(
                  color: Colors.black.withValues(alpha: 0.2),
                  child: Center(child: CircularProgressIndicator(color: theme.primary)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GamePickerSheet extends StatelessWidget {
  final PublicProfile friend;
  final List<Game> games;
  final ThemePalette theme;

  const _GamePickerSheet({required this.friend, required this.games, required this.theme});

  @override
  Widget build(BuildContext context) {
    final localeCode = LocaleScope.of(context).current.code;

    return SafeArea(
      child: ConstrainedBox(
        // Voir demande utilisateur : 7 jeux à lister, ça dépasse une
        // feuille "mi-écran" par défaut — bornée puis scrollable plutôt
        // que de déborder silencieusement en bas.
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Défier ${friend.fullName} à :',
                style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: theme.textOnBackground),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: games.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final game = games[index];
                    return Material(
                      color: theme.background,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.of(context).pop(game),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  game.nameFor(localeCode),
                                  style: GoogleFonts.nunito(fontWeight: FontWeight.w600, fontSize: 15, color: theme.textOnBackground),
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded, color: theme.textOnBackgroundMuted),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
