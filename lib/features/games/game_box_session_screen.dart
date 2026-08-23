import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../core/app_router.dart';
import '../../l10n/locale_scope.dart';
import '../../models/app_user.dart';
import '../../models/game.dart';
import '../../models/game_box.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../box/box_scope.dart';
import 'game_box_history_screen.dart';
import 'game_service.dart';
import 'widgets/game_box_icon.dart';
import 'widgets/game_card_widgets.dart';
import 'widgets/glass_session_card.dart';

/// Pioche de cartes-questions d'une boîte (voir GameBoxesScreen) : les
/// cartes restantes sont présentées en éventail — on fait défiler pour
/// choisir librement celle qu'on veut, on la retourne, puis on l'envoie
/// au/à la partenaire (elle rejoint le compteur de cartes jouées) ou on
/// revient à l'éventail pour en choisir une autre. La boîte est terminée
/// une fois toutes les cartes envoyées.
class GameBoxSessionScreen extends StatefulWidget {
  final Game game;
  final GameBox box;
  final AppUser user;
  // Ouverture depuis la bulle "Envoyer une autre carte" d'un fil précis
  // (voir GameCardThreadScreen) : exclut TOUTES les questions déjà
  // utilisées dans CETTE discussion (la carte d'origine + toute carte déjà
  // renvoyée via ce même raccourci), pour ne pas en re-choisir une par
  // erreur.
  final Set<String> excludeQuestionIds;
  // Envoyée depuis CETTE discussion (même écran que ci-dessus) : la carte
  // choisie doit rejoindre le fil d'origine comme un nouveau message plutôt
  // que d'ouvrir une nouvelle discussion — voir _send(), qui referme alors
  // cet écran avec le nouvel envoi au lieu de pousser GameCardThreadScreen.
  final String? replyToSendId;

  const GameBoxSessionScreen({
    super.key,
    required this.game,
    required this.box,
    required this.user,
    this.excludeQuestionIds = const {},
    this.replyToSendId,
  });

  @override
  State<GameBoxSessionScreen> createState() => _GameBoxSessionScreenState();
}

