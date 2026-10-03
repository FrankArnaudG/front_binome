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
import 'widgets/game_card_widgets.dart';
import 'widgets/glass_session_card.dart';

const veriteColor = Color(0xFF5B8DEF);
const defiColor = Color(0xFFFF6B4A);

/// Session du jeu "Vérité ou Défi" (voir GameBoxSessionScreen pour le
/// gabarit "classique" en éventail) : on choisit d'abord une catégorie à
/// l'aveugle, PUIS on parcourt un éventail des cartes de cette catégorie
/// pour choisir précisément laquelle retourner — même geste de sélection
/// que GameBoxSessionScreen, juste précédé d'un choix de catégorie.
/// Impossible de choisir la même catégorie plus de
/// `game.consecutiveChoiceLimit` fois d'affilée tant que l'autre a encore
/// des cartes (voir [_isBlocked]) — réglable depuis l'admin, décompté à
/// l'ENVOI (pas au choix de catégorie : parcourir l'éventail puis revenir
/// en arrière sans envoyer ne doit pas compter).
class TruthOrDareSessionScreen extends StatefulWidget {
  final Game game;
  final GameBox box;
  final AppUser user;
  // Ouverture depuis la bulle "Envoyer une autre carte" d'un fil précis
  // (voir GameCardThreadScreen) : exclut TOUTES les questions déjà
  // utilisées dans CETTE discussion, pour ne pas en re-choisir une par
  // erreur dans l'éventail — voir GameBoxSessionScreen.excludeQuestionIds.
  final Set<String> excludeQuestionIds;
  // Envoyée depuis CETTE discussion (même écran que ci-dessus) : la carte
  // choisie doit rejoindre le fil d'origine comme un nouveau message plutôt
  // que d'ouvrir une nouvelle discussion — voir _send().
  final String? replyToSendId;
  // Série de choix identiques déjà envoyés par MOI dans cette discussion
  // (voir GameCardThreadScreen._myTrailingCategoryStreak) — sans ça, la
  // règle des 3 choix consécutifs (voir _isBlocked) repartirait de zéro à
  // chaque nouvelle ouverture de cet écran depuis "envoyer une autre
  // carte", et laisserait passer autant de défis d'affilée qu'on rouvre
  // l'éventail.
  final String? initialLastCategory;
  final int initialStreak;
  // Voir demande utilisateur : "mon binôme peut m'envoyer une demande me
  // disant de choisir défi ou vérité... et lui pioche une carte" — une fois
  // le binôme répondu (voir TruthOrDareRequest), la catégorie n'est PLUS un
  // choix à faire ici : 'verite' ou 'defi' saute directement l'écran de
  // choix et ouvre l'éventail correspondant (voir initState).
  final String? lockedCategory;
  // Demande "choisis Vérité ou Défi" à acquitter une fois la carte envoyée
  // (voir GameCardThreadScreen._openTruthOrDareFromRequest/GameService.
  // sendCard) — `null` pour le flux habituel (choix à l'aveugle).
  final String? fulfillsRequestId;

  const TruthOrDareSessionScreen({
    super.key,
    required this.game,
    required this.box,
    required this.user,
    this.excludeQuestionIds = const {},
    this.replyToSendId,
    this.initialLastCategory,
    this.initialStreak = 0,
    this.lockedCategory,
    this.fulfillsRequestId,
  });

  @override
  State<TruthOrDareSessionScreen> createState() => _TruthOrDareSessionScreenState();
}

