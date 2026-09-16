import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:showcaseview/showcaseview.dart';

import '../../../core/api_client.dart';
import '../../../l10n/locale_scope.dart';
import '../../../models/app_user.dart';
import '../../../models/game.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../../../theme/themed_background.dart';
import '../../box/box_scope.dart';
import '../game_guide_storage.dart';
import '../game_invite_waiting_screen.dart';
import '../game_service.dart';
import '../widgets/game_mode_info_sheet.dart';
import 'number_hunt_board_screen.dart';
import 'number_hunt_difficulty_screen.dart';
import 'number_hunt_nearby_connect_screen.dart';
import 'number_hunt_transport_local.dart';

enum NumberHuntMode { remote, nearby, local }

const _kNumberHuntGuideKey = 'number_hunt';

/// Démarre une partie (à distance ou pass-and-play) et pousse l'écran
/// correspondant — pas de palier de difficulté à choisir avant (grille
/// fixe de 100 cases, voir demande utilisateur), donc directement
/// déclenché depuis [NumberHuntModeScreen]. Fonction autonome pour rester
/// rappelable depuis [NumberHuntBoardScreen] lui-même pour "Rejouer" (voir
/// onRematch), même principe que startDotSquaresAndPush.
///
/// Mode à distance : passe par une INVITATION (voir GameInvite) — voir
/// startMemoryGameAndPush pour le détail du principe.
Future<void> startNumberHuntAndPush(
  BuildContext context, {
  required Game game,
  required AppUser user,
  required NumberHuntMode mode,
  required int cellCount,
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
    if (mode == NumberHuntMode.remote) {
      final invite = await GameService.instance.createGameInvite(
        game.id,
        sessionType: 'number_hunt',
        payload: {'cell_count': cellCount},
      );
      if (!context.mounted) return;
      final route = MaterialPageRoute<void>(builder: (_) => GameInviteWaitingScreen(invite: invite, user: user));
      if (replaceCurrent) {
        Navigator.of(context).pushReplacement(route);
      } else {
        Navigator.of(context).push(route);
      }
      return;
    }

    // Pass-and-play : aucun appel réseau, ni pour jouer ni pour le
    // résultat final (voir demande utilisateur : ce mode ne doit envoyer
    // aucune donnée de jeu au serveur/à la base de données) — voir
    // LocalNumberHuntTransport. `askWhoFound` capture le CONTEXTE DE
    // L'ÉCRAN DE PLATEAU (passé plus bas via un callback indirect) — voir
    // NumberHuntBoardScreen, qui fournit le vrai pop-up une fois monté.
    late final LocalNumberHuntTransport transport;
    transport = LocalNumberHuntTransport(
      creatorUserId: user.id,
      partnerUserId: partner.id,
      askWhoFound: () => NumberHuntBoardScreen.askWhoFoundFor(user.id, partner.id),
      cellCount: cellCount,
    );
    if (!context.mounted) return;

    final route = MaterialPageRoute<void>(
      builder: (_) => NumberHuntBoardScreen(
        game: game,
        user: user,
        transport: transport,
        playerNames: {user.id: user.prenom, partner.id: partner.prenom},
        playerAvatars: {user.id: user.avatar, partner.id: partner.avatar},
        onRematch: (ctx) => startNumberHuntAndPush(
          ctx,
          game: game,
          user: user,
          mode: mode,
          cellCount: cellCount,
          replaceCurrent: true,
        ),
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


/// Premier écran de "Chasse aux Chiffres" — choix du mode, même style que
/// les 3 autres jeux (copie structurelle conforme).
class NumberHuntModeScreen extends StatefulWidget {
  final Game game;
  final AppUser user;

  const NumberHuntModeScreen({super.key, required this.game, required this.user});

  @override
  State<NumberHuntModeScreen> createState() => _NumberHuntModeScreenState();
}

class _NumberHuntModeScreenState extends State<NumberHuntModeScreen> {
  bool get _nearbySupported => !kIsWeb && Platform.isAndroid;

  Map<String, int>? _economyRate;

  // Guide pas-à-pas (même principe que MemoryGameModeScreen) — une bulle
  // par tuile, automatique la première fois, rejouable via le "?".
  final _remoteTileKey = GlobalKey();
  final _nearbyTileKey = GlobalKey();
  final _localTileKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadEconomyRate();
    _maybeStartGuideAutomatically();
  }

  Future<void> _maybeStartGuideAutomatically() async {
    final seen = await GameGuideStorage.instance.hasSeen(widget.user.id, _kNumberHuntGuideKey);
    if (seen || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _startGuide());
  }

  void _startGuide() {
    ShowcaseView.get().startShowCase([_remoteTileKey, _nearbyTileKey, _localTileKey]);
    GameGuideStorage.instance.markSeen(widget.user.id, _kNumberHuntGuideKey);
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
    return '$base\n\nCe mode est facturé au temps de jeu : 1 Token équivaut à $minutesPerCoin minutes, '
        'soit environ ${_formatMinutes(15 * minutesPerCoin)} pour 15 Tokens.';
  }

  String get _nearbyInfoText {
    final rate = _economyRate;
    final cost = rate?['nearby_daily_coin_cost'] ?? 5;
    final days = rate?['nearby_free_trial_days'] ?? 0;
    final trial = days > 0 ? ' Les $days premiers jours de jeu sont offerts.' : '';
    return "Ce mode se joue sans connexion internet, en direct entre les deux téléphones (Bluetooth ou Wifi Direct). "
        "Pratique quand vous êtes ensemble mais sans réseau disponible. "
        "Il est facturé $cost Tokens une seule fois par jour. Une fois ce paiement fait, vous pouvez ensuite jouer à "
        "TOUS les jeux interactifs de l'application, autant de fois que vous voulez ce jour là, sans être facturé "
        "de nouveau.$trial";
  }

  static const String _localInfoText =
      "Ce mode se joue à tour de rôle sur un seul téléphone, sans connexion internet. Il est gratuit.";

  void _goToDifficulty(NumberHuntMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NumberHuntDifficultyScreen(game: widget.game, user: widget.user, mode: mode),
      ),
    );
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
        actions: [
          IconButton(icon: const Icon(Icons.help_outline_rounded), tooltip: 'Revoir le guide', onPressed: _startGuide),
        ],
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: ListView(
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
              Showcase(
                key: _remoteTileKey,
                title: 'Mode à distance',
                description:
                    "Joue en temps réel avec ton binôme, où qu'il ou elle soit. Vous pouvez aussi vous parler pendant la partie.",
                targetBorderRadius: BorderRadius.circular(20),
                child: _ModeTile(
                  theme: theme,
                  icon: Icons.wifi_rounded,
                  title: LocaleScope.t(context, 'memory_mode_remote_title'),
                  subtitle: LocaleScope.t(context, 'memory_mode_remote_subtitle'),
                  infoText: _remoteInfoText,
                  onTap: () => _goToDifficulty(NumberHuntMode.remote),
                ),
              ),
              const SizedBox(height: 14),
              Showcase(
                key: _nearbyTileKey,
                title: 'Mode présentiel connecté',
                description:
                    "Vous êtes ensemble, sans internet. Les deux téléphones se connectent directement en Bluetooth ou Wifi.",
                targetBorderRadius: BorderRadius.circular(20),
                child: _ModeTile(
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
                              builder: (_) => NumberHuntNearbyConnectScreen(game: widget.game, user: widget.user),
                            ),
                          )
                      : null,
                ),
              ),
              const SizedBox(height: 14),
              Showcase(
                key: _localTileKey,
                title: 'Mode présentiel, un seul téléphone',
                description: "Vous jouez à tour de rôle sur le même appareil, sans internet.",
                targetBorderRadius: BorderRadius.circular(20),
                child: _ModeTile(
                  theme: theme,
                  icon: Icons.phone_android_rounded,
                  title: LocaleScope.t(context, 'memory_mode_local_title'),
                  subtitle: LocaleScope.t(context, 'memory_mode_local_subtitle'),
                  infoText: _localInfoText,
                  onTap: () => _goToDifficulty(NumberHuntMode.local),
                ),
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
