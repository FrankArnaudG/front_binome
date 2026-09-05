import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../box/box_scope.dart';
import 'dot_squares/dot_squares_board_screen.dart';
import 'dot_squares/dot_squares_transport_remote.dart';
import 'game_service.dart';
import 'memory_game/memory_game_board_screen.dart';
import 'memory_game/memory_game_transport_remote.dart';
import 'battleship/battleship_board_screen.dart';
import 'battleship/battleship_transport_remote.dart';
import 'connect_four/connect_four_board_screen.dart';
import 'connect_four/connect_four_transport_remote.dart';
import 'pictionary/pictionary_board_screen.dart';
import 'pictionary/pictionary_transport_remote.dart';
import 'number_hunt/number_hunt_board_screen.dart';
import 'number_hunt/number_hunt_transport_remote.dart';
import 'tic_tac_toe/tic_tac_toe_board_screen.dart';
import 'tic_tac_toe/tic_tac_toe_transport_remote.dart';
import 'war_card/war_card_board_screen.dart';
import 'war_card/war_card_transport_remote.dart';

/// Type de partie visée par une notification push "partie lancée" (voir
/// PushNotificationService._handleTap) — un seul écran de transition pour
/// les 8 jeux plutôt que d'en multiplier la structure, seule la branche
/// de chargement diffère.
enum PushGameSessionType { memoryGame, ticTacToe, dotSquares, numberHunt, warCard, connectFour, battleship, pictionary }

/// Écran de transition affiché immédiatement au tap d'une notification
/// "partie lancée" par le binôme (voir demande utilisateur : "si on ouvre
/// le jeu dans un téléphone dans l'autre ça ne s'ouvre pas automatiquement
/// il faut que j'aille ouvrir") — le temps de charger la session visée,
/// pour REJOINDRE la partie EN COURS plutôt que d'en démarrer une
/// nouvelle. Copie structurelle de PushSendOpenScreen (même rôle pour les
/// envois classiques), adaptée aux 3 mini-jeux à état partagé.
class PushGameSessionOpenScreen extends StatefulWidget {
  final PushGameSessionType sessionType;
  final String sessionId;
  final AppUser user;

  const PushGameSessionOpenScreen({
    super.key,
    required this.sessionType,
    required this.sessionId,
    required this.user,
  });

  @override
  State<PushGameSessionOpenScreen> createState() => _PushGameSessionOpenScreenState();
}

