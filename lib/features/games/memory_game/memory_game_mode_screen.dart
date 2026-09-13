import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/locale_scope.dart';
import '../../../models/app_user.dart';
import '../../../models/game.dart';
import '../../../theme/theme_palette.dart';
import '../../../theme/theme_scope.dart';
import '../../../theme/themed_background.dart';
import '../widgets/remote_billing_info.dart';
import 'memory_game_difficulty_screen.dart';
import 'memory_game_nearby_connect_screen.dart';

enum MemoryGameMode { remote, nearby, local }

/// Premier écran de "Jeu de Mémoire" — choix du mode avant même la
/// difficulté (voir demande utilisateur : les trois options doivent être
/// affichées avant de commencer). Style visuel repris de
/// CharadesCategoriesScreen (seul écran existant proche d'un "choix avant
/// de lancer une session").
class MemoryGameModeScreen extends StatelessWidget {
  final Game game;
  final AppUser user;

  const MemoryGameModeScreen({super.key, required this.game, required this.user});

  bool get _nearbySupported => !kIsWeb && Platform.isAndroid;

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
          game.nameFor(localeCode),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
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
              _ModeTile(
                theme: theme,
                icon: Icons.wifi_rounded,
                title: LocaleScope.t(context, 'memory_mode_remote_title'),
                subtitle: LocaleScope.t(context, 'memory_mode_remote_subtitle'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MemoryGameDifficultyScreen(game: game, user: user, mode: MemoryGameMode.remote),
                  ),
                ),
              ),
              RemoteBillingInfo(theme: theme),
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
                          MaterialPageRoute(builder: (_) => MemoryGameNearbyConnectScreen(game: game, user: user)),
                        )
                    : null,
              ),
              const SizedBox(height: 14),
              _ModeTile(
                theme: theme,
                icon: Icons.phone_android_rounded,
                title: LocaleScope.t(context, 'memory_mode_local_title'),
                subtitle: LocaleScope.t(context, 'memory_mode_local_subtitle'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MemoryGameDifficultyScreen(game: game, user: user, mode: MemoryGameMode.local),
                  ),
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
