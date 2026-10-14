import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../models/app_user.dart';
import '../../models/game.dart';
import '../../theme/theme_palette.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import 'battleship/battleship_difficulty_screen.dart' show BattleshipGridSizeList;
import 'dot_squares/dot_squares_difficulty_screen.dart' show DotSquaresWidthList;
import 'game_invite_waiting_screen.dart';
import 'game_service.dart';
import 'memory_game/memory_emoji_pool.dart';
import 'memory_game/memory_game_difficulty_screen.dart' show MemoryGameDifficultyList;
import 'number_hunt/number_hunt_difficulty_screen.dart' show NumberHuntLevelList;
import 'suit_battle/suit_battle_difficulty_screen.dart' show SuitBattleLevelList;
import 'war_card/war_card_difficulty_screen.dart' show WarCardLevelList;

/// Voir diagnostic utilisateur (alignement binôme/défi d'ami, phase 2) :
/// choix de la difficulté avant d'envoyer un défi à un ami, pour les 6 jeux
/// qui ont ce concept (tous sauf Morpion, voir gameHasDifficultyChoice) —
/// réutilise telles quelles les listes déjà extraites côté binôme (ex.
/// MemoryGameDifficultyList), jamais dupliquées ici.
///
/// Exactement un des deux doit être fourni : [friendUserId] pour un ami déjà
/// connu (voir FriendChallengeScreen), [friendCode] pour un nouveau défi par
/// code (voir AddFriendScreen).
class FriendDifficultyScreen extends StatefulWidget {
  final Game game;
  final AppUser user;
  final String opponentLabel;
  final String? friendUserId;
  final String? friendCode;

  const FriendDifficultyScreen({
    super.key,
    required this.game,
    required this.user,
    required this.opponentLabel,
    this.friendUserId,
    this.friendCode,
  }) : assert((friendUserId == null) != (friendCode == null), 'Exactement un des deux doit être fourni.');

  @override
  State<FriendDifficultyScreen> createState() => _FriendDifficultyScreenState();
}

class _FriendDifficultyScreenState extends State<FriendDifficultyScreen> {
  bool _starting = false;

  Future<void> _start(Map<String, dynamic>? payload) async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final invite = await GameService.instance.createGameInvite(
        widget.game.id,
        sessionType: widget.game.sessionType,
        payload: payload,
        friendUserId: widget.friendUserId,
        friendCode: widget.friendCode,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => GameInviteWaitingScreen(invite: invite, user: widget.user)),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      setState(() => _starting = false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Une erreur est survenue, réessaie.')));
      setState(() => _starting = false);
    }
  }

  Widget _buildList(ThemePalette theme) {
    final game = widget.game;
    if (game.isMemoryGame) {
      return MemoryGameDifficultyList(
        theme: theme,
        onSelected: (pairCount) => _start({'pair_count': pairCount, 'board': generateShuffledMemoryBoard(pairCount)}),
      );
    }
    if (game.isDotSquares) {
      return DotSquaresWidthList(theme: theme, onSelected: (cols) => _start({'cols': cols}));
    }
    if (game.isNumberHunt) {
      return NumberHuntLevelList(theme: theme, onSelected: (cellCount) => _start({'cell_count': cellCount}));
    }
    if (game.isWarCard) {
      return WarCardLevelList(theme: theme, onSelected: (deckSize) => _start({'deck_size': deckSize}));
    }
    if (game.isSuitBattle) {
      return SuitBattleLevelList(theme: theme, onSelected: (deckSize) => _start({'deck_size': deckSize}));
    }
    if (game.isBattleship) {
      return BattleshipGridSizeList(theme: theme, onSelected: (gridSize) => _start({'grid_size': gridSize}));
    }
    // N'arrive jamais : les appelants vérifient gameHasDifficultyChoice()
    // avant de pousser cet écran (voir friend_challenge_support.dart).
    return const SizedBox.shrink();
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
          'Défier ${widget.opponentLabel}',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: theme.textOnBackground),
        ),
      ),
      body: ThemedBackground(
        child: SafeArea(
          child: _starting ? Center(child: CircularProgressIndicator(color: theme.primary)) : _buildList(theme),
        ),
      ),
    );
  }
}
