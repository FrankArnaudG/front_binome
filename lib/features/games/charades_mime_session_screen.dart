import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/locale_scope.dart';
import '../../models/game.dart';
import '../../models/game_box.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import 'widgets/game_box_icon.dart';
import 'widgets/glass_session_card.dart';

enum _Phase { ready, playing, recap }

const _roundSeconds = 300;

// Combien de secondes minimum doivent s'écouler après l'apparition d'un mot
// avant de pouvoir le marquer "Deviné !" — évite de valider par réflexe
// avant même d'avoir commencé à mimer.
const _wordLockSeconds = 5;

/// "300" → "5 min", "90" → "90s" — affichage lisible de _roundSeconds
/// (voir Commencer/_RecapView) plutôt qu'un nombre de secondes à trois
/// chiffres.
String _durationLabel(int seconds) => seconds % 60 == 0 ? '${seconds ~/ 60} min' : '${seconds}s';

/// Manche de mime pour une catégorie (voir CharadesCategoriesScreen) : jeu
/// en présentiel, un seul téléphone passé de main en main, aucune
/// synchronisation réseau — un chrono local (voir _roundSeconds) ou un mode
/// libre sans chrono (voir _timed), un mot à la fois, "Deviné" ou "Passer"
/// (le mot passé repart en fin de pioche).
class CharadesMimeSessionScreen extends StatefulWidget {
  final Game game;
  final GameBox box;

  const CharadesMimeSessionScreen({super.key, required this.game, required this.box});

  @override
  State<CharadesMimeSessionScreen> createState() => _CharadesMimeSessionScreenState();
}