class _GameBoxSessionScreenState extends State<GameBoxSessionScreen> with SingleTickerProviderStateMixin {
  late final List<GameBoxQuestion> _deck;
  late final int _totalCount;
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );
  final PageController _pageController = PageController(viewportFraction: 0.36);

  GameBoxQuestion? _selected;
  bool _sending = false;
  bool _completing = false;
  // Réponse cachée choisie AVANT l'envoi — réservée à "Le Sondage Surprise"
  // (voir Game.isBlindPoll) : contrairement aux autres jeux à boîtes, qui
  // envoie une carte y répond aussi, tout de suite, mais sans que le
  // binôme voie ce choix avant d'avoir répondu à son tour (voir
  // GameCardController::send, sender_answer).
  String? _pickedAnswer;

  @override
  void initState() {
    super.initState();
    _deck = List.of(widget.box.questions)
      ..removeWhere((q) => widget.excludeQuestionIds.contains(q.id))
      ..shuffle();
    _totalCount = _deck.length;
  }

  @override
  void dispose() {
    _flip.dispose();
    _pageController.dispose();
    super.dispose();
  }

  int get _playedCount => _totalCount - _deck.length;

  void _selectCard(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _selected = _deck[index];
      _pickedAnswer = null;
    });
    _flip.forward(from: 0);
  }

  void _backToFan() {
    if (_sending) return;
    HapticFeedback.lightImpact();
    setState(() {
      _selected = null;
      _pickedAnswer = null;
    });
    _flip.value = 0;
  }

  Future<void> _send() async {
    if (_sending || _selected == null) return;
    if (widget.game.isBlindPoll && _pickedAnswer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LocaleScope.of(context).t('game_blind_poll_choose_first'))),
      );
      return;
    }
    final card = _selected!;
    setState(() => _sending = true);
    try {
      final sentSend = await GameService.instance.sendCard(
        widget.game.id,
        widget.box.id,
        card.id,
        replyToSendId: widget.replyToSendId,
        senderAnswer: _pickedAnswer,
      );
      if (!mounted) return;
      // Le compteur (_playedCount) est mis à jour tout de suite, mais on NE
      // remet PAS encore _selected à null : la carte retournée reste
      // affichée telle quelle pendant que la discussion glisse par-dessus
      // (voir push ci-dessous), pour éviter le flash de l'éventail derrière
      // la transition de navigation.
      setState(() {
        _deck.removeWhere((q) => q.id == card.id);
        _pickedAnswer = null;
      });
      if (_deck.isEmpty) {
        // _complete() referme cet écran (dialogue puis pop) — la carte
        // retournée reste visible derrière jusque-là, rien à réinitialiser.
        await _complete();
        return;
      }
      if (!mounted) return;
      if (widget.replyToSendId != null) {
        // Rejoint la discussion d'origine comme un nouveau message — ne
        // jamais ouvrir une discussion séparée dans ce cas (voir
        // GameCardThreadScreen._sendAnotherCard, qui attend cet envoi en
        // retour pour l'ajouter directement au fil).
        Navigator.of(context).pop(sentSend);
        return;
      }
      // Ouvre directement la petite discussion dédiée à CETTE carte, comme
      // un message qui part — chaque carte a la sienne, jamais mélangée aux
      // autres (voir GameCardThreadScreen). Revenir en arrière puis
      // envoyer une autre carte SANS passer par une discussion précise ouvre
      // systématiquement une NOUVELLE discussion, jamais la même.
      AppRouter.showGlobalNavBar.value = false;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GameCardThreadScreen(
            send: sentSend,
            user: widget.user,
            game: widget.game,
            box: widget.box,
          ),
        ),
      );
      AppRouter.showGlobalNavBar.value = true;
      if (!mounted) return;
      // De retour de la discussion (bouton "back") : on revient enfin à
      // l'éventail.
      setState(() => _selected = null);
      _flip.value = 0;
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showArchivePreview() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameBoxHistoryScreen(game: widget.game, box: widget.box, user: widget.user),
      ),
    );
  }

  Future<void> _complete() async {
    setState(() => _completing = true);
    try {
      await GameService.instance.completeBox(widget.game.id, widget.box.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => GameBoxCompletionDialog(
          theme: ThemeScope.paletteOf(context),
          boxTitle: widget.box.titleFor(LocaleScope.of(context).current.code),
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final localeCode = LocaleScope.of(context).current.code;
    final partner = BoxScope.of(context).currentBox?.partnerOf(widget.user.id);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.statusBarOverlayStyle,
        foregroundColor: theme.textOnBackground,
        // FittedBox plutôt qu'un maxLines/ellipsis : le titre entier doit
        // rester lisible même sur les boîtes au nom long, quitte à rétrécir
        // un peu plutôt que d'être coupé par le badge d'actions à droite.
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            widget.box.titleFor(localeCode),
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.style_rounded, size: 14, color: theme.primary),
                    const SizedBox(width: 5),
                    Text(
                      '$_playedCount/$_totalCount',
                      style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: theme.textOnBackground),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: GlassSessionCard(
                theme: theme,
                // L'éventail reste monté en permanence (Offstage, jamais
                // retiré de l'arbre) : démonter puis remonter le PageView à
                // chaque aller-retour détruisait son ScrollPosition, d'où
                // les cartes qui retombaient à plat un instant au retour.
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Offstage(offstage: _selected != null, child: _buildFanSelector(theme)),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween(begin: 0.94, end: 1.0).animate(animation),
                          child: child,
                        ),
                      ),
                      child: _selected == null
                          ? const SizedBox.shrink(key: ValueKey('empty'))
                          : _buildFocusedCard(theme, partner),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFanSelector(ThemePalette theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.box.themeFor(LocaleScope.of(context).current.code),
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 240,
          child: PageView.builder(
            controller: _pageController,
            itemCount: _deck.length,
            itemBuilder: (context, index) => Center(child: _buildFanCard(theme, index)),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.eco_outlined, size: 14, color: theme.primary.withValues(alpha: 0.55)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                LocaleScope.of(context).t('game_fan_hint'),
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(fontSize: 12.5, color: theme.textOnBackgroundMuted),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.eco_outlined, size: 14, color: theme.primary.withValues(alpha: 0.55)),
          ],
        ),
        const SizedBox(height: 20),
        Center(
          // Toujours affiché, même à 0 (voir GameArchiveTray) : le compteur
          // local ne connaît que les cartes envoyées PENDANT cette session
          // d'éventail — à une nouvelle arrivée sur l'écran, il repart
          // toujours de 0 même si des cartes ont déjà été échangées lors de
          // sessions précédentes (l'historique réel vit côté serveur, voir
          // GameBoxHistoryScreen). Masquer le bouton dans ce cas empêchait
          // d'accéder à un historique pourtant bien réel.
          child: GameArchiveTray(
            theme: theme,
            box: widget.box,
            count: _playedCount,
            onTap: _showArchivePreview,
          ),
        ),
      ],
    );
  }

  Widget _buildFanCard(ThemePalette theme, int index) {
    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, _) {
        var page = _pageController.initialPage.toDouble();
        if (_pageController.hasClients && _pageController.position.haveDimensions) {
          page = _pageController.page ?? page;
        }
        final diff = (page - index).clamp(-2.5, 2.5);
        final isCentered = diff.abs() < 0.06;
        final angle = diff * -0.24;
        final dy = diff.abs() * 26.0;
        final scale = (1 - diff.abs() * 0.12).clamp(0.72, 1.0);
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.rotate(
            angle: angle,
            child: Transform.scale(
              scale: scale,
              child: GestureDetector(
                onTap: () {
                  if (isCentered) {
                    _selectCard(index);
                  } else {
                    _pageController.animateToPage(index, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
                  }
                },
                child: _FanCardFace(theme: theme, box: widget.box, highlighted: isCentered),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFocusedCard(ThemePalette theme, AppUser? partner) {
    final card = _selected!;
    return Column(
      key: ValueKey('focused-${card.id}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.box.themeFor(LocaleScope.of(context).current.code),
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: 220,
          height: 300,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_deck.length > 2)
                Positioned(
                  top: 14,
                  child: Transform.rotate(angle: -0.07, child: DeckShadowCard(theme: theme)),
                ),
              if (_deck.length > 1)
                Positioned(
                  top: 7,
                  child: Transform.rotate(angle: 0.05, child: DeckShadowCard(theme: theme)),
                ),
              FlippableCard(
                flip: _flip,
                back: GameCardBack(theme: theme, box: widget.box),
                front: GameCardFront(theme: theme, text: card.textFor(LocaleScope.of(context).current.code)),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: GestureDetector(
                  onTap: _backToFan,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.35),
                    ),
                    child: const Icon(Icons.close_rounded, size: 18, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.game.isBlindPoll) ...[
          const SizedBox(height: 18),
          _buildAnswerPicker(theme, card),
        ],
        const SizedBox(height: 24),
        GameCardActions(
          theme: theme,
          sendLabel: partnerSendLabel(context, partner, card.id),
          sending: _sending || _completing,
          onSend: _send,
          onBack: _backToFan,
        ),
      ],
    );
  }

  /// Choix de LA réponse cachée avant l'envoi — "Le Sondage Surprise"
  /// uniquement (voir Game.isBlindPoll). Le binôme ne verra ce choix qu'une
  /// fois SA propre réponse donnée à son tour (voir GameCardThreadScreen,
  /// révélation automatique).
  Widget _buildAnswerPicker(ThemePalette theme, GameBoxQuestion card) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          LocaleScope.of(context).t('game_blind_poll_hidden_answer_label'),
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: theme.textOnBackgroundMuted),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in card.options)
              _AnswerChoiceChip(
                theme: theme,
                label: option,
                selected: _pickedAnswer == option,
                onTap: () => setState(() => _pickedAnswer = option),
              ),
          ],
        ),
      ],
    );
  }
}

