import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/locale_scope.dart';
import '../../models/game.dart';
import '../../models/game_box.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import 'widgets/glass_session_card.dart';

enum _Phase { ready, playing, recap }

/// Défi chronométré en présentiel (voir Game.challengeSeconds côté admin) :
/// un thème/une mission tirée au hasard, un chrono, puis on repasse le
/// téléphone — même famille que Charades mais sans mots à cycler, un seul
/// prompt affiché pour toute la manche. Aucune synchronisation réseau.
class TimedChallengeSessionScreen extends StatefulWidget {
  final Game game;
  final List<GameBoxQuestion> prompts;

  const TimedChallengeSessionScreen({super.key, required this.game, required this.prompts});

  @override
  State<TimedChallengeSessionScreen> createState() => _TimedChallengeSessionScreenState();
}

class _TimedChallengeSessionScreenState extends State<TimedChallengeSessionScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _timer = AnimationController(
    vsync: this,
    duration: Duration(seconds: widget.game.challengeSeconds),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) _endRound();
    });

  _Phase _phase = _Phase.ready;
  String? _prompt;

  @override
  void dispose() {
    _timer.dispose();
    super.dispose();
  }

  String? _drawPrompt() {
    if (widget.prompts.isEmpty) return null;
    final localeCode = LocaleScope.of(context).current.code;
    if (widget.prompts.length == 1) return widget.prompts.first.textFor(localeCode);
    final pool = widget.prompts.where((p) => p.textFor(localeCode) != _prompt).toList();
    return (pool..shuffle()).first.textFor(localeCode);
  }

  void _startRound() {
    HapticFeedback.mediumImpact();
    setState(() {
      _prompt = _drawPrompt();
      _phase = _Phase.playing;
    });
    _timer.forward(from: 0);
  }

  void _endRound() {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    setState(() => _phase = _Phase.recap);
  }

  void _backToReady() {
    setState(() => _phase = _Phase.ready);
    _timer.value = 0;
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
        title: Text(
          widget.game.nameFor(LocaleScope.of(context).current.code),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: GlassSessionCard(
                theme: theme,
                child: switch (_phase) {
                  _Phase.ready => _ReadyView(theme: theme, seconds: widget.game.challengeSeconds, onStart: _startRound),
                  _Phase.playing => _PlayingView(theme: theme, timer: _timer, seconds: widget.game.challengeSeconds, prompt: _prompt, onFinish: _endRound),
                  _Phase.recap => _RecapView(theme: theme, onNextRound: _backToReady, onFinish: () => Navigator.of(context).pop()),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadyView extends StatelessWidget {
  final ThemePalette theme;
  final int seconds;
  final VoidCallback onStart;

  const _ReadyView({required this.theme, required this.seconds, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [theme.primary, theme.secondary]),
          ),
          child: const Icon(Icons.timer_rounded, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 18),
        Text(
          'Prêt·e pour le défi ?',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
        const SizedBox(height: 8),
        Text(
          'Un thème sera tiré au lancement, chrono de $seconds secondes',
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(colors: [theme.primary, theme.secondary]),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onStart,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Commencer (${seconds}s)',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 15),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlayingView extends StatelessWidget {
  final ThemePalette theme;
  final AnimationController timer;
  final int seconds;
  final String? prompt;
  final VoidCallback onFinish;

  const _PlayingView({required this.theme, required this.timer, required this.seconds, required this.prompt, required this.onFinish});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: timer,
          builder: (context, _) {
            final remaining = (seconds * (1 - timer.value)).ceil().clamp(0, seconds);
            final urgent = remaining <= 10;
            return Column(
              children: [
                Text(
                  '$remaining s',
                  style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w800, color: urgent ? Colors.redAccent : theme.textOnBackground),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: 1 - timer.value,
                    minHeight: 6,
                    backgroundColor: theme.primary.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(urgent ? Colors.redAccent : theme.primary),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 28),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 120),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.primary.withValues(alpha: 0.35)),
          ),
          child: Text(
            prompt ?? 'À toi de jouer !',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 19, fontWeight: FontWeight.w700, height: 1.4, color: theme.textOnBackground),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onFinish,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: theme.textOnBackgroundMuted.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text('Terminer la manche', style: GoogleFonts.nunito(fontWeight: FontWeight.w700, color: theme.textOnBackgroundMuted)),
          ),
        ),
      ],
    );
  }
}

class _RecapView extends StatelessWidget {
  final ThemePalette theme;
  final VoidCallback onNextRound;
  final VoidCallback onFinish;

  const _RecapView({required this.theme, required this.onNextRound, required this.onFinish});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.emoji_events_rounded, color: theme.primary, size: 44),
        const SizedBox(height: 14),
        Text(
          'Manche terminée !',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 20, color: theme.textOnBackground),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(colors: [theme.primary, theme.secondary]),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onNextRound,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Manche suivante 🔁',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: onFinish,
            child: Text('Terminer', style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted)),
          ),
        ),
      ],
    );
  }
}