class _CharadesMimeSessionScreenState extends State<CharadesMimeSessionScreen> with TickerProviderStateMixin {
  late final AnimationController _timer = AnimationController(
    vsync: this,
    duration: const Duration(seconds: _roundSeconds),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) _endRound();
    });

  // Verrou anti-réflexe sur "Deviné !" (voir _wordLockSeconds) — redémarré à
  // chaque nouveau mot affiché, qu'il vienne du début de manche, d'un
  // "Deviné" ou d'un "Passer".
  late final AnimationController _wordLock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: _wordLockSeconds),
  );

  late List<GameBoxQuestion> _deck;
  _Phase _phase = _Phase.ready;
  int _score = 0;
  // Mode libre (voir _ReadyView) : pas de compte à rebours, la manche se
  // termine quand on appuie soi-même sur "Terminer" — le résumé de fin
  // n'affiche alors pas de jugement basé sur un temps qui n'existe pas.
  bool _timed = true;

  @override
  void initState() {
    super.initState();
    _deck = _shuffledDeck();
  }

  List<GameBoxQuestion> _shuffledDeck() => List.of(widget.box.questions)..shuffle();

  @override
  void dispose() {
    _timer.dispose();
    _wordLock.dispose();
    super.dispose();
  }

  void _resetWordLock() => _wordLock.forward(from: 0);

  void _startRound({required bool timed}) {
    HapticFeedback.mediumImpact();
    setState(() {
      _phase = _Phase.playing;
      _timed = timed;
    });
    _resetWordLock();
    if (timed) _timer.forward(from: 0);
  }

  void _correct() {
    if (_deck.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _deck.removeAt(0);
      _score++;
      // La manche est bornée par le chrono (ou par l'appui sur "Terminer" en
      // mode libre), pas par la pioche : on la ré-remplit si elle se vide.
      if (_deck.isEmpty) _deck = _shuffledDeck();
    });
    _resetWordLock();
  }

  void _skip() {
    if (_deck.length <= 1) return;
    HapticFeedback.lightImpact();
    setState(() {
      final word = _deck.removeAt(0);
      _deck.add(word);
    });
    _resetWordLock();
  }

  void _endRound() {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    setState(() => _phase = _Phase.recap);
  }

  void _prepareNextRound() {
    setState(() {
      _deck = _shuffledDeck();
      _score = 0;
      _phase = _Phase.ready;
    });
    _timer.value = 0;
    _wordLock.value = 0;
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
          widget.box.titleFor(localeCode),
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
                  _Phase.ready => _ReadyView(
                      theme: theme,
                      box: widget.box,
                      onStartTimed: () => _startRound(timed: true),
                      onStartUntimed: () => _startRound(timed: false),
                    ),
                  _Phase.playing => _PlayingView(
                      theme: theme,
                      timer: _timer,
                      wordLock: _wordLock,
                      timed: _timed,
                      word: _deck.first.textFor(localeCode),
                      score: _score,
                      canSkip: _deck.length > 1,
                      onCorrect: _correct,
                      onSkip: _skip,
                      onEndUntimed: _endRound,
                    ),
                  _Phase.recap => _RecapView(
                      theme: theme,
                      score: _score,
                      timed: _timed,
                      onNextRound: _prepareNextRound,
                      onChangeCategory: () => Navigator.of(context).pop(),
                    ),
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
  final GameBox box;
  final VoidCallback onStartTimed;
  final VoidCallback onStartUntimed;

  const _ReadyView({required this.theme, required this.box, required this.onStartTimed, required this.onStartUntimed});

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
          child: Icon(iconForGameBox(box.iconKey), color: Colors.white, size: 32),
        ),
        const SizedBox(height: 18),
        Text(
          box.titleFor(LocaleScope.of(context).current.code),
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
        const SizedBox(height: 8),
        Text(
          'Passe le téléphone à la personne qui va mimer 🤳',
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
                onTap: onStartTimed,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Commencer (${_durationLabel(_roundSeconds)})',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 15),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onStartUntimed,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: theme.textOnBackgroundMuted.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(
              'Jouer sans chrono',
              style: GoogleFonts.nunito(fontWeight: FontWeight.w700, color: theme.textOnBackgroundMuted),
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
  final AnimationController wordLock;
  final bool timed;
  final String word;
  final int score;
  final bool canSkip;
  final VoidCallback onCorrect;
  final VoidCallback onSkip;
  final VoidCallback onEndUntimed;

  const _PlayingView({
    required this.theme,
    required this.timer,
    required this.wordLock,
    required this.timed,
    required this.word,
    required this.score,
    required this.canSkip,
    required this.onCorrect,
    required this.onSkip,
    required this.onEndUntimed,
  });

  Widget _scoreBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events_rounded, size: 14, color: theme.primary),
            const SizedBox(width: 5),
            Text('$score', style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: theme.textOnBackground)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (timed)
          AnimatedBuilder(
            animation: timer,
            builder: (context, _) {
              final remaining = (_roundSeconds * (1 - timer.value)).ceil().clamp(0, _roundSeconds);
              final urgent = remaining <= 10;
              return Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _scoreBadge(),
                      Text(
                        '$remaining s',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: urgent ? Colors.redAccent : theme.textOnBackground,
                          // Chiffres à chasse fixe : sans ça, "9 s"→"10 s"
                          // décale légèrement le texte à chaque changement de
                          // chiffre.
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
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
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _scoreBadge(),
              TextButton(
                onPressed: onEndUntimed,
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
                child: Text(
                  'Terminer',
                  style: GoogleFonts.nunito(fontWeight: FontWeight.w700, color: theme.textOnBackgroundMuted),
                ),
              ),
            ],
          ),
        const SizedBox(height: 32),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 180),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.primary.withValues(alpha: 0.35)),
          ),
          // Le mot doit se lire d'un coup d'œil pendant qu'on mime, souvent
          // téléphone tenu à bout de bras — texte agrandi, et un fondu entre
          // deux mots (voir ValueKey(word)) pour que le changement de mot
          // après "Deviné"/"Passer" soit visible plutôt qu'un saut instantané
          // facile à manquer.
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(animation), child: child),
            ),
            child: Text(
              word,
              key: ValueKey(word),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 32, fontWeight: FontWeight.w800, height: 1.2, color: theme.textOnBackground),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: canSkip ? onSkip : null,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: theme.textOnBackgroundMuted.withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('⏭️ Passer', style: GoogleFonts.nunito(fontWeight: FontWeight.w700, color: theme.textOnBackgroundMuted)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedBuilder(
                animation: wordLock,
                builder: (context, _) {
                  final locked = wordLock.status != AnimationStatus.completed;
                  final remainingLock = (_wordLockSeconds * (1 - wordLock.value)).ceil().clamp(0, _wordLockSeconds);
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: locked
                            ? [theme.primary.withValues(alpha: 0.35), theme.secondary.withValues(alpha: 0.35)]
                            : [theme.primary, theme.secondary],
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        // Verrou anti-réflexe (voir _wordLockSeconds) : on ne
                        // peut pas valider un mot dans les toutes premières
                        // secondes suivant son apparition.
                        onTap: locked ? null : onCorrect,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            locked ? '✅ Deviné ! ($remainingLock s)' : '✅ Deviné !',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Phrase de complicité selon le score — paliers fixes pensés pour une
/// manche de 5 minutes (voir _roundSeconds).
String _complicityPhrase(int score) {
  if (score <= 4) return 'Ce n\'est que le début — la complicité, ça se muscle ! 💪';
  if (score <= 10) return 'Une belle base, la complicité est déjà là 🙂';
  if (score <= 17) return 'Une vraie complicité, ça se sent ✨';
  if (score <= 25) return 'Un sacré bon duo ! 🔥';
  return 'Synchronisation parfaite, imparable ! 🏆';
}

class _RecapView extends StatelessWidget {
  final ThemePalette theme;
  final int score;
  final bool timed;
  final VoidCallback onNextRound;
  final VoidCallback onChangeCategory;

  const _RecapView({
    required this.theme,
    required this.score,
    required this.timed,
    required this.onNextRound,
    required this.onChangeCategory,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.emoji_events_rounded, color: theme.primary, size: 44),
        const SizedBox(height: 14),
        Text(
          '$score mot${score > 1 ? 's' : ''} deviné${score > 1 ? 's' : ''} !',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 20, color: theme.textOnBackground),
        ),
        const SizedBox(height: 6),
        Text(
          // En mode libre, aucune référence de temps n'a de sens (voir
          // _ReadyView.onStartUntimed) — ni la durée, ni le jugement du
          // score qui irait avec, l'objectif étant justement de lâcher
          // prise plutôt que de performer.
          timed ? 'en ${_durationLabel(_roundSeconds)}' : 'en mode libre, sans chrono',
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
        ),
        const SizedBox(height: 10),
        Text(
          timed ? _complicityPhrase(score) : 'Peu importe le score, ce moment compte 💛',
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: theme.primary),
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
                    'C\'est maintenant le tour de ton/ta partenaire 🔁',
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
            onPressed: onChangeCategory,
            child: Text('Changer de thème', style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted)),
          ),
        ),
      ],
    );
  }
}
