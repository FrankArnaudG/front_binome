import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../core/usage_service.dart';
import '../../models/app_user.dart';
import '../../models/public_profile.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/empty_state.dart';
import 'add_friend_screen.dart';
import 'blocked_users_screen.dart';
import 'friend_challenge_support.dart';
import 'friend_difficulty_screen.dart';
import 'friends_cache.dart';
import 'game_invite_waiting_screen.dart';
import 'game_service.dart';
import 'my_friend_code_screen.dart';
import 'widgets/game_picker_sheet.dart';

/// Écran "Défier un ami" (voir demande utilisateur : jouer ponctuellement
/// avec quelqu'un hors de sa propre Box, via un code personnel — l'amitié
/// se crée automatiquement si le défi est accepté, voir
/// GameInviteController::accept côté backend).
///
/// Voir demande utilisateur (refonte) : "proposer d'abord directement de
/// choisir un·e ami·e à défier" — la liste d'amis déjà connus (ex-
/// FriendsListScreen, fusionnée ici) est donc le contenu PRINCIPAL de cet
/// écran, "Ajouter un ami" et "Voir mon code d'amitié" restant toujours
/// accessibles en haut, quel que soit l'état de la liste (y compris vide).
class FriendChallengeScreen extends StatefulWidget {
  final AppUser user;

  const FriendChallengeScreen({super.key, required this.user});

  @override
  State<FriendChallengeScreen> createState() => _FriendChallengeScreenState();
}

class _FriendChallengeScreenState extends State<FriendChallengeScreen> {
  List<PublicProfile>? _friends;
  bool _loadError = false;
  bool _challenging = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Affiche d'abord la dernière liste connue (voir FriendsCache — permet
  /// aussi de choisir un ami pour un défi Bluetooth sans connexion), puis
  /// rafraîchit en arrière-plan, comme le reste de l'app (code ami, jeux).
  Future<void> _load() async {
    if (_friends == null) {
      final cached = await FriendsCache.read();
      if (cached.isNotEmpty && mounted) setState(() => _friends = cached);
    }
    try {
      final friends = await GameService.instance.fetchFriends();
      unawaited(FriendsCache.save(friends));
      if (!mounted) return;
      setState(() {
        _friends = friends;
        _loadError = false;
      });
    } catch (_) {
      // Best effort — garde la liste déjà en cache affichée ; signale
      // l'erreur seulement si on n'a vraiment rien à montrer.
      if (mounted && _friends == null) setState(() => _loadError = true);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openAddFriend() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AddFriendScreen(user: widget.user)),
    );
  }

  void _openMyCode() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MyFriendCodeScreen()),
    );
  }

  Future<void> _challengeFriend(PublicProfile friend) async {
    final theme = ThemeScope.paletteOf(context);
    // Voir demande utilisateur : "en cliquant sur le nom, mette un loader et
    // sassurer que lon ne puisse plu cliquer" — avant ce correctif, le
    // loader/verrou (_challenging) n'apparaissait qu'au moment d'envoyer le
    // défi, pas dès le tap : le premier appel réseau (fetchGames) et le
    // choix du jeu/niveau pouvaient donc être déclenchés en double. Posé
    // dès l'entrée, retiré dans le `finally` qui couvre toute la méthode.
    setState(() => _challenging = true);
    try {
      final games = await GameService.instance.fetchGames();
      final challengeable = friendChallengeableGames(games);
      if (!mounted || challengeable.isEmpty) return;

      final game = await showGamePickerSheet(
        context: context,
        opponentLabel: friend.fullName,
        games: challengeable,
        theme: theme,
      );
      if (game == null || !mounted) return;

      // Voir diagnostic utilisateur : jamais loggé jusqu'ici pour un défi
      // d'ami, contrairement au flux binôme (voir GamesMenuScreen._playGame)
      // — "fonctionnalité la plus utilisée" doit aussi compter ces parties.
      UsageService.instance.logFeature('game', detail: game.sessionType);

      // Voir diagnostic utilisateur (phase 2) : choix de la difficulté avant
      // d'envoyer le défi, pour les 6 jeux qui ont ce concept (tous sauf
      // Morpion) — comme avec le binôme, au lieu d'une valeur fixe imposée.
      if (gameHasDifficultyChoice(game)) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FriendDifficultyScreen(
              game: game,
              user: widget.user,
              opponentLabel: friend.fullName,
              friendUserId: friend.id,
            ),
          ),
        );
        return;
      }

      // Facturé au temps réellement joué une fois la partie acceptée (voir BillGameSessions côté
      // serveur), comme dans la Box — pas de coût connu à l'avance à annoncer ici.
      final invite = await GameService.instance.createGameInvite(
        game.id,
        sessionType: game.sessionType,
        friendUserId: friend.id,
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GameInviteWaitingScreen(invite: invite, user: widget.user)),
      );
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Une erreur est survenue, réessaie.');
    } finally {
      if (mounted) setState(() => _challenging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final friends = _friends;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text('Défier un ami', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground)),
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
              RefreshIndicator(
                color: theme.primary,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Voir demande utilisateur : "a tout moment ya un btn
                    // ajouter ami en haut et clairement écrit. et un btn
                    // voire mon code d'amitier" — toujours visibles, quel
                    // que soit l'état de la liste ci-dessous.
                    FilledButton.icon(
                      onPressed: _openAddFriend,
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                      label: const Text('Ajouter un ami'),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _openMyCode,
                      icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                      label: const Text("Voir mon code d'amitié"),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Mes amis de jeu',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: theme.textOnBackground),
                    ),
                    const SizedBox(height: 12),
                    if (friends == null && !_loadError)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: CircularProgressIndicator(color: theme.primary)),
                      )
                    else if (friends == null && _loadError)
                      EmptyState(
                        icon: Icons.error_outline_rounded,
                        message: 'Impossible de charger tes amis, réessaie.',
                        actionLabel: 'Réessayer',
                        onAction: _load,
                      )
                    else if (friends!.isEmpty)
                      // Voir demande utilisateur : "si la liste est vide on
                      // met un message pour le dire".
                      EmptyState(
                        icon: Icons.people_outline_rounded,
                        message: "Aucun ami de jeu pour l'instant. Ajoute-en un avec son code pour commencer à jouer ensemble.",
                        actionLabel: 'Ajouter un ami',
                        onAction: _openAddFriend,
                      )
                    else
                      ...friends.map(
                        (friend) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
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
                          ),
                        ),
                      ),
                  ],
                ),
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
