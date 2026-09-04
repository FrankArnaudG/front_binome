import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/app_router.dart';
import '../../../core/game_invite_notifier.dart';
import '../../../l10n/locale_scope.dart';
import '../../../models/game_invite.dart';
import '../../../theme/theme_scope.dart';
import '../../box/box_scope.dart';
import '../../games/game_invite_navigation.dart';
import '../../games/game_service.dart';

/// Nom affiché pour un `session_type` — pas besoin d'aller chercher le
/// [Game] complet juste pour ça (voir demande utilisateur : le pop-up doit
/// apparaître tout de suite, sans latence réseau supplémentaire).
String _gameLabel(String sessionType) => switch (sessionType) {
      'memory_game' => 'Jeu de Mémoire',
      'tic_tac_toe' => 'Morpion à Deux',
      'dot_squares' => 'Le Jeu des Carrés',
      'number_hunt' => 'Chasse aux Chiffres',
      'war_card' => 'Bataille',
      'connect_four' => 'Puissance 4',
      'battleship' => 'Bataille Navale',
      'pictionary' => 'Pictionary à Deux',
      _ => 'un jeu',
    };

/// Pop-up d'invitation à une partie — flotte au-dessus de N'IMPORTE QUEL
/// écran (montée dans AppShell, comme GameCardBubble), apparaît dès que
/// [GameInviteNotifier.pendingInvite] est renseigné (voir demande
/// utilisateur : "peu importe où ils sont dans l'app... il y a un pop-up
/// mignon qui apparaît et le user peut accepter... ou refuser").
class GameInviteOverlay extends StatelessWidget {
  const GameInviteOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: GameInviteNotifier.instance,
      builder: (context, _) {
        final invite = GameInviteNotifier.instance.pendingInvite;
        if (invite == null) return const SizedBox.shrink();
        return _GameInviteCard(key: ValueKey(invite.id), invite: invite);
      },
    );
  }
}

class _GameInviteCard extends StatefulWidget {
  final GameInvite invite;

  const _GameInviteCard({super.key, required this.invite});

  @override
  State<_GameInviteCard> createState() => _GameInviteCardState();
}

class _GameInviteCardState extends State<_GameInviteCard> {
  bool _responding = false;

  Future<void> _respond(bool accept) async {
    if (_responding) return;
    setState(() => _responding = true);

    // Efface le pop-up tout de suite plutôt que d'attendre l'aller-retour
    // réseau (voir GameInviteNotifier.dismissPendingInvite).
    GameInviteNotifier.instance.dismissPendingInvite();

    try {
      if (accept) {
        final resolved = await GameService.instance.acceptGameInvite(widget.invite.id);
        final navContext = AppRouter.navigatorKey.currentContext;
        if (navContext != null && navContext.mounted) {
          await openGameSessionFromInvite(navContext, resolved);
        }
      } else {
        await GameService.instance.declineGameInvite(widget.invite.id);
      }
    } catch (_) {
      // Best-effort — l'auteur verra de toute façon l'expiration au bout
      // de 60s si rien n'aboutit (voir GameInviteWaitingScreen).
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final box = BoxScope.of(context).currentBox;
    final inviter = box?.creatorId == widget.invite.inviterId ? box?.creator : box?.partner;
    final name = inviter?.prenom ?? LocaleScope.t(context, 'memory_board_partner_fallback');
    final avatar = inviter?.avatar;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: AnimatedScale(
          scale: 1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 20, offset: const Offset(0, 8)),
              ],
              border: Border.all(color: theme.primary.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: theme.primary.withValues(alpha: 0.16),
                      backgroundImage: (avatar != null && avatar.isNotEmpty) ? NetworkImage(avatar) : null,
                      child: (avatar == null || avatar.isEmpty)
                          ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.primary))
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$name te propose de jouer 🎮',
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: theme.textOnBackground),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _gameLabel(widget.invite.sessionType),
                            style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _responding ? null : () => _respond(false),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                        child: const Text('Refuser'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _responding ? null : () => _respond(true),
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                        child: _responding
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Rejoindre'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
