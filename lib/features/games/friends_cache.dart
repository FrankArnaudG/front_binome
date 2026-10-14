import '../../core/local_cache.dart';
import '../../models/public_profile.dart';

/// Copie locale de la liste d'amis de jeu (voir GameService.fetchFriends), pour pouvoir en choisir un
/// SANS connexion internet — voir demande utilisateur (défi à un ami en présentiel connecté/Bluetooth) :
/// "on defit le ami qui sont deja ami si jai pas de connection internet pour etablir la liaison
/// d'amitié" — l'amitié doit donc déjà exister ET être déjà connue de CE téléphone avant de partir sans
/// réseau. [LocalCache] reste la seule source déjà utilisée ailleurs dans l'app pour ce genre de
/// mémorisation "dernière réponse réseau réussie" (voir sa doc de classe) — jamais la vérité, juste un
/// repli hors ligne.
class FriendsCache {
  FriendsCache._();

  static const _key = 'cache_friends_list';

  /// À appeler après chaque [GameService.fetchFriends] réussi (voir FriendChallengeScreen) — écrase la
  /// copie précédente par la liste la plus à jour.
  static Future<void> save(List<PublicProfile> friends) {
    return LocalCache.instance.writeJson(
      _key,
      friends.map((f) => {'id': f.id, 'prenom': f.prenom, 'name': f.name, 'avatar': f.avatar}).toList(),
    );
  }

  /// Liste vide si jamais chargée en ligne depuis ce téléphone (voir demande utilisateur : uniquement
  /// des amis DÉJÀ connus, jamais un lien d'amitié flambant neuf créé sans réseau).
  static Future<List<PublicProfile>> read() async {
    final raw = await LocalCache.instance.readJson<List<dynamic>>(_key);
    if (raw == null) return const [];
    return raw
        .whereType<Map>()
        .map((e) => PublicProfile.fromJson(e.cast<String, dynamic>()))
        .toList();
  }
}
