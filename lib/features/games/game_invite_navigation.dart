import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/token_storage.dart';
import '../../models/app_user.dart';
import '../../models/game_invite.dart';
import '../box/box_scope.dart';
import 'dot_squares/dot_squares_board_screen.dart';
import 'dot_squares/dot_squares_difficulty_screen.dart';
import 'dot_squares/dot_squares_mode_screen.dart';
import 'dot_squares/dot_squares_transport_remote.dart';
import 'game_service.dart';
import 'memory_game/memory_game_board_screen.dart';
import 'memory_game/memory_game_difficulty_screen.dart';
import 'memory_game/memory_game_mode_screen.dart';
import 'memory_game/memory_game_transport_remote.dart';
import 'battleship/battleship_difficulty_screen.dart';
import 'battleship/battleship_mode_screen.dart';
import 'battleship/battleship_placement_screen.dart';
import 'battleship/battleship_transport_remote.dart';
import 'number_hunt/number_hunt_board_screen.dart';
import 'number_hunt/number_hunt_difficulty_screen.dart';
import 'number_hunt/number_hunt_mode_screen.dart';
import 'number_hunt/number_hunt_transport_remote.dart';
import 'tic_tac_toe/tic_tac_toe_board_screen.dart';
import 'tic_tac_toe/tic_tac_toe_mode_screen.dart';
import 'tic_tac_toe/tic_tac_toe_transport_remote.dart';
import 'war_card/war_card_board_screen.dart';
import 'war_card/war_card_difficulty_screen.dart';
import 'war_card/war_card_mode_screen.dart';
import 'war_card/war_card_transport_remote.dart';
import 'suit_battle/suit_battle_board_screen.dart';
import 'suit_battle/suit_battle_difficulty_screen.dart';
import 'suit_battle/suit_battle_mode_screen.dart';
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

  // Voir demande utilisateur : seul celui qui a lancé la partie voit "Rejouer" (= nouvelle
  // invitation, même difficulté) ; l'autre joueur ne voit que "Quitter", qui lui ouvre le choix de
  // la difficulté. Un défi d'ami hors-Box n'a pas de binôme à ré-inviter : pas de "Rejouer" et
  // "Quitter" referme simplement le jeu.
  final isLauncher = resolved.inviterId == me.id;
  final canRematch = isLauncher && !resolved.isFriendInvite;
  final canBackToChoice = !isLauncher && !resolved.isFriendInvite;
  Future<void> Function(BuildContext)? quitTo(Widget Function() choice) => canBackToChoice
      ? (ctx) async {
          Navigator.of(ctx).pushReplacement(MaterialPageRoute<void>(builder: (_) => choice()));
        }
      : null;

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
        isLauncher: isLauncher,
        onRematch: canRematch
            ? (ctx) => startMemoryGameAndPush(ctx, game: game, user: me, mode: MemoryGameMode.remote, pairCount: session.pairCount, replaceCurrent: true)
            : null,
        onQuit: quitTo(() => MemoryGameDifficultyScreen(game: game, user: me, mode: MemoryGameMode.remote)),
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
        isLauncher: isLauncher,
        onRematch: canRematch
            ? (ctx) => startTicTacToeAndPush(ctx, game: game, user: me, mode: TicTacToeMode.remote, replaceCurrent: true)
            : null,
        onQuit: quitTo(() => TicTacToeModeScreen(game: game, user: me)),
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
        isLauncher: isLauncher,
        onRematch: canRematch
            ? (ctx) => startDotSquaresAndPush(ctx, game: game, user: me, mode: DotSquaresMode.remote, cols: session.gridCols, replaceCurrent: true)
            : null,
        onQuit: quitTo(() => DotSquaresDifficultyScreen(game: game, user: me, mode: DotSquaresMode.remote)),
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
        isLauncher: isLauncher,
        onRematch: canRematch
            ? (ctx) => startNumberHuntAndPush(ctx, game: game, user: me, mode: NumberHuntMode.remote, cellCount: session.cellCount, replaceCurrent: true)
            : null,
        onQuit: quitTo(() => NumberHuntDifficultyScreen(game: game, user: me, mode: NumberHuntMode.remote)),
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
        isLauncher: isLauncher,
        onRematch: canRematch
            ? (ctx) => startWarCardAndPush(ctx, game: game, user: me, mode: WarCardMode.remote, deckSize: session.deckSize, replaceCurrent: true)
            : null,
        onQuit: quitTo(() => WarCardDifficultyScreen(game: game, user: me, mode: WarCardMode.remote)),
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
        isLauncher: isLauncher,
        onRematch: canRematch
            ? (ctx) => startSuitBattleAndPush(ctx, game: game, user: me, deckSize: session.deckSize, replaceCurrent: true)
            : null,
        onQuit: quitTo(() => SuitBattleDifficultyScreen(game: game, user: me)),
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
        isLauncher: isLauncher,
        onRematch: canRematch
            ? (ctx) => startBattleshipAndPush(ctx, game: game, user: me, mode: BattleshipMode.remote, gridSize: session.gridSize, replaceCurrent: true)
            : null,
        onQuit: quitTo(() => BattleshipDifficultyScreen(game: game, user: me, mode: BattleshipMode.remote)),
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