class _PushGameSessionOpenScreenState extends State<PushGameSessionOpenScreen> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      switch (widget.sessionType) {
        case PushGameSessionType.memoryGame:
          await _openMemoryGame();
        case PushGameSessionType.ticTacToe:
          await _openTicTacToe();
        case PushGameSessionType.dotSquares:
          await _openDotSquares();
        case PushGameSessionType.numberHunt:
          await _openNumberHunt();
        case PushGameSessionType.warCard:
          await _openWarCard();
        case PushGameSessionType.connectFour:
          await _openConnectFour();
        case PushGameSessionType.battleship:
          await _openBattleship();
        case PushGameSessionType.pictionary:
          await _openPictionary();
      }
    } catch (_) {
      // Partie introuvable/déjà terminée entre l'envoi de la notif et le
      // tap — repli silencieux sur l'écran déjà affiché en dessous (voir
      // PushSendOpenScreen, même principe).
      if (mounted) Navigator.of(context).pop();
    }
  }

  ({
    String myId,
    String partnerId,
    String creatorId,
    String boxPartnerId,
    Map<String, String> names,
    Map<String, String?> avatars
  })? _players() {
    final box = BoxScope.of(context).currentBox;
    final partner = box?.partnerOf(widget.user.id);
    if (box == null || partner == null || box.partnerId == null) return null;
    return (
      myId: widget.user.id,
      partnerId: partner.id,
      creatorId: box.creatorId,
      // Distinct de `partnerId` ci-dessus (qui est relatif à MOI, "l'autre
      // personne") — ici le RÔLE FIXE `partner` de la Box, indépendant de
      // qui consulte (voir WarCardBoardState, seul jeu à distinguer
      // creator/partner par rôle plutôt que par "moi/l'autre").
      boxPartnerId: box.partnerId!,
      names: {widget.user.id: widget.user.prenom, partner.id: partner.prenom},
      avatars: {widget.user.id: widget.user.avatar, partner.id: partner.avatar},
    );
  }

  Future<void> _openMemoryGame() async {
    final session = await GameService.instance.fetchMemoryGameState(widget.sessionId);
    final games = await GameService.instance.fetchGames();
    final game = games.firstWhere((g) => g.id == session.gameId);
    final players = _players();
    if (!mounted || players == null) return;

    final transport = RemoteMemoryGameTransport(session: session, boxId: session.boxId, myUserId: players.myId, partnerUserId: players.partnerId);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MemoryGameBoardScreen(
          game: game,
          user: widget.user,
          transport: transport,
          playerNames: players.names,
          playerAvatars: players.avatars,
        ),
      ),
    );
  }

  Future<void> _openTicTacToe() async {
    final session = await GameService.instance.fetchTicTacToeState(widget.sessionId);
    final games = await GameService.instance.fetchGames();
    final game = games.firstWhere((g) => g.id == session.gameId);
    final players = _players();
    if (!mounted || players == null) return;

    final transport = RemoteTicTacToeTransport(session: session, boxId: session.boxId, myUserId: players.myId, partnerUserId: players.partnerId);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => TicTacToeBoardScreen(
          game: game,
          user: widget.user,
          transport: transport,
          playerNames: players.names,
          playerAvatars: players.avatars,
        ),
      ),
    );
  }

  Future<void> _openDotSquares() async {
    final session = await GameService.instance.fetchDotSquaresState(widget.sessionId);
    final games = await GameService.instance.fetchGames();
    final game = games.firstWhere((g) => g.id == session.gameId);
    final players = _players();
    if (!mounted || players == null) return;

    final transport = RemoteDotSquaresTransport(session: session, boxId: session.boxId, myUserId: players.myId, partnerUserId: players.partnerId);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DotSquaresBoardScreen(
          game: game,
          user: widget.user,
          transport: transport,
          playerNames: players.names,
          playerAvatars: players.avatars,
        ),
      ),
    );
  }

  Future<void> _openNumberHunt() async {
    final session = await GameService.instance.fetchNumberHuntState(widget.sessionId);
    final games = await GameService.instance.fetchGames();
    final game = games.firstWhere((g) => g.id == session.gameId);
    final players = _players();
    if (!mounted || players == null) return;

    final transport = RemoteNumberHuntTransport(session: session, boxId: session.boxId, myUserId: players.myId, partnerUserId: players.partnerId);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => NumberHuntBoardScreen(
          game: game,
          user: widget.user,
          transport: transport,
          playerNames: players.names,
          playerAvatars: players.avatars,
        ),
      ),
    );
  }

  Future<void> _openWarCard() async {
    final session = await GameService.instance.fetchWarCardState(widget.sessionId);
    final games = await GameService.instance.fetchGames();
    final game = games.firstWhere((g) => g.id == session.gameId);
    final players = _players();
    if (!mounted || players == null) return;

    final transport = RemoteWarCardTransport(
      session: session,
      boxId: session.boxId,
      myUserId: players.myId,
      creatorId: players.creatorId,
      partnerId: players.boxPartnerId,
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => WarCardBoardScreen(
          game: game,
          user: widget.user,
          transport: transport,
          playerNames: players.names,
          playerAvatars: players.avatars,
        ),
      ),
    );
  }

  Future<void> _openConnectFour() async {
    final session = await GameService.instance.fetchConnectFourState(widget.sessionId);
    final games = await GameService.instance.fetchGames();
    final game = games.firstWhere((g) => g.id == session.gameId);
    final players = _players();
    if (!mounted || players == null) return;

    final transport = RemoteConnectFourTransport(session: session, boxId: session.boxId, myUserId: players.myId);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ConnectFourBoardScreen(
          game: game,
          user: widget.user,
          transport: transport,
          playerNames: players.names,
          playerAvatars: players.avatars,
        ),
      ),
    );
  }

  Future<void> _openBattleship() async {
    final session = await GameService.instance.fetchBattleshipState(widget.sessionId);
    final games = await GameService.instance.fetchGames();
    final game = games.firstWhere((g) => g.id == session.gameId);
    final players = _players();
    if (!mounted || players == null) return;

    // Cette notification n'arrive qu'en fin de partie (voir
    // BattleshipController::notifyOther) — la partie est forcément déjà
    // en phase de combat/terminée, jamais en placement.
    final transport = RemoteBattleshipTransport(
      session: session,
      boxId: session.boxId,
      myUserId: players.myId,
      opponentUserId: players.partnerId,
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BattleshipBoardScreen(
          game: game,
          user: widget.user,
          transport: transport,
          playerNames: players.names,
          playerAvatars: players.avatars,
        ),
      ),
    );
  }

  Future<void> _openPictionary() async {
    final session = await GameService.instance.fetchPictionaryState(widget.sessionId);
    final games = await GameService.instance.fetchGames();
    final game = games.firstWhere((g) => g.id == session.gameId);
    final players = _players();
    if (!mounted || players == null) return;

    final transport = RemotePictionaryTransport(
      session: session,
      boxId: session.boxId,
      myUserId: players.myId,
      opponentUserId: players.partnerId,
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PictionaryBoardScreen(
          game: game,
          user: widget.user,
          transport: transport,
          playerNames: players.names,
          playerAvatars: players.avatars,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    return Scaffold(
      backgroundColor: theme.background,
      body: ThemedBackground(
        child: Center(child: CircularProgressIndicator(color: theme.primary)),
      ),
    );
  }
}
