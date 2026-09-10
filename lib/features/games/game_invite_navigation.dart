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
import 'battleship/battleship_mode_screen.dart';
import 'battleship/battleship_placement_screen.dart';
import 'battleship/battleship_transport_remote.dart';
import 'number_hunt/number_hunt_board_screen.dart';
import 'number_hunt/number_hunt_transport_remote.dart';
import 'tic_tac_toe/tic_tac_toe_board_screen.dart';
import 'tic_tac_toe/tic_tac_toe_transport_remote.dart';
import 'war_card/war_card_board_screen.dart';
import 'war_card/war_card_transport_remote.dart';
import 'suit_battle/suit_battle_board_screen.dart';
import 'suit_battle/suit_battle_transport_remote.dart';

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

  final me = await _cachedUser();
  if (me == null || !context.mounted) return;

  // Invitation hors-Box (défi à un ami de jeu via son code, voir demande
  // utilisateur) : l'adversaire n'est jamais le binôme (voir BoxScope),
  // mais l'autre id porté par l'invite elle-même — son profil n'est par
  // définition pas déjà connu de l'app, on le récupère à part.
  final String opponentId;
  final String opponentPrenom;
  final String? opponentAvatar;
  String? boxId;
  String? boxCreatorId;
  String? boxPartnerId;

  if (resolved.isFriendInvite) {
    opponentId = resolved.inviterId == me.id ? resolved.inviteeId : resolved.inviterId;
    try {
      final profile = await GameService.instance.fetchPublicProfile(opponentId);
      opponentPrenom = profile.prenom;
      opponentAvatar = profile.avatar;
    } catch (_) {
      return;
    }
    if (!context.mounted) return;
  } else {
    final box = BoxScope.of(context).currentBox;
    final partner = box?.partnerOf(me.id);
    if (box == null || partner == null) return;
    opponentId = partner.id;
    opponentPrenom = partner.prenom;
    opponentAvatar = partner.avatar;
    boxId = box.id;
    boxCreatorId = box.creatorId;
    boxPartnerId = box.partnerId;
  }

  final playerNames = {me.id: me.prenom, opponentId: opponentPrenom};
  final playerAvatars = {me.id: me.avatar, opponentId: opponentAvatar};

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
        // boxId reste `null` pour une invitation hors-Box (voir plus haut)
        // — RemoteMemoryGameTransport bascule alors sur le canal temps
        // réel dédié à cette session plutôt que celui de la Box.
        transport: RemoteMemoryGameTransport(session: session, boxId: boxId, myUserId: me.id, partnerUserId: opponentId),
        playerNames: playerNames,
        playerAvatars: playerAvatars,
      );
    case 'tic_tac_toe':
      final session = await GameService.instance.fetchTicTacToeState(sessionId);
      if (!context.mounted) return;
      screen = TicTacToeBoardScreen(
        game: game,
        user: me,
        // boxId reste `null` pour une invitation hors-Box (voir plus haut)
        // — RemoteTicTacToeTransport bascule alors sur le canal temps réel
        // dédié à cette session plutôt que celui de la Box.
        transport: RemoteTicTacToeTransport(session: session, boxId: boxId, myUserId: me.id, partnerUserId: opponentId),
        playerNames: playerNames,
        playerAvatars: playerAvatars,
      );
    case 'dot_squares':
      final session = await GameService.instance.fetchDotSquaresState(sessionId);
      if (!context.mounted) return;
      screen = DotSquaresBoardScreen(
        game: game,
        user: me,
        // boxId reste `null` pour une invitation hors-Box (voir plus haut)
        // — RemoteDotSquaresTransport bascule alors sur le canal temps
        // réel dédié à cette session plutôt que celui de la Box.
        transport: RemoteDotSquaresTransport(session: session, boxId: boxId, myUserId: me.id, partnerUserId: opponentId),
        playerNames: playerNames,
        playerAvatars: playerAvatars,
      );
    case 'number_hunt':
      final session = await GameService.instance.fetchNumberHuntState(sessionId);
      if (!context.mounted) return;
      screen = NumberHuntBoardScreen(
        game: game,
        user: me,
        // boxId reste `null` pour une invitation hors-Box (voir plus haut)
        // — RemoteNumberHuntTransport bascule alors sur le canal temps
        // réel dédié à cette session plutôt que celui de la Box.
        transport: RemoteNumberHuntTransport(session: session, boxId: boxId, myUserId: me.id, partnerUserId: opponentId),
        playerNames: playerNames,
        playerAvatars: playerAvatars,
      );
    // Voir demande utilisateur : défi d'ami hors-Box — `creatorId`/
    // `partnerId` restent le nom historique des DEUX rôles de jeu (voir
    // XxxSession::playerIds côté backend), plus seulement "qui a créé la
    // Box" : player_one_id/player_two_id de la session pour une partie
    // hors-Box, sinon les ids de la Box comme avant.
    case 'war_card':
      final session = await GameService.instance.fetchWarCardState(sessionId);
      if (!context.mounted) return;
      screen = WarCardBoardScreen(
        game: game,
        user: me,
        transport: RemoteWarCardTransport(
          session: session,
          boxId: boxId,
          myUserId: me.id,
          creatorId: session.isFriendSession ? session.playerOneId! : boxCreatorId!,
          partnerId: session.isFriendSession ? session.playerTwoId! : boxPartnerId!,
        ),
        playerNames: playerNames,
        playerAvatars: playerAvatars,
      );
    case 'suit_battle':
      final session = await GameService.instance.fetchSuitBattleState(sessionId);
      if (!context.mounted) return;
      screen = SuitBattleBoardScreen(
        game: game,
        user: me,
        transport: RemoteSuitBattleTransport(
          session: session,
          boxId: boxId,
          myUserId: me.id,
          creatorId: session.isFriendSession ? session.playerOneId! : boxCreatorId!,
          partnerId: session.isFriendSession ? session.playerTwoId! : boxPartnerId!,
        ),
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
        transport: RemoteBattleshipTransport(session: session, boxId: boxId, myUserId: me.id, opponentUserId: opponentId),
        playerNames: playerNames,
        playerAvatars: playerAvatars,
        onRematch: (ctx) => startBattleshipAndPush(
          ctx,
          game: game,
          user: me,
          mode: BattleshipMode.remote,
          gridSize: session.gridSize,
          replaceCurrent: true,
        ),
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
