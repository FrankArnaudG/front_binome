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
import '../widgets/game_mode_info_sheet.dart';
import 'tic_tac_toe_board_screen.dart';
import 'tic_tac_toe_nearby_connect_screen.dart';
import 'tic_tac_toe_transport.dart';
import 'tic_tac_toe_transport_local.dart';

enum TicTacToeMode { remote, nearby, local }

/// Démarre une partie (à distance ou pass-and-play) et pousse l'écran
/// correspondant — pas de palier de difficulté à choisir avant
/// (contrairement au Jeu de Mémoire), donc directement déclenché depuis
/// [TicTacToeModeScreen] plutôt que depuis un écran intermédiaire.
/// Fonction autonome pour rester rappelable depuis [TicTacToeBoardScreen]
/// lui-même pour "Rejouer" (voir onRematch), même principe que
/// startMemoryGameAndPush.
///
/// Mode à distance : passe désormais par une INVITATION (voir GameInvite)
/// — voir startMemoryGameAndPush pour le détail du principe.
Future<void> startTicTacToeAndPush(
  BuildContext context, {
  required Game game,
  required AppUser user,
  required TicTacToeMode mode,
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
    if (mode == TicTacToeMode.remote) {
      final invite = await GameService.instance.createGameInvite(game.id, sessionType: 'tic_tac_toe');
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
    // LocalTicTacToeTransport.
    final transport = LocalTicTacToeTransport(myUserId: user.id, partnerUserId: partner.id);
    unawaited(_postLocalResultWhenFinished(game, transport));
    if (!context.mounted) return;

    final route = MaterialPageRoute<void>(
      builder: (_) => TicTacToeBoardScreen(
        game: game,
        user: user,
        transport: transport,
        playerNames: {user.id: user.prenom, partner.id: partner.prenom},
        playerAvatars: {user.id: user.avatar, partner.id: partner.avatar},
        onRematch: (ctx) => startTicTacToeAndPush(ctx, game: game, user: user, mode: mode, replaceCurrent: true),
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
/// best-effort, même principe que _postLocalResultWhenFinished côté Jeu de
/// Mémoire.
Future<void> _postLocalResultWhenFinished(Game game, TicTacToeTransport transport) async {
  await for (final state in transport.stateStream) {
    if (state.finished) {
      final duration = state.startedAt != null ? DateTime.now().difference(state.startedAt!).inSeconds : 0;
      try {
        await GameService.instance.recordTicTacToeResult(
          game.id,
          movesCount: state.movesCount,
          durationSeconds: duration,
          winnerUserId: state.winnerUserId,
          isDraw: state.isDraw,
        );
      } catch (_) {
        // Best-effort.
      }
      break;
    }
  }
}

/// Premier écran de "Morpion à Deux" — choix du mode, même style que
/// MemoryGameModeScreen (copie structurelle conforme).
class TicTacToeModeScreen extends StatefulWidget {
  final Game game;
  final AppUser user;

  const TicTacToeModeScreen({super.key, required this.game, required this.user});

  @override
  State<TicTacToeModeScreen> createState() => _TicTacToeModeScreenState();
}

class _TicTacToeModeScreenState extends State<TicTacToeModeScreen> {
  bool _starting = false;

  bool get _nearbySupported => !kIsWeb && Platform.isAndroid;

  Map<String, int>? _economyRate;

  @override
  void initState() {
    super.initState();
    _loadEconomyRate();
  }

  Future<void> _loadEconomyRate() async {
    try {
      final rate = await GameService.instance.fetchGameEconomyRate();
      if (mounted) setState(() => _economyRate = rate);
    } catch (_) {
      // Best-effort — l'écran reste utilisable sans ce détail.
    }
  }

  String _formatMinutes(int totalMinutes) {
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours <= 0) return '${minutes}min';
    if (minutes == 0) return '${hours}h';
    return '${hours}h${minutes.toString().padLeft(2, '0')}';
  }

  String get _remoteInfoText {
    final rate = _economyRate;
    const base =
        "Jouez en temps réel avec votre binôme, où qu'il ou elle soit dans le monde. Vous pouvez aussi communiquer par message, audio ou vidéo pendant la partie.";
    if (rate == null) return base;
    final minutesPerCoin = rate['minutes_per_coin'] ?? 8;
    return '$base\n\nCe mode est facturé au temps de jeu : 1 pièce équivaut à $minutesPerCoin minutes, '
        'soit environ ${_formatMinutes(15 * minutesPerCoin)} pour 15 pièces.';
  }

  String get _nearbyInfoText {
    final rate = _economyRate;
    final cost = rate?['nearby_daily_coin_cost'] ?? 5;
    final days = rate?['nearby_free_trial_days'] ?? 0;
    final trial = days > 0 ? ' Les $days premiers jours de jeu sont offerts.' : '';
    return "Ce mode se joue sans connexion internet, en direct entre les deux téléphones (Bluetooth ou Wifi Direct). "
        "Pratique quand vous êtes ensemble mais sans réseau disponible. "
        "Il est facturé $cost pièces une seule fois par jour. Une fois ce paiement fait, vous pouvez ensuite jouer à "
        "TOUS les jeux interactifs de l'application, autant de fois que vous voulez ce jour là, sans être facturé "
        "de nouveau.$trial";
  }

  static const String _localInfoText =
      "Ce mode se joue à tour de rôle sur un seul téléphone, sans connexion internet. Il est gratuit.";

  Future<void> _start(TicTacToeMode mode) async {
    if (_starting) return;
    setState(() => _starting = true);
    await startTicTacToeAndPush(context, game: widget.game, user: widget.user, mode: mode);
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
                      infoText: _remoteInfoText,
                      onTap: () => _start(TicTacToeMode.remote),
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
                      infoText: _nearbyInfoText,
                      onTap: _nearbySupported
                          ? () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => TicTacToeNearbyConnectScreen(game: widget.game, user: widget.user),
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
                      infoText: _localInfoText,
                      onTap: () => _start(TicTacToeMode.local),
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
  final String? infoText;
  final VoidCallback? onTap;

  const _ModeTile({
    required this.theme,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.locked = false,
    this.infoText,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Opacity(
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
        ),
        if (infoText != null) GameModeInfoIcon(theme: theme, title: 'Mode $title', text: infoText!),
      ],
    );
  }
}
