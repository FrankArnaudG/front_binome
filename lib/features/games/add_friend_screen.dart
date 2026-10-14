import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../models/app_user.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import 'friend_challenge_support.dart';
import 'game_invite_waiting_screen.dart';
import 'game_service.dart';
import 'widgets/game_picker_sheet.dart';

/// Voir demande utilisateur (refonte de "Défier un ami") : "+ ajouter un
/// ami" — défier quelqu'un de NOUVEAU via son code personnel, plutôt que de
/// ressaisir un code sur l'écran principal à chaque fois. L'amitié se crée
/// automatiquement dès que le défi est accepté (voir
/// GameInviteController::accept côté backend), jamais de demande d'ami
/// explicite — cette personne apparaîtra ensuite dans la liste.
class AddFriendScreen extends StatefulWidget {
  final AppUser user;

  const AddFriendScreen({super.key, required this.user});

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen> {
  final _codeController = TextEditingController();
  bool _challenging = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _continue() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      _showError("Entre le code ami de la personne que tu veux défier.");
      return;
    }

    setState(() => _challenging = true);
    try {
      final games = await GameService.instance.fetchGames();
      final challengeable = friendChallengeableGames(games);
      if (!mounted) return;
      if (challengeable.isEmpty) {
        _showError('Aucun jeu disponible pour le moment.');
        return;
      }

      final theme = ThemeScope.paletteOf(context);
      final game = await showGamePickerSheet(
        context: context,
        opponentLabel: 'ton ami',
        games: challengeable,
        theme: theme,
      );
      if (game == null || !mounted) return;

      // Facturé au temps réellement joué une fois la partie acceptée (voir BillGameSessions côté
      // serveur), comme dans la Box — pas de coût connu à l'avance à annoncer ici.
      final invite = await GameService.instance.createGameInvite(
        game.id,
        sessionType: game.sessionType,
        payload: friendChallengePayloadFor(game),
        friendCode: code,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
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
        title: Text('Ajouter un ami', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground)),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Entre le code ami d'un·e ami·e pour le/la défier à un jeu. Il/elle rejoindra ta liste d'amis dès que le défi sera accepté.",
                  style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                ),
                const SizedBox(height: 24),
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
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _challenging ? null : _continue,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _challenging
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Text('Continuer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
