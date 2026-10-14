import '../../models/game.dart';

/// Partagé entre AddFriendScreen (défi via code) et FriendChallengeScreen
/// (défi direct depuis la liste "Mes amis de jeu") — voir demande
/// utilisateur : les deux proposent le même choix des 7 jeux temps réel.

/// Les 7 jeux temps réel éligibles au défi d'ami (voir
/// GameInviteController::FRIEND_SESSION_TYPES côté backend) — dans l'ordre
/// où ils apparaissent au choix.
const kFriendChallengeableSessionTypes = [
  'memory_game',
  'tic_tac_toe',
  'dot_squares',
  'number_hunt',
  'war_card',
  'suit_battle',
  'battleship',
];

/// Voir diagnostic utilisateur (alignement binôme/défi d'ami, phase 2) :
/// seul le Morpion n'a aucun concept de difficulté — les 6 autres doivent
/// désormais proposer le même choix qu'avec le binôme (voir
/// FriendDifficultyScreen), au lieu d'une valeur fixe envoyée sans le dire.
bool gameHasDifficultyChoice(Game game) => !game.isTicTacToe;

/// Les 7 jeux éligibles, triés dans l'ordre de [kFriendChallengeableSessionTypes].
List<Game> friendChallengeableGames(List<Game> allGames) {
  final challengeable = allGames.where((g) => kFriendChallengeableSessionTypes.contains(g.sessionType)).toList();
  challengeable.sort(
    (a, b) => kFriendChallengeableSessionTypes.indexOf(a.sessionType).compareTo(kFriendChallengeableSessionTypes.indexOf(b.sessionType)),
  );
  return challengeable;
}
