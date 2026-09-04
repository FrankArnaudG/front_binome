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
String _durationLabel(BuildContext context, int seconds) {
  final t = LocaleScope.of(context).t;
  return seconds % 60 == 0
      ? t('charades_duration_minutes', {'count': '${seconds ~/ 60}'})
      : t('charades_duration_seconds', {'count': '$seconds'});
}

/// Manche de mime pour une catégorie (voir CharadesCategoriesScreen) : jeu
/// en présentiel, un seul téléphone passé de main en main, aucune
/// synchronisation réseau — un chrono local (voir _roundSeconds) ou un mode
/// libre sans chrono (voir _timed), un mot à la fois, "Deviné" ou "Passer"
/// (le mot passé repart en fin de pioche).
class CharadesMimeSessionScreen extends StatefulWidget {
  final Game game;
  final GameBox box;

  const CharadesMimeSessionScreen({
    super.key,
    required this.game,
    required this.box,
  });

  @override
  State<CharadesMimeSessionScreen> createState() =>
      _CharadesMimeSessionScreenState();
}

class _CharadesMimeSessionScreenState extends State<CharadesMimeSessionScreen>
    with TickerProviderStateMixin {
  late final AnimationController _timer =
      AnimationController(
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

  List<GameBoxQuestion> _shuffledDeck() =>
      List.of(widget.box.questions)..shuffle();

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
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: theme.textOnBackground,
          ),
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

  const _ReadyView({
    required this.theme,
    required this.box,
    required this.onStartTimed,
    required this.onStartUntimed,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = box.imagePath != null && box.imagePath!.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Bandeau plein cadre quand une image est renseignée (voir
        // GameBox.imagePath, réglable depuis l'espace admin) — plus
        // immersif que le petit rond dégradé, qui reste le repli quand
        // aucune image n'est choisie.
        if (hasImage)
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.network(
              box.imagePath!,
              width: double.infinity,
              height: 170,
              fit: BoxFit.cover,
              alignment: box.imageAlignment,
              errorBuilder: (context, error, stackTrace) =>
                  _ReadyBadge(theme: theme, box: box),
            ),
          )
        else
          _ReadyBadge(theme: theme, box: box),
        const SizedBox(height: 18),
        Text(
          box.titleFor(LocaleScope.of(context).current.code),
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: theme.textOnBackground,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          LocaleScope.of(context).t('charades_ready_hint'),
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(
            fontSize: 13,
            color: theme.textOnBackgroundMuted,
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [theme.primary, theme.secondary],
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onStartTimed,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    LocaleScope.of(context).t('charades_start_button', {
                      'duration': _durationLabel(context, _roundSeconds),
                    }),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontSize: 15,
                    ),
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
              side: BorderSide(
                color: theme.textOnBackgroundMuted.withValues(alpha: 0.3),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              LocaleScope.of(context).t('charades_start_untimed_button'),
              style: GoogleFonts.nunito(
                fontWeight: FontWeight.w700,
                color: theme.textOnBackgroundMuted,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Repli quand la boîte n'a pas d'image personnalisée (voir _ReadyView).
class _ReadyBadge extends StatelessWidget {
  final ThemePalette theme;
  final GameBox box;

  const _ReadyBadge({required this.theme, required this.box});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [theme.primary, theme.secondary]),
      ),
      child: Icon(iconForGameBox(box.iconKey), color: Colors.white, size: 32),
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
        Text(
          '$score',
          style: GoogleFonts.nunito(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: theme.textOnBackground,
          ),
        ),
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
              final remaining = (_roundSeconds * (1 - timer.value))
                  .ceil()
                  .clamp(0, _roundSeconds);
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
                          color: urgent
                              ? Colors.redAccent
                              : theme.textOnBackground,
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
                      valueColor: AlwaysStoppedAnimation(
                        urgent ? Colors.redAccent : theme.primary,
                      ),
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
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                ),
                child: Text(
                  LocaleScope.of(context).t('charades_finish_button'),
                  style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w700,
                    color: theme.textOnBackgroundMuted,
                  ),
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
              child: ScaleTransition(
                scale: Tween(begin: 0.92, end: 1.0).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              word,
              key: ValueKey(word),
              textAlign: TextAlign.center,
              // Manuscrite plutôt que Poppins (voir demande utilisateur) —
              // taille relevée par rapport à l'ancien style : à poids visuel
              // égal, une police cursive a besoin d'être plus grande pour
              // rester aussi lisible d'un coup d'œil.
              style: GoogleFonts.caveat(
                fontSize: 44,
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: theme.textOnBackground,
              ),
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
                  side: BorderSide(
                    color: theme.textOnBackgroundMuted.withValues(alpha: 0.3),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  LocaleScope.of(context).t('charades_skip_button'),
                  style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w700,
                    color: theme.textOnBackgroundMuted,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedBuilder(
                animation: wordLock,
                builder: (context, _) {
                  final locked = wordLock.status != AnimationStatus.completed;
                  final remainingLock =
                      (_wordLockSeconds * (1 - wordLock.value)).ceil().clamp(
                        0,
                        _wordLockSeconds,
                      );
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: locked
                            ? [
                                theme.primary.withValues(alpha: 0.35),
                                theme.secondary.withValues(alpha: 0.35),
                              ]
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
                            locked
                                ? LocaleScope.of(context).t(
                                    'charades_guessed_locked_button',
                                    {'seconds': '$remainingLock'},
                                  )
                                : LocaleScope.of(
                                    context,
                                  ).t('charades_guessed_button'),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              fontSize: 14,
                            ),
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
String _complicityPhrase(BuildContext context, int score) {
  final t = LocaleScope.of(context).t;
  if (score <= 4) return t('charades_complicity_1');
  if (score <= 10) return t('charades_complicity_2');
  if (score <= 17) return t('charades_complicity_3');
  if (score <= 25) return t('charades_complicity_4');
  return t('charades_complicity_5');
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
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: LocaleScope.of(context).t(
                  score > 1
                      ? 'charades_words_guessed_other'
                      : 'charades_words_guessed_one',
                  {'count': '$score'},
                ),
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: theme.textOnBackground,
                ),
              ),
              // En mode libre, aucune référence de temps n'a de sens (voir
              // _ReadyView.onStartUntimed) — ni la durée, ni le jugement
              // du score qui irait avec, l'objectif étant justement de
              // lâcher prise plutôt que de performer — donc rien à ajouter
              // du tout, plutôt qu'une mention "mode libre" superflue.
              if (timed)
                TextSpan(
                  text:
                      ' ${LocaleScope.of(context).t('charades_recap_timed', {'duration': _durationLabel(context, _roundSeconds)})}',
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.textOnBackgroundMuted,
                  ),
                ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          timed
              ? _complicityPhrase(context, score)
              : LocaleScope.of(context).t('charades_untimed_note'),
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: theme.primary,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [theme.primary, theme.secondary],
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onNextRound,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    LocaleScope.of(context).t('charades_next_turn_button'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontSize: 14,
                    ),
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
            child: Text(
              LocaleScope.of(context).t('charades_change_theme_button'),
              style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
            ),
          ),
        ),
      ],
    );
  }
}
