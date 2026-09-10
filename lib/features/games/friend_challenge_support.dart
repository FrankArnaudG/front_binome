import '../../models/game.dart';
import 'memory_game/memory_emoji_pool.dart';

/// Partagé entre FriendChallengeScreen (défi via code) et FriendsListScreen
/// (défi direct depuis "Mes amis de jeu") — voir demande utilisateur : les
/// deux écrans proposent le même choix des 7 jeux temps réel.

/// Nombre de paires par défaut pour un défi d'ami au Jeu de Mémoire (voir
/// demande utilisateur : pas de sélecteur de difficulté séparé ici — cette
/// valeur reprend la difficulté "moyenne" déjà proposée dans
/// MemoryGameDifficultyScreen).
const kFriendChallengePairCount = 8;

/// Nombre de cases par défaut pour un défi d'ami à la Chasse aux Chiffres
/// (voir NumberHuntEngine.levels — seul jeu, avec le Jeu de Mémoire, dont le
/// payload de départ est OBLIGATOIRE côté backend, voir
/// GameInviteController::create) — valeur "moyenne" du palier existant.
const kFriendChallengeCellCount = 100;

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

/// `null` pour les jeux dont la session démarre sans configuration de
/// départ (Morpion, Bataille, Jeu de Carte Classique, Bataille Navale et
/// Le Jeu des Carrés acceptent tous un payload nul ou absent côté backend)
/// — seuls le Jeu de Mémoire et la Chasse aux Chiffres exigent un payload
/// (voir GameInviteController::create).
Map<String, dynamic>? friendChallengePayloadFor(Game game) {
  if (game.isMemoryGame) {
    return {'pair_count': kFriendChallengePairCount, 'board': generateShuffledMemoryBoard(kFriendChallengePairCount)};
  }
  if (game.isNumberHunt) {
    return {'cell_count': kFriendChallengeCellCount};
  }
  return null;
}

/// Les 7 jeux éligibles, triés dans l'ordre de [kFriendChallengeableSessionTypes].
List<Game> friendChallengeableGames(List<Game> allGames) {
  final challengeable = allGames.where((g) => kFriendChallengeableSessionTypes.contains(g.sessionType)).toList();
  challengeable.sort(
    (a, b) => kFriendChallengeableSessionTypes.indexOf(a.sessionType).compareTo(kFriendChallengeableSessionTypes.indexOf(b.sessionType)),
  );
  return challengeable;
}
