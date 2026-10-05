import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/game.dart';
import '../../models/game_box.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import 'charades_mime_session_screen.dart';
import 'widgets/glass_session_card.dart';

/// "Qui commence ?" puis le compte à rebours avant la manche (voir demande
/// utilisateur, maquette "Écran 3 — Qui commence ?"/"Écran 4 —
/// Préparation") — un seul écran à deux étapes locales plutôt que deux
/// routes séparées, rien à persister entre les deux (juste qui tient le
/// téléphone en premier, affiché le temps du compte à rebours).
class CharadesWhoStartsScreen extends StatefulWidget {
  final Game game;
  final GameBox box;

  const CharadesWhoStartsScreen({super.key, required this.game, required this.box});

  @override
  State<CharadesWhoStartsScreen> createState() => _CharadesWhoStartsScreenState();
}

enum _Step { whoStarts, countdown }

class _CharadesWhoStartsScreenState extends State<CharadesWhoStartsScreen> {
  _Step _step = _Step.whoStarts;
  String? _starterLabel;
  // "Prêt ?" → 3 → 2 → 1 → "MIME !" — voir demande utilisateur.
  static const _ticks = ['Prêt ?', '3', '2', '1', 'MIME !'];
  int _tickIndex = 0;
  Timer? _tickTimer;

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  void _pick(String label) {
    HapticFeedback.selectionClick();
    setState(() {
      _starterLabel = label;
      _step = _Step.countdown;
      _tickIndex = 0;
    });
    _tickTimer = Timer.periodic(const Duration(milliseconds: 700), (timer) {
      if (!mounted) return;
      if (_tickIndex >= _ticks.length - 1) {
        timer.cancel();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => CharadesMimeSessionScreen(game: widget.game, box: widget.box)),
        );
        return;
      }
      HapticFeedback.mediumImpact();
      setState(() => _tickIndex++);
    });
  }

  void _pickRandom() => _pick(Random().nextBool() ? 'Elle' : 'Lui');

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
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: GlassSessionCard(
                theme: theme,
                child: _step == _Step.whoStarts ? _buildWhoStarts(theme) : _buildCountdown(theme),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWhoStarts(theme) {
    return Column(
      key: const ValueKey('who-starts'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Qui commence ?',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: theme.textOnBackground),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: _StarterTile(emoji: '👩', label: 'Elle', theme: theme, onTap: () => _pick('Elle'))),
            const SizedBox(width: 12),
            Expanded(child: _StarterTile(emoji: '👨', label: 'Lui', theme: theme, onTap: () => _pick('Lui'))),
          ],
        ),
        const SizedBox(height: 18),
        Text('ou', style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted)),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _pickRandom,
            icon: const Text('🎲', style: TextStyle(fontSize: 16)),
            label: const Text('Choisir au hasard'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: theme.textOnBackgroundMuted.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              foregroundColor: theme.textOnBackgroundMuted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCountdown(theme) {
    final tick = _ticks[_tickIndex];
    final isFinalTick = _tickIndex == _ticks.length - 1;
    return Column(
      key: const ValueKey('countdown'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Le téléphone est donné à $_starterLabel',
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w700, color: theme.textOnBackgroundMuted),
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 110,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: Tween(begin: 0.6, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack)),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Text(
              tick,
              key: ValueKey(tick),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: isFinalTick ? 40 : 56,
                fontWeight: FontWeight.w800,
                color: isFinalTick ? theme.primary : theme.textOnBackground,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StarterTile extends StatelessWidget {
  final String emoji;
  final String label;
  final dynamic theme;
  final VoidCallback onTap;

  const _StarterTile({required this.emoji, required this.label, required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.surface.withValues(alpha: theme.isDark ? 0.5 : 0.75),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.primary.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 34)),
              const SizedBox(height: 10),
              Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: theme.textOnBackground)),
            ],
          ),
        ),
      ),
    );
  }
}
