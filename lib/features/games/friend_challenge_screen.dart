import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_client.dart';
import '../../models/app_user.dart';
import '../../models/game.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import 'game_invite_waiting_screen.dart';
import 'game_service.dart';
import 'memory_game/memory_emoji_pool.dart';

/// Nombre de paires par défaut pour un défi d'ami (voir demande
/// utilisateur : Phase 1 se limite au Jeu de Mémoire, sans sélecteur de
/// difficulté — cette valeur reprend la difficulté "moyenne" déjà proposée
/// dans MemoryGameDifficultyScreen).
const _kFriendChallengePairCount = 8;

/// Écran "Défier un ami" (voir demande utilisateur : permettre de jouer
/// ponctuellement avec quelqu'un hors de sa propre Box, via un code
/// personnel — principe "TikTok" : pas de liste d'amis à constituer avant,
/// l'amitié se crée automatiquement si le défi est accepté, voir
/// GameInviteController::accept côté backend). Phase 1 : uniquement le Jeu
/// de Mémoire, pas de sélecteur de jeu.
class FriendChallengeScreen extends StatefulWidget {
  final AppUser user;

  const FriendChallengeScreen({super.key, required this.user});

  @override
  State<FriendChallengeScreen> createState() => _FriendChallengeScreenState();
}

class _FriendChallengeScreenState extends State<FriendChallengeScreen> {
  final _codeController = TextEditingController();
  late Future<String> _myCodeFuture;
  bool _challenging = false;

  @override
  void initState() {
    super.initState();
    _myCodeFuture = GameService.instance.fetchMyFriendCode();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _shareCode(String code) {
    Share.share('Défie-moi à un jeu sur Binome avec mon code ami : $code');
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

    setState(() => _challenging = true);
    try {
      final games = await GameService.instance.fetchGames();
      Game? memoryGame;
      for (final g in games) {
        if (g.isMemoryGame) {
          memoryGame = g;
          break;
        }
      }
      if (memoryGame == null) {
        _showError('Jeu de Mémoire indisponible pour le moment.');
        return;
      }

      final board = generateShuffledMemoryBoard(_kFriendChallengePairCount);
      final invite = await GameService.instance.createGameInvite(
        memoryGame.id,
        sessionType: 'memory_game',
        payload: {'pair_count': _kFriendChallengePairCount, 'board': board},
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
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Joue une partie de Jeu de Mémoire avec quelqu\'un en dehors de ta Box, à l\'aide de son code ami.',
                style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
              ),
              const SizedBox(height: 28),
              Text(
                'Ton code ami :',
                style: GoogleFonts.nunito(fontSize: 14, color: theme.textOnBackgroundMuted),
              ),
              const SizedBox(height: 10),
              FutureBuilder<String>(
                future: _myCodeFuture,
                builder: (context, snapshot) {
                  final code = snapshot.data;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(14)),
                        alignment: Alignment.center,
                        child: code == null
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5),
                              )
                            : Text(
                                code,
                                style: GoogleFonts.poppins(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 6,
                                  color: theme.textOnBackground,
                                ),
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
                    : const Text('Défier au Jeu de Mémoire'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
