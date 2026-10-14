import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_client.dart';
import '../../l10n/locale_scope.dart';
import '../../models/app_user.dart';
import '../../models/game.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import 'friend_challenge_support.dart';
import 'friends_list_screen.dart';
import 'game_invite_waiting_screen.dart';
import 'game_service.dart';

/// Écran "Défier un ami" (voir demande utilisateur : permettre de jouer
/// ponctuellement avec quelqu'un hors de sa propre Box, via un code
/// personnel — principe "TikTok" : pas de liste d'amis à constituer avant,
/// l'amitié se crée automatiquement si le défi est accepté, voir
/// GameInviteController::accept côté backend). Les 7 jeux temps réel sont
/// proposés au choix (voir demande utilisateur — la Phase 1 d'origine se
/// limitait au Jeu de Mémoire, le backend supporte désormais les 7).
class FriendChallengeScreen extends StatefulWidget {
  final AppUser user;

  const FriendChallengeScreen({super.key, required this.user});

  @override
  State<FriendChallengeScreen> createState() => _FriendChallengeScreenState();
}

class _FriendChallengeScreenState extends State<FriendChallengeScreen> {
  final _codeController = TextEditingController();
  // Voir demande utilisateur : "à chaque fois que j'ouvre ici ça charge" —
  // le code ami ne change jamais une fois généré, et le catalogue de jeux
  // change rarement : on affiche d'abord le dernier état connu (voir
  // LocalCache côté GameService), avant même la réponse réseau, comme
  // GameDiscussionsScreen._loadCachedThenRefresh pour le même catalogue.
  String? _myCode;
  List<Game>? _challengeableGames;
  Game? _selectedGame;
  bool _challenging = false;

  @override
  void initState() {
    super.initState();
    _loadMyCode();
    _loadGames();
  }

  Future<void> _loadMyCode() async {
    final cached = await GameService.instance.cachedFriendCode();
    if (cached != null && mounted) setState(() => _myCode = cached);
    try {
      final code = await GameService.instance.fetchMyFriendCode();
      if (mounted) setState(() => _myCode = code);
    } catch (_) {
      // Best effort — garde le code déjà en cache affiché, sinon pas bloquant.
    }
  }

  void _applyGames(List<Game> games) {
    final challengeable = friendChallengeableGames(games);
    setState(() {
      _challengeableGames = challengeable;
      // Le Jeu de Mémoire reste sélectionné par défaut — comportement
      // historique de cet écran, avant l'ajout du sélecteur.
      _selectedGame ??= challengeable.isNotEmpty
          ? challengeable.firstWhere((g) => g.isMemoryGame, orElse: () => challengeable.first)
          : null;
    });
  }

  Future<void> _loadGames() async {
    final cached = await GameService.instance.cachedGames();
    if (cached != null && mounted) _applyGames(cached);
    try {
      final games = await GameService.instance.fetchGames();
      if (mounted) _applyGames(games);
    } catch (_) {
      // Best effort — garde le catalogue déjà en cache affiché, sinon pas bloquant.
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _shareCode(String code) {
    Share.share('Défie-moi à un jeu sur Binome Couple avec mon code ami : $code');
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copié')));
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _challenge() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      _showError("Entre le code ami de la personne que tu veux défier.");
      return;
    }
    final game = _selectedGame;
    if (game == null) {
      _showError('Choisis un jeu.');
      return;
    }

    // Facturé au temps réellement joué une fois la partie acceptée (voir BillGameSessions côté
    // serveur), comme dans la Box — pas de coût connu à l'avance à annoncer ici (voir demande
    // utilisateur : "à distance c'est facturé en fonction du temps de jeu, comme dans la Box").
    setState(() => _challenging = true);
    try {
      final invite = await GameService.instance.createGameInvite(
        game.id,
        sessionType: game.sessionType,
        payload: friendChallengePayloadFor(game),
        friendCode: code,
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

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(
          'Défier un ami',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_outline_rounded),
            tooltip: 'Mes amis de jeu',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => FriendsListScreen(user: widget.user)),
            ),
          ),
        ],
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Joue une partie avec quelqu\'un en dehors de ta Box, à l\'aide de son code ami.',
                style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
              ),
              const SizedBox(height: 28),
              Text(
                'Ton code ami :',
                style: GoogleFonts.nunito(fontSize: 14, color: theme.textOnBackgroundMuted),
              ),
              const SizedBox(height: 10),
              Builder(
                builder: (context) {
                  final code = _myCode;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(14)),
                        child: code == null
                            ? const Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.5),
                                ),
                              )
                            : Stack(
                                alignment: Alignment.center,
                                children: [
                                  Text(
                                    code,
                                    style: GoogleFonts.poppins(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 6,
                                      color: theme.textOnBackground,
                                    ),
                                  ),
                                  Positioned(
                                    right: 12,
                                    child: GestureDetector(
                                      onTap: () => _copyCode(code),
                                      child: Icon(Icons.copy_rounded, size: 20, color: theme.textOnBackgroundMuted),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: code == null ? null : () => _shareCode(code),
                        icon: const Icon(Icons.ios_share_rounded, size: 18),
                        label: const Text('Partager mon code'),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(child: Divider(color: theme.textOnBackgroundMuted.withValues(alpha: 0.4))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('OU', style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted)),
                  ),
                  Expanded(child: Divider(color: theme.textOnBackgroundMuted.withValues(alpha: 0.4))),
                ],
              ),
              const SizedBox(height: 28),
              Text(
                'Jeu :',
                style: GoogleFonts.nunito(fontSize: 14, color: theme.textOnBackgroundMuted),
              ),
              const SizedBox(height: 10),
              Builder(
                builder: (context) {
                  final games = _challengeableGames;
                  if (games == null) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))),
                    );
                  }
                  final localeCode = LocaleScope.of(context).current.code;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final game in games)
                        ChoiceChip(
                          label: Text(game.nameFor(localeCode)),
                          selected: _selectedGame?.id == game.id,
                          onSelected: (_) => setState(() => _selectedGame = game),
                          labelStyle: GoogleFonts.nunito(
                            fontWeight: FontWeight.w600,
                            color: _selectedGame?.id == game.id ? Colors.white : theme.textOnBackground,
                          ),
                          selectedColor: theme.primary,
                          backgroundColor: theme.surface,
                          side: BorderSide.none,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 28),
              Text(
                "Entre le code ami d'un·e ami·e pour le/la défier :",
                style: GoogleFonts.nunito(fontSize: 14, color: theme.textOnBackgroundMuted),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _codeController,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 4),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'XXXXXX',
                  filled: true,
                  fillColor: theme.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _challenging ? null : _challenge,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: _challenging
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : Text(_selectedGame != null ? 'Défier au ${_selectedGame!.nameFor(LocaleScope.of(context).current.code)}' : 'Défier'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
