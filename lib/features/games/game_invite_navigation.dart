import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/token_storage.dart';
import '../../models/app_user.dart';
import '../../models/game_invite.dart';
import '../box/box_scope.dart';
import 'dot_squares/dot_squares_board_screen.dart';
import 'dot_squares/dot_squares_transport_remote.dart';
import 'game_service.dart';
import 'memory_game/memory_game_board_screen.dart';
import 'memory_game/memory_game_transport_remote.dart';
import 'battleship/battleship_placement_screen.dart';
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

/// Ouvre la partie créée par une invitation ACCEPTÉE ([resolved.sessionId]
/// non nul) — utilisé aussi bien côté invité·e (voir GameInviteOverlay,
/// qui vient d'accepter) que côté auteur (voir GameInviteWaitingScreen,
/// qui vient de voir l'invitation acceptée par le binôme) : même écran de
/// jeu, peu importe qui vient de déclencher la création de la session.
Future<void> openGameSessionFromInvite(
  BuildContext context,
  GameInvite resolved, {
  bool replaceCurrent = false,
}) async {
  final sessionId = resolved.sessionId;
  if (sessionId == null) return;

  final box = BoxScope.of(context).currentBox;
  final me = await _cachedUser();
  final partner = box != null && me != null ? box.partnerOf(me.id) : null;
  if (box == null || me == null || partner == null || !context.mounted) return;

  final playerNames = {me.id: me.prenom, partner.id: partner.prenom};
  final playerAvatars = {me.id: me.avatar, partner.id: partner.avatar};

  final games = await GameService.instance.fetchGames();
  final game = games.firstWhere((g) => g.id == resolved.gameId, orElse: () => games.first);
  if (!context.mounted) return;

  Widget? screen;
  switch (resolved.sessionType) {
    case 'memory_game':
      final session = await GameService.instance.fetchMemoryGameState(sessionId);
      if (!context.mounted) return;
      screen = MemoryGameBoardScreen(
        game: game,
        user: me,
        transport: RemoteMemoryGameTransport(session: session, boxId: box.id, myUserId: me.id, partnerUserId: partner.id),
        playerNames: playerNames,
        playerAvatars: playerAvatars,
      );
    case 'tic_tac_toe':
      final session = await GameService.instance.fetchTicTacToeState(sessionId);
      if (!context.mounted) return;
      screen = TicTacToeBoardScreen(
        game: game,
        user: me,
        transport: RemoteTicTacToeTransport(session: session, boxId: box.id, myUserId: me.id, partnerUserId: partner.id),
        playerNames: playerNames,
        playerAvatars: playerAvatars,
      );
    case 'dot_squares':
      final session = await GameService.instance.fetchDotSquaresState(sessionId);
      if (!context.mounted) return;
      screen = DotSquaresBoardScreen(
        game: game,
        user: me,
        transport: RemoteDotSquaresTransport(session: session, boxId: box.id, myUserId: me.id, partnerUserId: partner.id),
        playerNames: playerNames,
        playerAvatars: playerAvatars,
      );
    case 'number_hunt':
      final session = await GameService.instance.fetchNumberHuntState(sessionId);
      if (!context.mounted) return;
      screen = NumberHuntBoardScreen(
        game: game,
        user: me,
        transport: RemoteNumberHuntTransport(session: session, boxId: box.id, myUserId: me.id, partnerUserId: partner.id),
        playerNames: playerNames,
        playerAvatars: playerAvatars,
      );
    case 'war_card':
      final session = await GameService.instance.fetchWarCardState(sessionId);
      if (!context.mounted) return;
      screen = WarCardBoardScreen(
        game: game,
        user: me,
        transport: RemoteWarCardTransport(
          session: session,
          boxId: box.id,
          myUserId: me.id,
          creatorId: box.creatorId,
          partnerId: box.partnerId!,
        ),
        playerNames: playerNames,
        playerAvatars: playerAvatars,
      );
    case 'connect_four':
      final session = await GameService.instance.fetchConnectFourState(sessionId);
      if (!context.mounted) return;
      screen = ConnectFourBoardScreen(
        game: game,
        user: me,
        transport: RemoteConnectFourTransport(session: session, boxId: box.id, myUserId: me.id),
        playerNames: playerNames,
        playerAvatars: playerAvatars,
      );
    case 'battleship':
      final session = await GameService.instance.fetchBattleshipState(sessionId);
      if (!context.mounted) return;
      // Toujours l'écran de PLACEMENT ici, jamais directement le plateau
      // de combat — la session vient d'être créée par l'invitation,
      // aucune flotte n'est encore posée (voir BattleshipPlacementScreen).
      screen = BattleshipPlacementScreen(
        game: game,
        user: me,
        transport: RemoteBattleshipTransport(session: session, boxId: box.id, myUserId: me.id, opponentUserId: partner.id),
        playerNames: playerNames,
        playerAvatars: playerAvatars,
      );
    case 'pictionary':
      final session = await GameService.instance.fetchPictionaryState(sessionId);
      if (!context.mounted) return;
      screen = PictionaryBoardScreen(
        game: game,
        user: me,
        transport: RemotePictionaryTransport(session: session, boxId: box.id, myUserId: me.id, opponentUserId: partner.id),
        playerNames: playerNames,
        playerAvatars: playerAvatars,
      );
  }
  if (screen == null || !context.mounted) return;

  final route = MaterialPageRoute<void>(builder: (_) => screen!);
  if (replaceCurrent) {
    Navigator.of(context).pushReplacement(route);
  } else {
    Navigator.of(context).push(route);
  }
}

Future<AppUser?> _cachedUser() async {
  // Même mécanisme que PushNotificationService._cachedUser — BoxScope ne
  // porte pas l'utilisateur courant lui-même, seulement la Box.
  final cached = await TokenStorage.instance.readUserJson();
  if (cached == null) return null;
  try {
    return AppUser.fromJson(jsonDecode(cached) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}