class _TruthOrDareSessionScreenState extends State<TruthOrDareSessionScreen> with SingleTickerProviderStateMixin {
  List<GameBoxQuestion> _deckVerite = [];
  List<GameBoxQuestion> _deckDefi = [];
  int _totalCount = 0;
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );

  // Catégorie choisie à l'aveugle — `null` tant qu'on est sur l'écran de
  // choix. Une fois choisie, son éventail (voir _currentDeck) reste monté
  // (Offstage) même quand une carte est retournée par-dessus, pour ne pas
  // perdre la position de défilement à chaque aller-retour.
  String? _chosenCategory;
  PageController? _pageController;

  GameBoxQuestion? _selected;
  late String? _lastCategory;
  late int _streak;
  int _sentCount = 0;
  bool _sending = false;
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    _lastCategory = widget.initialLastCategory;
    _streak = widget.initialStreak;
    _loadDecks();
    final locked = widget.lockedCategory;
    if (locked != null) {
      final deck = locked == 'verite' ? _deckVerite : _deckDefi;
      // Repli silencieux sur l'écran de choix normal si la catégorie
      // imposée se trouve vide (cas rare : toutes ses cartes déjà jouées
      // dans cette discussion) plutôt que de bloquer sur un éventail vide.
      if (deck.isNotEmpty) {
        _chosenCategory = locked;
        _pageController = PageController(viewportFraction: 0.36);
      }
    }
  }

  /// Construit les deux piles à partir de la boîte — en excluant les cartes
  /// déjà jouées dans CETTE discussion (voir excludeQuestionIds), sauf
  /// [ignoreExclude] (voir _restart, quand on relance depuis zéro une fois
  /// les deux catégories épuisées pour ce fil).
  void _loadDecks({bool ignoreExclude = false}) {
    final excluded = ignoreExclude ? const <String>{} : widget.excludeQuestionIds;
    _deckVerite = widget.box.questions.where((q) => q.isVerite && !excluded.contains(q.id)).toList()..shuffle();
    _deckDefi = widget.box.questions.where((q) => q.isDefi && !excluded.contains(q.id)).toList()..shuffle();
    _totalCount = _deckVerite.length + _deckDefi.length;
  }

  /// Les deux catégories sont épuisées pour cette discussion — propose de
  /// recommencer (voir _restart) plutôt que de laisser un écran de choix
  /// avec deux tuiles vides.
  bool get _threadExhausted => _chosenCategory == null && _deckVerite.isEmpty && _deckDefi.isEmpty;

  void _restart() {
    HapticFeedback.mediumImpact();
    setState(() {
      _loadDecks(ignoreExclude: true);
      _lastCategory = null;
      _streak = 0;
      _sentCount = 0;
    });
  }

  @override
  void dispose() {
    _flip.dispose();
    _pageController?.dispose();
    super.dispose();
  }

  List<GameBoxQuestion> get _currentDeck => _chosenCategory == 'verite' ? _deckVerite : _deckDefi;
  Color get _currentColor => _chosenCategory == 'defi' ? defiColor : veriteColor;

  /// Bloque [category] si la choisir une fois de plus ferait
  /// `consecutiveChoiceLimit` fois d'affilée (donc dès `limit - 1` envois
  /// déjà faits, PAS seulement une fois le seuil atteint — sinon on
  /// laisserait passer exactement le nombre qu'on est censé interdire) ET
  /// qu'il reste une carte dans l'autre catégorie — sinon on laisserait la
  /// personne totalement bloquée si l'alternative est vide.
  bool _isBlocked(String category) {
    if (_lastCategory != category || _streak < widget.game.consecutiveChoiceLimit - 1) return false;
    final other = category == 'verite' ? _deckDefi : _deckVerite;
    return other.isNotEmpty;
  }

  /// Choisit la catégorie à l'aveugle — ouvre son éventail, ne tire pas
  /// encore de carte précise (voir _selectCardFromFan).
  void _pickCategory(String category) {
    final deck = category == 'verite' ? _deckVerite : _deckDefi;
    if (deck.isEmpty || _isBlocked(category)) return;
    HapticFeedback.selectionClick();
    _pageController?.dispose();
    setState(() {
      _chosenCategory = category;
      _pageController = PageController(viewportFraction: 0.36);
    });
  }

  void _backToCategoryChoice() {
    if (_sending) return;
    HapticFeedback.lightImpact();
    _pageController?.dispose();
    setState(() {
      _chosenCategory = null;
      _pageController = null;
    });
  }

  void _selectCardFromFan(int index) {
    HapticFeedback.selectionClick();
    setState(() => _selected = _currentDeck[index]);
    _flip.forward(from: 0);
  }

  /// Retour de la carte retournée vers son éventail (pas encore envoyée) —
  /// reste sur la MÊME catégorie, contrairement à _backToCategoryChoice.
  void _backToFan() {
    if (_sending) return;
    HapticFeedback.lightImpact();
    final card = _selected;
    if (card != null) {
      (card.isVerite ? _deckVerite : _deckDefi).add(card);
    }
    setState(() => _selected = null);
    _flip.value = 0;
  }

  Future<void> _send() async {
    if (_sending || _selected == null) return;
    final card = _selected!;
    final category = card.isVerite ? 'verite' : 'defi';
    setState(() => _sending = true);
    try {
      final sentSend = await GameService.instance.sendCard(
        widget.game.id,
        widget.box.id,
        card.id,
        replyToSendId: widget.replyToSendId,
        truthOrDareRequestId: widget.fulfillsRequestId,
      );
      if (!mounted) return;
      // Le compteur et la règle de série sont mis à jour tout de suite,
      // mais on NE remet PAS encore _selected/_chosenCategory à null : la
      // carte retournée reste affichée telle quelle pendant que la
      // discussion glisse par-dessus (voir push ci-dessous), pour éviter
      // le flash de l'écran de choix derrière la transition de navigation.
      setState(() {
        if (_lastCategory == category) {
          _streak++;
        } else {
          _lastCategory = category;
          _streak = 1;
        }
        _sentCount++;
      });
      if (_sentCount >= _totalCount) {
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
      // Ouvre directement la discussion dédiée à CETTE carte — même
      // comportement que GameBoxSessionScreen._send, pour rester cohérent
      // entre les deux gabarits de jeu.
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
      // l'écran de choix — décompté seulement maintenant (voir le
      // commentaire de classe), pas au moment d'ouvrir l'éventail.
      _pageController?.dispose();
      setState(() {
        _selected = null;
        _chosenCategory = null;
        _pageController = null;
      });
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
        title: Text(
          widget.box.titleFor(localeCode),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
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
                      '$_sentCount/$_totalCount',
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
                // Même principe que GameBoxSessionScreen : l'écran de choix
                // et l'éventail restent tous deux montés en permanence
                // (Offstage, jamais retirés de l'arbre) pour ne jamais
                // perdre l'état du PageView entre deux allers-retours.
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Offstage(
                      offstage: _chosenCategory != null,
                      child: _threadExhausted ? _buildFinishedScreen(theme) : _buildChoiceScreen(theme),
                    ),
                    if (_chosenCategory != null)
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

  /// Les deux catégories sont épuisées pour cette discussion (voir
  /// _threadExhausted) : plutôt qu'un écran de choix avec deux tuiles
  /// vides, on l'annonce explicitement et on propose de recommencer — les
  /// cartes déjà envoyées dans ce fil réapparaissent alors (voir _restart).
  Widget _buildFinishedScreen(ThemePalette theme) {
    return Column(
      key: const ValueKey('finished'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.celebration_rounded, size: 40, color: theme.primary),
        const SizedBox(height: 14),
        Text(
          LocaleScope.of(context).t('truth_or_dare_deck_exhausted_title'),
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w800, color: theme.textOnBackground),
        ),
        const SizedBox(height: 8),
        Text(
          LocaleScope.of(context).t('truth_or_dare_deck_exhausted_body'),
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(fontSize: 13, color: theme.textOnBackgroundMuted),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _restart,
          icon: const Icon(Icons.replay_rounded, size: 18),
          label: Text(LocaleScope.of(context).t('common_restart')),
          style: FilledButton.styleFrom(
            backgroundColor: theme.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: GameArchiveTray(
            theme: theme,
            box: widget.box,
            count: _sentCount,
            onTap: _showArchivePreview,
          ),
        ),
      ],
    );
  }

  /// Affiche la règle des choix consécutifs quand une tuile bloquée est
  /// tapée — spécifique au jeu Vérité ou Défi (voir _isBlocked).
  void _showBlockedDialog(String category) {
    HapticFeedback.lightImpact();
    final t = LocaleScope.of(context).t;
    final label = t(category == 'verite' ? 'truth_or_dare_truth_label' : 'truth_or_dare_dare_label');
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('truth_or_dare_rule_title')),
        content: Text(
          t('truth_or_dare_rule_body', {
            'label': label,
            'streak': '$_streak',
            'limit': '${widget.game.consecutiveChoiceLimit}',
          }),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(t('common_understood'))),
        ],
      ),
    );
  }

  Widget _buildChoiceScreen(ThemePalette theme) {
    final veriteBlocked = _isBlocked('verite');
    final defiBlocked = _isBlocked('defi');

    return Column(
      key: const ValueKey('choice'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.box.themeFor(LocaleScope.of(context).current.code),
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
        ),
        const SizedBox(height: 4),
        Text(
          LocaleScope.of(context).t('truth_or_dare_choose_category'),
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
        const SizedBox(height: 22),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _CategoryTile(
                label: LocaleScope.of(context).t('truth_or_dare_truth_label'),
                icon: Icons.psychology_alt_rounded,
                color: veriteColor,
                remaining: _deckVerite.length,
                blockedByStreak: veriteBlocked,
                onTap: _deckVerite.isEmpty ? null : (veriteBlocked ? null : () => _pickCategory('verite')),
                onBlockedTap: veriteBlocked ? () => _showBlockedDialog('verite') : null,
                imagePath: widget.game.truthImagePath,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _CategoryTile(
                label: LocaleScope.of(context).t('truth_or_dare_dare_label'),
                icon: Icons.local_fire_department_rounded,
                color: defiColor,
                remaining: _deckDefi.length,
                blockedByStreak: defiBlocked,
                onTap: _deckDefi.isEmpty ? null : (defiBlocked ? null : () => _pickCategory('defi')),
                onBlockedTap: defiBlocked ? () => _showBlockedDialog('defi') : null,
                imagePath: widget.game.dareImagePath,
              ),
            ),
          ],
        ),
        if (veriteBlocked || defiBlocked) ...[
          const SizedBox(height: 14),
          Text(
            LocaleScope.of(context).t('truth_or_dare_streak_notice', {
              'category': LocaleScope.of(context).t(
                    _lastCategory == 'verite' ? 'truth_or_dare_truth_label' : 'truth_or_dare_dare_label',
                  ),
              'streak': '$_streak',
            }),
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(fontSize: 11.5, color: theme.textOnBackgroundMuted),
          ),
        ],
        const SizedBox(height: 20),
        // Toujours affiché, même à 0 (voir GameBoxSessionScreen, même
        // correctif) : le compteur local ne connaît que les cartes envoyées
        // PENDANT cette session — masquer le bouton empêchait d'accéder à
        // un historique pourtant bien réel côté serveur.
        Center(
          child: GameArchiveTray(
            theme: theme,
            box: widget.box,
            count: _sentCount,
            onTap: _showArchivePreview,
          ),
        ),
      ],
    );
  }

  /// Éventail des cartes de la catégorie choisie — même geste de
  /// défilement/sélection que GameBoxSessionScreen._buildFanSelector,
  /// juste teinté selon Vérité (bleu) ou Défi (orange) pour rester lisible
  /// une fois qu'on a quitté l'écran de choix.
  Widget _buildFanSelector(ThemePalette theme) {
    final deck = _currentDeck;
    final color = _currentColor;
    final isDefi = _chosenCategory == 'defi';
    final imagePath = isDefi
        ? (widget.game.dareImageInFan ? widget.game.dareImagePath : null)
        : (widget.game.truthImageInFan ? widget.game.truthImagePath : null);

    return Column(
      key: ValueKey('fan-$_chosenCategory'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Voir demande utilisateur : la catégorie imposée par le binôme
        // n'est pas un choix qu'on peut changer d'avis ici.
        if (widget.lockedCategory == null)
        GestureDetector(
          onTap: _backToCategoryChoice,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back_rounded, size: 14, color: theme.textOnBackgroundMuted),
              const SizedBox(width: 4),
              Text(
                LocaleScope.of(context).t('truth_or_dare_choose_other_category'),
                style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w600, color: theme.textOnBackgroundMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(999)),
          child: Text(
            LocaleScope.of(context)
                .t(isDefi ? 'truth_or_dare_dare_label' : 'truth_or_dare_truth_label')
                .toUpperCase(),
            style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: color),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 240,
          child: PageView.builder(
            controller: _pageController,
            itemCount: deck.length,
            itemBuilder: (context, index) => Center(child: _buildFanCard(theme, index, color, imagePath)),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.eco_outlined, size: 14, color: color.withValues(alpha: 0.55)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                LocaleScope.of(context).t('game_fan_hint'),
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(fontSize: 12.5, color: theme.textOnBackgroundMuted),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.eco_outlined, size: 14, color: color.withValues(alpha: 0.55)),
          ],
        ),
      ],
    );
  }

  Widget _buildFanCard(ThemePalette theme, int index, Color color, String? imagePath) {
    return AnimatedBuilder(
      animation: _pageController!,
      builder: (context, _) {
        var page = _pageController!.initialPage.toDouble();
        if (_pageController!.hasClients && _pageController!.position.haveDimensions) {
          page = _pageController!.page ?? page;
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
                    _selectCardFromFan(index);
                  } else {
                    _pageController!.animateToPage(index, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
                  }
                },
                child: _CategoryCardFace(color: color, highlighted: isCentered, imagePath: imagePath),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFocusedCard(ThemePalette theme, AppUser? partner) {
    final card = _selected!;
    final isDefi = card.isDefi;
    final categoryColor = isDefi ? defiColor : veriteColor;
    final deck = _currentDeck;

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
              // Même effet de profondeur que GameBoxSessionScreen — laisse
              // deviner qu'il reste des cartes à piocher derrière celle-ci.
              if (deck.length > 2)
                Positioned(
                  top: 14,
                  child: Transform.rotate(angle: -0.07, child: DeckShadowCard(theme: theme)),
                ),
              if (deck.length > 1)
                Positioned(
                  top: 7,
                  child: Transform.rotate(angle: 0.05, child: DeckShadowCard(theme: theme)),
                ),
              FlippableCard(
                flip: _flip,
                back: GameCardBack(theme: theme, box: widget.box),
                front: GameCardFront(
                  theme: theme,
                  text: card.textFor(LocaleScope.of(context).current.code),
                  badge: LocaleScope.of(context)
                      .t(isDefi ? 'truth_or_dare_dare_label' : 'truth_or_dare_truth_label')
                      .toUpperCase(),
                  badgeColor: categoryColor,
                ),
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
        const SizedBox(height: 24),
        GameCardActions(
          theme: theme,
          sendLabel: partnerSendLabel(context, partner, card.id),
          sending: _sending || _completing,
          onSend: _send,
          onBack: _backToFan,
          backLabel: LocaleScope.of(context).t('truth_or_dare_back_to_fan'),
        ),
      ],
    );
  }
}

/// Carte de l'éventail Vérité/Défi (voir _buildFanCard) — même mise en
/// scène que _FanCardFace de GameBoxSessionScreen (mise en avant de la
/// carte centrale), teintée selon la catégorie plutôt que le dégradé du
/// thème, pour rester identifiable une fois l'écran de choix quitté.
class _CategoryCardFace extends StatelessWidget {
  final Color color;
  final bool highlighted;
  // Réglable depuis l'espace admin (voir Game.truthImagePath/dareImagePath
  // + truthImageInFan/dareImageInFan) — remplace tout le fond teinté par une
  // image quand renseignée ET autorisée à apparaître ici.
  final String? imagePath;

  const _CategoryCardFace({required this.color, required this.highlighted, this.imagePath});

  @override
  Widget build(BuildContext context) {
    final hasImage = imagePath != null && imagePath!.isNotEmpty;

    return Container(
      width: 132,
      height: 190,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: hasImage
            ? null
            : LinearGradient(
                colors: highlighted
                    ? [color, color.withValues(alpha: 0.65)]
                    : [color.withValues(alpha: 0.5), color.withValues(alpha: 0.3)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlighted ? Colors.white.withValues(alpha: 0.75) : Colors.white.withValues(alpha: 0.2),
          width: highlighted ? 1.6 : 1,
        ),
        boxShadow: highlighted
            ? [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 22, offset: const Offset(0, 10))]
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 6))],
      ),
      child: hasImage
          ? Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: highlighted ? 1 : 0.55,
                  child: Image.network(
                    imagePath!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => _CategoryCardIcon(color: color, highlighted: highlighted),
                  ),
                ),
              ],
            )
          : Center(child: _CategoryCardIcon(color: color, highlighted: highlighted)),
    );
  }
}

