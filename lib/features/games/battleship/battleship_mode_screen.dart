import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api_client.dart';
import '../../../l10n/locale_scope.dart';
import '../../../models/app_user.dart';
import '../../../models/game.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../../../theme/themed_background.dart';
import '../../box/box_scope.dart';
import '../game_invite_waiting_screen.dart';
import '../game_service.dart';
import 'battleship_nearby_connect_screen.dart';
import 'battleship_placement_screen.dart';
import 'battleship_transport.dart';
import 'battleship_transport_local.dart';

enum BattleshipMode { remote, nearby, local }

/// Démarre une partie (à distance ou pass-and-play) et pousse l'écran de
/// PLACEMENT (jamais directement le plateau de combat — les flottes ne
/// sont pas encore posées) — fonction autonome pour rester rappelable
/// pour "Rejouer" (voir onRematch dans BattleshipBoardScreen), même
/// principe que startWarCardAndPush.
///
/// Mode à distance : passe par une INVITATION (voir GameInvite).
Future<void> startBattleshipAndPush(
  BuildContext context, {
  required Game game,
  required AppUser user,
  required BattleshipMode mode,
  bool replaceCurrent = false,
}) async {
  final box = BoxScope.of(context).currentBox;
  final partner = box?.partnerOf(user.id);
  if (partner == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LocaleScope.t(context, 'memory_no_partner'))),
      );
    }
    return;
  }

  try {
    if (mode == BattleshipMode.remote) {
      final invite = await GameService.instance.createGameInvite(game.id, sessionType: 'battleship');
      if (!context.mounted) return;
      final route = MaterialPageRoute<void>(builder: (_) => GameInviteWaitingScreen(invite: invite, user: user));
      if (replaceCurrent) {
        Navigator.of(context).pushReplacement(route);
      } else {
        Navigator.of(context).push(route);
      }
      return;
    }

    // Pass-and-play : aucun appel réseau pour jouer, voir
    // LocalBattleshipTransport — chaque joueur place sa flotte à son
    // tour, un écran "passe le téléphone" entre les deux (voir
    // BattleshipPlacementScreen).
    final transport = LocalBattleshipTransport(creatorUserId: user.id, partnerUserId: partner.id);
    unawaited(_postLocalResultWhenFinished(game, transport));
    if (!context.mounted) return;

    final route = MaterialPageRoute<void>(
      builder: (_) => BattleshipPlacementScreen(
        game: game,
        user: user,
        transport: transport,
        playerNames: {user.id: user.prenom, partner.id: partner.prenom},
        playerAvatars: {user.id: user.avatar, partner.id: partner.avatar},
      ),
    );
    if (replaceCurrent) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).push(route);
    }
  } on ApiException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// Poste le résultat en fin de partie pass-and-play, en tâche de fond —
/// best-effort, même principe que les autres jeux.
Future<void> _postLocalResultWhenFinished(Game game, BattleshipTransport transport) async {
  await for (final state in transport.stateStream) {
    if (state.finished) {
      final duration = state.startedAt != null ? DateTime.now().difference(state.startedAt!).inSeconds : 0;
      try {
        await GameService.instance.recordBattleshipResult(
          game.id,
          movesCount: state.movesCount,
          durationSeconds: duration,
          winnerUserId: state.winnerUserId,
        );
      } catch (_) {
        // Best-effort.
      }
      break;
    }
  }
}

/// Premier écran de "Bataille Navale" — choix du mode, même style que les
/// autres jeux (copie structurelle conforme).
class BattleshipModeScreen extends StatefulWidget {
  final Game game;
  final AppUser user;

  const BattleshipModeScreen({super.key, required this.game, required this.user});

  @override
  State<BattleshipModeScreen> createState() => _BattleshipModeScreenState();
}

class _BattleshipModeScreenState extends State<BattleshipModeScreen> {
  bool _starting = false;

  bool get _nearbySupported => !kIsWeb && Platform.isAndroid;

  Future<void> _start(BattleshipMode mode) async {
    if (_starting) return;
    setState(() => _starting = true);
    await startBattleshipAndPush(context, game: widget.game, user: widget.user, mode: mode);
    if (mounted) setState(() => _starting = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final localeCode = LocaleScope.of(context).current.code;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text(
          widget.game.nameFor(localeCode),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: _starting
              ? Center(child: CircularProgressIndicator(color: theme.primary))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      LocaleScope.t(context, 'memory_mode_title'),
                      style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: theme.textOnBackground),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      LocaleScope.t(context, 'memory_mode_subtitle'),
                      style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                    ),
                    const SizedBox(height: 20),
                    _ModeTile(
                      theme: theme,
                      icon: Icons.wifi_rounded,
                      title: LocaleScope.t(context, 'memory_mode_remote_title'),
                      subtitle: LocaleScope.t(context, 'memory_mode_remote_subtitle'),
                      onTap: () => _start(BattleshipMode.remote),
                    ),
                    const SizedBox(height: 14),
                    _ModeTile(
                      theme: theme,
                      icon: Icons.bluetooth_rounded,
                      title: LocaleScope.t(context, 'memory_mode_nearby_title'),
                      subtitle: _nearbySupported
                          ? LocaleScope.t(context, 'memory_mode_nearby_subtitle')
                          : LocaleScope.t(context, 'memory_mode_nearby_unsupported'),
                      locked: !_nearbySupported,
                      onTap: _nearbySupported
                          ? () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => BattleshipNearbyConnectScreen(game: widget.game, user: widget.user),
                                ),
                              )
                          : null,
                    ),
                    const SizedBox(height: 14),
                    _ModeTile(
                      theme: theme,
                      icon: Icons.phone_android_rounded,
                      title: LocaleScope.t(context, 'memory_mode_local_title'),
                      subtitle: LocaleScope.t(context, 'memory_mode_local_subtitle'),
                      onTap: () => _start(BattleshipMode.local),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  final ThemePalette theme;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool locked;
  final VoidCallback? onTap;

  const _ModeTile({
    required this.theme,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.locked = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: locked ? 0.5 : 1,
      child: Material(
        color: theme.surface.withValues(alpha: theme.isDark ? 0.5 : 0.75),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [theme.primary, theme.secondary]),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: theme.textOnBackground),
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle, style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted)),
                    ],
                  ),
                ),
                if (!locked) Icon(Icons.chevron_right_rounded, color: theme.textOnBackgroundMuted, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
