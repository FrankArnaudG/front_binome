import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/locale_scope.dart';
import '../../models/game.dart';
import '../../models/game_box.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import 'widgets/game_style.dart';
import 'widgets/glass_session_card.dart';

/// Template unique pour tous les jeux du catalogue : fond de thème + carte
/// centrale "verre dépoli" à bordure lumineuse, dont seul le contenu change
/// selon [GameStyle] (voir game_style.dart) — remplace GamePlaceholderScreen.
///
/// Pas de synchronisation temps réel entre partenaires ici (pas d'API de
/// session de jeu côté backend pour l'instant) : chaque écran est une
/// session locale, pensée pour être vécue à deux sur le même téléphone ou
/// en parlant à voix haute au téléphone/en visio.
class GameSessionScreen extends StatefulWidget {
  final Game game;
  final List<GameBoxQuestion> prompts;

  const GameSessionScreen({super.key, required this.game, this.prompts = const []});

  @override
  State<GameSessionScreen> createState() => _GameSessionScreenState();
}

class _GameSessionScreenState extends State<GameSessionScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  )..forward();
  late final Animation<double> _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final style = styleForGame(widget.game);

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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: GlassSessionCard(
                  theme: theme,
                  child: switch (style) {
                    GameStyle.reflection => _ReflectionSession(game: widget.game, theme: theme),
                    GameStyle.action => _ActionSession(game: widget.game, theme: theme, prompts: widget.prompts),
                    GameStyle.creative => _CreativeSession(game: widget.game, theme: theme),
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Jeux de réflexion (20 Questions, quiz, devinettes...) : bulle de prompt
/// flottante + zone de réponse semi-transparente qui s'illumine au focus.
class _ReflectionSession extends StatefulWidget {
  final Game game;
  final ThemePalette theme;

  const _ReflectionSession({required this.game, required this.theme});

  @override
  State<_ReflectionSession> createState() => _ReflectionSessionState();
}

class _ReflectionSessionState extends State<_ReflectionSession> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final localeCode = LocaleScope.of(context).current.code;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.85, end: 1),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.background.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: theme.secondary.withValues(alpha: 0.3)),
            ),
            child: Text(
              widget.game.descriptionFor(localeCode) ?? widget.game.nameFor(localeCode),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4, color: theme.textOnBackground),
            ),
          ),
        ),
        const SizedBox(height: 28),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: _focused
                ? [BoxShadow(color: theme.primary.withValues(alpha: 0.35), blurRadius: 20, spreadRadius: 1)]
                : [],
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            maxLines: 3,
            style: GoogleFonts.nunito(color: theme.textOnBackground),
            cursorColor: theme.primary,
            decoration: InputDecoration(
              filled: true,
              fillColor: theme.background.withValues(alpha: 0.4),
              hintText: 'Écris ta réponse…',
              hintStyle: GoogleFonts.nunito(color: theme.textOnBackgroundMuted),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: theme.textOnBackgroundMuted.withValues(alpha: 0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: theme.primary, width: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Partagez vos réponses à voix haute, ou tour à tour 💬',
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
        ),
      ],
    );
  }
}

/// Jeux d'action/classiques (Vérité ou Défi, chasse au trésor...) : dé
/// central à lancer d'un tap, révèle le défi, puis CTA dégradé pour rejouer.
/// Si [prompts] est fourni (voir games.session_type = prompt_reveal), un
/// prompt admin-éditable est tiré au hasard à chaque lancer plutôt que de
/// toujours répéter game.description.
class _ActionSession extends StatefulWidget {
  final Game game;
  final ThemePalette theme;
  final List<GameBoxQuestion> prompts;

  const _ActionSession({required this.game, required this.theme, this.prompts = const []});

  @override
  State<_ActionSession> createState() => _ActionSessionState();
}

class _ActionSessionState extends State<_ActionSession> with SingleTickerProviderStateMixin {
  late final AnimationController _roll = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  bool _revealed = false;
  String? _drawnPrompt;

  void _rollDie() {
    setState(() {
      _revealed = false;
      _drawnPrompt = _drawPrompt();
    });
    _roll.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _revealed = true);
    });
  }

  /// Évite de retirer deux fois de suite le même prompt tant qu'il y a le
  /// choix (piscine généralement assez grande pour ne jamais y penser).
  String? _drawPrompt() {
    if (widget.prompts.isEmpty) return null;
    final localeCode = LocaleScope.of(context).current.code;
    if (widget.prompts.length == 1) return widget.prompts.first.textFor(localeCode);
    final pool = widget.prompts.where((p) => p.textFor(localeCode) != _drawnPrompt).toList();
    return (pool..shuffle()).first.textFor(localeCode);
  }

  @override
  void dispose() {
    _roll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _rollDie,
          child: AnimatedBuilder(
            animation: _roll,
            builder: (context, child) {
              final t = _roll.value;
              final angle = t * 4 * math.pi;
              final scale = 1 - (math.sin(t * math.pi) * 0.15);
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.002)
                  ..rotateY(angle)
                  ..scale(scale),
                child: child,
              );
            },
            child: Container(
              width: 116,
              height: 116,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [theme.primary, theme.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(color: theme.primary.withValues(alpha: 0.4), blurRadius: 26, offset: const Offset(0, 12)),
                ],
              ),
              child: Icon(
                _revealed ? Icons.favorite_rounded : Icons.casino_rounded,
                color: Colors.white,
                size: 44,
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _revealed
              ? Padding(
                  key: const ValueKey('revealed'),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    _drawnPrompt ?? widget.game.descriptionFor(LocaleScope.of(context).current.code) ?? widget.game.nameFor(LocaleScope.of(context).current.code),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4, color: theme.textOnBackground),
                  ),
                )
              : Text(
                  'Tape pour lancer 🎲',
                  key: const ValueKey('idle'),
                  style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                ),
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
                onTap: _rollDie,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    _revealed ? 'Nouveau tour' : 'Lancer le défi',
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

const _emojiPalette = [
  '😍', '🥰', '😂', '😴', '🎉', '☕', '🌙', '🔥',
  '💕', '😅', '🍕', '🎮', '🌧️', '☀️', '😭', '🥳',
  '💭', '🎵', '🐾', '✈️', '📚', '🍫', '😳', '💌',
];

/// Jeux créatifs (Devine mon émoji, charades...) : écran épuré, place à une
/// grille légère d'émojis plutôt qu'à du texte.
class _CreativeSession extends StatefulWidget {
  final Game game;
  final ThemePalette theme;

  const _CreativeSession({required this.game, required this.theme});

  @override
  State<_CreativeSession> createState() => _CreativeSessionState();
}

class _CreativeSessionState extends State<_CreativeSession> {
  final List<String> _picked = [];

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.game.descriptionFor(LocaleScope.of(context).current.code) ?? widget.game.nameFor(LocaleScope.of(context).current.code),
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 64),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.textOnBackgroundMuted.withValues(alpha: 0.2)),
          ),
          child: _picked.isEmpty
              ? Text(
                  'Ta phrase en émojis apparaît ici',
                  style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
                )
              : Text(_picked.join(' '), textAlign: TextAlign.center, style: const TextStyle(fontSize: 26)),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: _emojiPalette
              .map(
                (e) => GestureDetector(
                  onTap: () => setState(() => _picked.add(e)),
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.background.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 22)),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        if (_picked.isNotEmpty)
          TextButton(
            onPressed: () => setState(() => _picked.clear()),
            child: Text('Effacer', style: GoogleFonts.nunito(color: theme.textOnBackgroundMuted)),
          ),
      ],
    );
  }
}