class _CategoryCardIcon extends StatelessWidget {
  final Color color;
  final bool highlighted;

  const _CategoryCardIcon({required this.color, required this.highlighted});

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
        Icons.style_rounded,
        color: Colors.white.withValues(alpha: highlighted ? 0.95 : 0.55),
        size: 24,
      ),
    );
  }
}

/// Grande tuile de choix Vérité/Défi — grisée avec cadenas si bloquée par
/// la règle des choix consécutifs, simplement estompée si la catégorie n'a
/// plus de carte.
class _CategoryTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final int remaining;
  final bool blockedByStreak;
  final VoidCallback? onTap;
  // Tapée quand la tuile est bloquée par la règle des choix consécutifs
  // (voir _showBlockedDialog) — la tuile reste tapable dans ce cas pour
  // pouvoir expliquer la règle, contrairement à `onTap` qui reste null.
  final VoidCallback? onBlockedTap;
  // Réglable depuis l'espace admin (voir Game.truthImagePath/dareImagePath)
  // — remplace tout le fond dégradé par une image quand renseignée, avec un
  // voile sombre pour garder le texte lisible (même principe que
  // GameBox.imagePath dans _FanCardFace).
  final String? imagePath;

  const _CategoryTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.remaining,
    required this.blockedByStreak,
    required this.onTap,
    this.onBlockedTap,
    this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final hasImage = imagePath != null && imagePath!.isNotEmpty;

    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap ?? onBlockedTap,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: hasImage
                  ? null
                  : LinearGradient(
                      colors: [color.withValues(alpha: 0.85), color.withValues(alpha: 0.55)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              // La lueur teintée (boxShadow) restait pensée pour le dégradé
              // plat — contre une photo, elle ressortait comme un halo
              // disgracieux autour de l'image (voir demande utilisateur) ;
              // la bordure blanche, elle, reste dans les deux cas.
              boxShadow: hasImage || disabled
                  ? []
                  : [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 18, offset: const Offset(0, 10))],
            ),
            child: Stack(
              children: [
                if (hasImage)
                  Positioned.fill(
                    child: Image.network(
                      imagePath!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [color.withValues(alpha: 0.85), color.withValues(alpha: 0.55)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (hasImage) Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.32))),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!hasImage)
                        Icon(disabled && blockedByStreak ? Icons.lock_rounded : icon, color: Colors.white, size: 30)
                      else if (disabled && blockedByStreak)
                        const Icon(Icons.lock_rounded, color: Colors.white, size: 30)
                      else
                        const SizedBox(height: 30),
                      const SizedBox(height: 10),
                      Text(
                        label,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        remaining == 0
                            ? LocaleScope.of(context).t('truth_or_dare_no_cards')
                            : LocaleScope.of(context).t(
                                remaining > 1 ? 'truth_or_dare_cards_count_other' : 'truth_or_dare_cards_count_one',
                                {'count': '$remaining'},
                              ),
                        style: GoogleFonts.nunito(fontSize: 11, color: Colors.white.withValues(alpha: 0.85)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
