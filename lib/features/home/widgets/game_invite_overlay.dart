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
      'battleship' => 'Bataille Navale',
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
        // Le binôme vient de taper sur "Rejoindre" : la pop-up a disparu, la
        // partie se prépare — on l'indique plutôt que de laisser l'écran figé.
        if (GameInviteNotifier.instance.isJoining) return const _JoiningLoader();
        final invite = GameInviteNotifier.instance.pendingInvite;
        if (invite == null) return const SizedBox.shrink();
        return _GameInviteCard(key: ValueKey(invite.id), invite: invite);
      },
    );
  }
}

/// Voile plein écran avec un chargement, affiché entre le tap sur "Rejoindre"
/// et l'ouverture de l'écran de jeu (voir GameInviteNotifier.isJoining).
/// Bloque les taps : pas de double action pendant l'ouverture.
class _JoiningLoader extends StatelessWidget {
  const _JoiningLoader();

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    return Positioned.fill(
      child: AbsorbPointer(
        child: Material(
          color: Colors.black.withValues(alpha: 0.45),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 8)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(strokeWidth: 3, color: theme.primary),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Ouverture de la partie…',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14, color: theme.textOnBackground),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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

  // Chargé à part pour une invitation hors-Box (défi à un ami de jeu, voir
  // demande utilisateur) : l'expéditeur n'est alors JAMAIS un membre de MA
  // Box (voir build(), qui reste synchrone pour le cas binôme existant).
  String? _friendInviterName;
  String? _friendInviterAvatar;

  @override
  void initState() {
    super.initState();
    if (widget.invite.isFriendInvite) _loadFriendInviter();
  }

  Future<void> _loadFriendInviter() async {
    try {
      final profile = await GameService.instance.fetchPublicProfile(widget.invite.inviterId);
      if (!mounted) return;
      setState(() {
        _friendInviterName = profile.prenom;
        _friendInviterAvatar = profile.avatar;
      });
    } catch (_) {
      // Best-effort — repli sur le nom générique déjà géré dans build().
    }
  }

  /// Bloque l'expéditeur (voir demande utilisateur : plus jamais reçu ses
  /// invitations ensuite) puis efface la pop-up comme un refus.
  Future<void> _block() async {
    if (_responding) return;
    setState(() => _responding = true);
    GameInviteNotifier.instance.dismissPendingInvite();
    try {
      await GameService.instance.blockUser(widget.invite.inviterId);
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> _respond(bool accept) async {
    if (_responding) return;
    setState(() => _responding = true);

    // "Rejoindre" : le chargement s'allume AVANT que la pop-up disparaisse
    // (pas de flash sans rien) et reste jusqu'à l'ouverture de l'écran de jeu.
    if (accept) GameInviteNotifier.instance.setJoining(true);

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
      // L'auteur verra de toute façon l'expiration au bout de 60s si rien
      // n'aboutit (voir GameInviteWaitingScreen). Côté invité·e, on le dit
      // plutôt que de laisser croire que rien ne s'est passé.
      if (accept) {
        final context = AppRouter.navigatorKey.currentContext;
        if (context != null && context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text("Impossible de rejoindre la partie. Réessaie dans un instant.")),
          );
        }
      }
    } finally {
      if (accept) GameInviteNotifier.instance.setJoining(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final String name;
    final String? avatar;
    if (widget.invite.isFriendInvite) {
      name = _friendInviterName ?? LocaleScope.t(context, 'memory_board_partner_fallback');
      avatar = _friendInviterAvatar;
    } else {
      final box = BoxScope.of(context).currentBox;
      final inviter = box?.creatorId == widget.invite.inviterId ? box?.creator : box?.partner;
      name = inviter?.prenom ?? LocaleScope.t(context, 'memory_board_partner_fallback');
      avatar = inviter?.avatar;
    }

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
                // Uniquement pour un défi d'ami de jeu — jamais pour son
                // propre binôme (voir demande utilisateur).
                if (widget.invite.isFriendInvite) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _responding ? null : _block,
                    style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                    child: const Text('Bloquer cette personne'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
