import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/game_invite_notifier.dart';
import '../../core/realtime_client.dart';
import '../../models/app_user.dart';
import '../../models/game_invite.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../box/box_scope.dart';
import '../box/box_service.dart';
import 'game_invite_navigation.dart';
import 'game_service.dart';

/// Écran d'attente affiché côté AUTEUR de l'invitation après le tap sur
/// "démarrer" en mode à distance — voir demande utilisateur : "pendant ce
/// temps dans l'écran A, le user a un truc qui l'informe en attente de
/// connexion". Se remplace lui-même par le plateau de jeu dès que le
/// binôme accepte (voir openGameSessionFromInvite), ou affiche un message
/// et revient en arrière s'il refuse/n'a pas répondu sous 60s.
class GameInviteWaitingScreen extends StatefulWidget {
  final GameInvite invite;
  final AppUser user;

  const GameInviteWaitingScreen({super.key, required this.invite, required this.user});

  @override
  State<GameInviteWaitingScreen> createState() => _GameInviteWaitingScreenState();
}

class _GameInviteWaitingScreenState extends State<GameInviteWaitingScreen> {
  static const _totalWait = Duration(seconds: 60);

  late StreamSubscription<GameInvite> _subscription;
  Timer? _tickTimer;
  Timer? _timeoutTimer;
  Timer? _pollTimer;
  DateTime? _startedAt;
  bool _resolved = false;

  // Présence en direct du binôme (canal de la Box, voir RealtimeClient) :
  // null = inconnue (pas encore reçue, ou invitation hors-Box), false = pas en
  // ligne → on l'écrit à l'écran pour que l'auteur le prévienne (voir
  // demande utilisateur).
  bool? _partnerOnline;
  String? _presenceBoxId;
  String? _partnerId;

