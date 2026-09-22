import 'dart:async';

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
import '../game_guide_notes.dart';
import '../game_invite_waiting_screen.dart';
import '../game_service.dart';
import 'memory_emoji_pool.dart';
import 'memory_game_board_screen.dart';
import 'memory_game_mode_screen.dart';
import 'memory_game_transport_local.dart';

/// Démarre une partie (à distance ou pass-and-play) et pousse l'écran
/// correspondant — fonction autonome plutôt que méthode d'écran, car elle
/// doit pouvoir être rappelée depuis [MemoryGameBoardScreen] lui-même pour
/// le bouton "Rejouer" (voir onRematch ci-dessous), à un moment où l'écran
/// de difficulté d'origine peut déjà avoir été retiré de la pile — le
/// `context` utilisé est donc toujours celui de l'appelant ACTUEL, jamais
/// capturé depuis un State qui pourrait être démonté entre-temps.
///
/// Mode à distance : passe désormais par une INVITATION (voir GameInvite)
/// plutôt que de créer la session tout de suite — pousse
/// [GameInviteWaitingScreen], qui pousse lui-même le plateau une fois le
/// binôme d'accord (voir demande utilisateur : pop-up d'acceptation +
/// écran d'attente). Pass-and-play inchangé (aucun appel réseau, voir
/// LocalMemoryGameTransport).
Future<void> startMemoryGameAndPush(
  BuildContext context, {
  required Game game,
  required AppUser user,
  required MemoryGameMode mode,
  required int pairCount,
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
    if (mode == MemoryGameMode.remote) {
      final board = generateShuffledMemoryBoard(pairCount);
      final invite = await GameService.instance.createGameInvite(
        game.id,
        sessionType: 'memory_game',
        payload: {'pair_count': pairCount, 'board': board},
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
    // LocalMemoryGameTransport.
    final transport = LocalMemoryGameTransport(pairCount: pairCount, myUserId: user.id, partnerUserId: partner.id);
    if (!context.mounted) return;

    final route = MaterialPageRoute<void>(
      builder: (_) => MemoryGameBoardScreen(
        game: game,
        user: user,
        transport: transport,
        playerNames: {user.id: user.prenom, partner.id: partner.prenom},
        playerAvatars: {user.id: user.avatar, partner.id: partner.avatar},
        onRematch: (ctx) => startMemoryGameAndPush(
          ctx,
          game: game,
          user: user,
          mode: mode,
          pairCount: pairCount,
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

/// Choix de la difficulté (voir MemoryGameDifficulty.all) puis lancement
/// de la partie — réutilisé pour les modes à distance et pass-and-play
/// (voir MemoryGameMode) ; le mode présentiel connecté choisit sa
/// difficulté APRÈS la connexion, uniquement par l'hôte (voir
/// memory_game_nearby_connect_screen.dart, qui affiche sa propre liste
/// pour ne pas dupliquer ce fichier entier pour un seul écran différent).
class MemoryGameDifficultyScreen extends StatefulWidget {
  final Game game;
  final AppUser user;
  final MemoryGameMode mode;

  const MemoryGameDifficultyScreen({super.key, required this.game, required this.user, required this.mode});

  @override
  State<MemoryGameDifficultyScreen> createState() => _MemoryGameDifficultyScreenState();
}

class _MemoryGameDifficultyScreenState extends State<MemoryGameDifficultyScreen> {
  bool _starting = false;
  final _firstDifficultyGuideKey = GlobalKey();
  // Guide pas-à-pas (voir demande utilisateur : "ajouter dans tous les
  // écrans qui suivent") — cet écran vérifie LUI-MÊME s'il a déjà été vu
  // (plutôt que de recevoir un `showGuide` transmis depuis l'écran
  // précédent), pour fonctionner peu importe comment on y arrive : depuis
  // l'écran de choix du mode, mais aussi une notification push qui pousse
  // directement ici, ou tout autre chemin futur.
  static const _guideKey = 'memory_game_difficulty';

  @override
  void initState() {
    super.initState();
    _maybeStartGuide();
  }

  Future<void> _maybeStartGuide() async {
    final seen = await GameGuideStorage.instance.hasSeen(widget.user.id, _guideKey);
    if (seen || !mounted) return;
    GameGuideStorage.instance.markSeen(widget.user.id, _guideKey);
    _startGuide();
  }

  // Bouton "?" de l'AppBar (voir demande utilisateur : "si je clique sur
  // le point d'interrogation le guide se relance pour cette page mais
  // dans la page suivante... rien") — même principe que
  // MemoryGameModeScreen._startGuide : rejouable manuellement à tout
  // moment, indépendamment du flag "déjà vu" (déjà marqué dès le premier
  // affichage automatique, voir _maybeStartGuide ci-dessus).
  void _startGuide() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ShowcaseView.get().startShowCase([_firstDifficultyGuideKey]);
    });
  }

  Future<void> _start(int pairCount) async {
    if (_starting) return;
    setState(() => _starting = true);
    await startMemoryGameAndPush(context, game: widget.game, user: widget.user, mode: widget.mode, pairCount: pairCount);
    if (mounted) setState(() => _starting = false);
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
        title: Text(LocaleScope.t(context, 'memory_difficulty_title')),
        actions: [
          IconButton(icon: const Icon(Icons.help_outline_rounded), tooltip: 'Revoir le guide', onPressed: _startGuide),
        ],
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: _starting
              ? Center(child: CircularProgressIndicator(color: theme.primary))
              : MemoryGameDifficultyList(
                  theme: theme,
                  onSelected: _start,
                  firstTileGuideKey: _firstDifficultyGuideKey, guideNote: widget.mode == MemoryGameMode.local ? null : kHowToPlayNote,
                ),
        ),
      ),
    );
  }
}

/// Liste des paliers, extraite pour être réutilisée telle quelle par
/// l'hôte en présentiel connecté (voir memory_game_nearby_connect_screen.dart),
/// qui choisit la difficulté après connexion plutôt qu'avant.
class MemoryGameDifficultyList extends StatelessWidget {
  final ThemePalette theme;
  final void Function(int pairCount) onSelected;
  // Guide pas-à-pas (voir demande utilisateur) — non-null uniquement pour
  // faire apparaître une bulle sur le PREMIER palier de la liste.
  final GlobalKey? firstTileGuideKey;
  // N.B. ajouté à la bulle du guide (voir game_guide_notes.dart) — null en mode "un seul téléphone".
  final String? guideNote;

  const MemoryGameDifficultyList({super.key, required this.theme, required this.onSelected, this.firstTileGuideKey, this.guideNote});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final (index, difficulty) in MemoryGameDifficulty.all.indexed) ...[
          _buildTile(context, difficulty, index == 0 ? firstTileGuideKey : null),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildTile(BuildContext context, MemoryGameDifficulty difficulty, GlobalKey? guideKey) {
    final tile = Material(
      color: theme.surface.withValues(alpha: theme.isDark ? 0.5 : 0.75),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onSelected(difficulty.pairCount),
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
                child: Center(
                  child: Text(
                    '${difficulty.cardCount}',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      LocaleScope.t(context, 'memory_difficulty_pairs', {'count': '${difficulty.pairCount}'}),
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: theme.textOnBackground),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      LocaleScope.t(context, 'memory_difficulty_grid', {
                        'cards': '${difficulty.cardCount}',
                        'cols': '${difficulty.columns}',
                        'rows': '${difficulty.rows}',
                      }),
                      style: GoogleFonts.nunito(fontSize: 12, color: theme.textOnBackgroundMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.textOnBackgroundMuted, size: 22),
            ],
          ),
        ),
      ),
    );
    if (guideKey == null) return tile;
    return Showcase(
      key: guideKey,
      title: 'Choisis une difficulté',
      description: withGuideNote('Plus il y a de cartes, plus la partie sera longue et difficile.', guideNote),
      targetBorderRadius: BorderRadius.circular(20),
      child: tile,
    );
  }
}