class _AnswerChoiceChip extends StatelessWidget {
  final ThemePalette theme;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AnswerChoiceChip({required this.theme, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? theme.primary : theme.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? Colors.transparent : theme.primary.withValues(alpha: 0.35)),
          ),
          child: Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : theme.textOnBackground,
            ),
          ),
        ),
      ),
    );
  }
}

/// Carte de l'éventail de sélection (voir _buildFanCard) : la carte au
/// centre est mise en avant (lueur + icône plus visible), les autres sont
/// atténuées — tape sur la carte centrale pour la choisir, sur une carte
/// latérale pour la faire glisser au centre.
class _FanCardFace extends StatelessWidget {
  final ThemePalette theme;
  final GameBox box;
  final bool highlighted;

  const _FanCardFace({required this.theme, required this.box, required this.highlighted});

  @override
  Widget build(BuildContext context) {
    final hasImage = box.imagePath != null;

    return Container(
      width: 132,
      height: 190,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: hasImage
            ? null
            : LinearGradient(
                colors: highlighted
                    ? [theme.primary, theme.secondary]
                    : [theme.primary.withValues(alpha: 0.5), theme.secondary.withValues(alpha: 0.5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(18),
        border: hasImage
            ? null
            : Border.all(
                color: highlighted ? Colors.white.withValues(alpha: 0.75) : theme.primary.withValues(alpha: 0.25),
                width: highlighted ? 1.6 : 1,
              ),
        boxShadow: highlighted
            ? [BoxShadow(color: theme.primary.withValues(alpha: 0.45), blurRadius: 22, offset: const Offset(0, 10))]
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 6))],
      ),
      // L'image (voir GameBox.imagePath, réglable depuis l'espace admin)
      // recouvre TOUTE la carte, pas juste le badge central — remplace
      // entièrement le dégradé + l'icône quand elle est renseignée.
      child: hasImage
          ? Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: highlighted ? 1 : 0.55,
                  child: Image.network(
                    box.imagePath!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => _CardIconBadge(
                      theme: theme,
                      box: box,
                      highlighted: highlighted,
                    ),
                  ),
                ),
                if (!highlighted) Container(color: Colors.black.withValues(alpha: 0.15)),
              ],
            )
          : Center(child: _CardIconBadge(theme: theme, box: box, highlighted: highlighted)),
    );
  }
}

class _CardIconBadge extends StatelessWidget {
  final ThemePalette theme;
  final GameBox box;
  final bool highlighted;

  const _CardIconBadge({required this.theme, required this.box, required this.highlighted});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: highlighted ? 0.7 : 0.4)),
      ),
      child: Icon(
        iconForGameBox(box.iconKey),
        color: Colors.white.withValues(alpha: highlighted ? 0.95 : 0.55),
        size: 24,
      ),
    );
  }
}