  @override
  void initState() {
    super.initState();
    if (widget.invite.isFriendInvite) _loadFriendInvitee();
    _watchPartnerPresence();
    _startedAt = DateTime.now();
    _subscription = GameInviteNotifier.instance.watch(widget.invite.id).listen(_onUpdate);
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _timeoutTimer = Timer(_totalWait, _onTimeout);
    // Temps réel pour une confirmation instantanée, + un poll de secours en
    // parallèle (indépendant du socket, même principe que BoxWaitingScreen)
    // — sans ça, un événement WebSocket manqué (voir RealtimeClient, jamais
    // la seule source de vérité) laissait cet écran attendre jusqu'à
    // expiration des 60s puis annuler l'invitation MÊME QUAND le binôme
    // avait déjà rejoint et jouait de son côté (voir demande utilisateur).
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _pollStatus());
  }

  /// Écoute la présence du binôme sur le canal de sa Box (déjà utilisé ailleurs
  /// dans l'app, voir RealtimeClient.subscribeToBox) pour savoir s'il est en
  /// ligne. Rien pour une invitation hors-Box (défi à un ami de jeu) : pas de
  /// canal de présence commun, l'état reste inconnu et aucun message n'est
  /// affiché.
  void _watchPartnerPresence() {
    if (widget.invite.isFriendInvite) return;
    final box = BoxService.instance.currentBox;
    final partner = box?.partnerOf(widget.user.id);
    if (box == null || partner == null) return;
    _presenceBoxId = box.id;
    _partnerId = partner.id;
    unawaited(RealtimeClient.instance.subscribeToBox(
      box.id,
      onEvent: _ignoreEvent,
      onPresenceChange: _onPresenceChange,
    ));
  }

  void _ignoreEvent(RealtimeEvent event) {}

  void _onPresenceChange(Set<String> memberIds) {
    final partnerId = _partnerId;
    if (!mounted || partnerId == null) return;
    setState(() => _partnerOnline = memberIds.contains(partnerId));
  }

  Future<void> _pollStatus() async {
    if (_resolved) return;
    try {
      final invite = await GameService.instance.fetchGameInvite(widget.invite.id);
      _onUpdate(invite);
    } catch (_) {
      // best effort, on retente au prochain tick.
    }
  }

  void _onUpdate(GameInvite invite) {
    if (_resolved) return;
    if (invite.isAccepted) {
      _resolved = true;
      _openGame(invite);
    } else if (invite.isDeclined || invite.isExpired) {
      _resolved = true;
      _showOutcomeAndPop(invite.isExpired
          ? "Ton binôme n'a pas répondu à temps."
          : 'Ton binôme a décliné ton invitation.');
    }
  }

  // Chargé à part pour une invitation hors-Box (défi à un ami de jeu, voir
  // demande utilisateur) : l'invité·e n'est alors JAMAIS le binôme (voir
  // build(), qui reste synchrone pour le cas binôme existant).
  String? _friendInviteeName;
  String? _friendInviteeAvatar;

  Future<void> _loadFriendInvitee() async {
    try {
      final profile = await GameService.instance.fetchPublicProfile(widget.invite.inviteeId);
      if (!mounted) return;
      setState(() {
        _friendInviteeName = profile.prenom;
        _friendInviteeAvatar = profile.avatar;
      });
    } catch (_) {
      // Best-effort — repli sur le nom générique déjà géré dans build().
    }
  }

  Future<void> _onTimeout() async {
    if (_resolved) return;
    _resolved = true;
    try {
      await GameService.instance.cancelGameInvite(widget.invite.id);
    } catch (_) {
      // Best-effort — l'invitation sera de toute façon inutilisable côté
      // serveur une fois `expires_at` dépassé (voir GameInviteController).
    }
    _showOutcomeAndPop("Ton binôme n'a pas répondu à temps.");
  }

  Future<void> _openGame(GameInvite invite) async {
    if (!mounted) return;
    await openGameSessionFromInvite(context, invite, replaceCurrent: true);
  }

  void _showOutcomeAndPop(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).pop();
  }

  Future<void> _cancel() async {
    if (_resolved) return;
    _resolved = true;
    try {
      await GameService.instance.cancelGameInvite(widget.invite.id);
    } catch (_) {
      // Best-effort.
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _subscription.cancel();
    _tickTimer?.cancel();
    _timeoutTimer?.cancel();
    _pollTimer?.cancel();
    final presenceBoxId = _presenceBoxId;
    if (presenceBoxId != null) {
      RealtimeClient.instance.unsubscribeFromBox(
        presenceBoxId,
        onEvent: _ignoreEvent,
        onPresenceChange: _onPresenceChange,
      );
    }
    GameInviteNotifier.instance.disposeWatch(widget.invite.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final String name;
    final String? avatar;
    if (widget.invite.isFriendInvite) {
      name = _friendInviteeName ?? 'ton adversaire';
      avatar = _friendInviteeAvatar;
    } else {
      final box = BoxScope.of(context).currentBox;
      final partner = box?.partnerOf(widget.user.id);
      name = partner?.prenom ?? 'ton binôme';
      avatar = partner?.avatar;
    }

    final elapsed = _startedAt != null ? DateTime.now().difference(_startedAt!) : Duration.zero;
    final remaining = (_totalWait - elapsed).isNegative ? Duration.zero : _totalWait - elapsed;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: theme.background,
        body: ThemedBackground(
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 96,
                          height: 96,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: theme.primary.withValues(alpha: 0.4)),
                        ),
                        CircleAvatar(
                          radius: 38,
                          backgroundColor: theme.primary.withValues(alpha: 0.16),
                          backgroundImage: (avatar != null && avatar.isNotEmpty) ? NetworkImage(avatar) : null,
                          child: (avatar == null || avatar.isEmpty)
                              ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 24, color: theme.primary))
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'En attente de $name...',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: theme.textOnBackground),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Il/elle a ${remaining.inSeconds}s pour rejoindre la partie.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                    ),
                    // Le binôme n'est pas connecté : l'invitation ne lui sera
                    // vue qu'à l'ouverture de l'app (voir demande utilisateur).
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      alignment: Alignment.topCenter,
                      child: _partnerOnline == false
                          ? Padding(
                              padding: const EdgeInsets.only(top: 18),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: theme.primary.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: theme.primary.withValues(alpha: 0.25)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.wifi_off_rounded, size: 18, color: theme.primary),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "Ton binôme n'est pas en ligne.",
                                            style: GoogleFonts.nunito(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              color: theme.textOnBackground,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            "Demande-lui de se connecter à l'application pour qu'il/elle voie ton invitation.",
                                            style: GoogleFonts.nunito(
                                              fontSize: 12.5,
                                              height: 1.35,
                                              color: theme.textOnBackgroundMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    const SizedBox(height: 28),
                    OutlinedButton(
                      onPressed: _cancel,
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12)),
                      child: const Text('Annuler'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
