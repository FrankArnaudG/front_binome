import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import 'game_service.dart';

/// Voir demande utilisateur (refonte de "Défier un ami") : "un btn voire
/// mon code d'amitier" — écran dédié, accessible à tout moment depuis la
/// liste d'amis, pour partager son propre code sans devoir d'abord choisir
/// ou ajouter quelqu'un. Affiche le dernier code connu tout de suite (voir
/// GameService.cachedFriendCode), rafraîchi juste après en arrière-plan.
class MyFriendCodeScreen extends StatefulWidget {
  const MyFriendCodeScreen({super.key});

  @override
  State<MyFriendCodeScreen> createState() => _MyFriendCodeScreenState();
}

class _MyFriendCodeScreenState extends State<MyFriendCodeScreen> {
  String? _code;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = await GameService.instance.cachedFriendCode();
    if (cached != null && mounted) setState(() => _code = cached);
    try {
      final code = await GameService.instance.fetchMyFriendCode();
      if (mounted) setState(() => _code = code);
    } catch (_) {
      // Best effort — garde le code déjà en cache affiché, sinon pas bloquant.
    }
  }

  void _copy(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copié')));
  }

  void _share(String code) {
    Share.share('Défie-moi à un jeu sur Binome Couple avec mon code ami : $code');
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final code = _code;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        title: Text("Mon code d'amitié", style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground)),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Partage ce code pour qu'un·e ami·e puisse te défier à un jeu, en dehors de ta Box.",
                  style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                ),
                const SizedBox(height: 28),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(18)),
                  child: code == null
                      ? Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: theme.primary),
                          ),
                        )
                      : Stack(
                          alignment: Alignment.center,
                          children: [
                            Text(
                              code,
                              style: GoogleFonts.poppins(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 6,
                                color: theme.textOnBackground,
                              ),
                            ),
                            Positioned(
                              right: 16,
                              child: GestureDetector(
                                onTap: () => _copy(code),
                                child: Icon(Icons.copy_rounded, size: 22, color: theme.textOnBackgroundMuted),
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: code == null ? null : () => _share(code),
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: const Text('Partager mon code'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
