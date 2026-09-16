import '../../core/local_cache.dart';

/// Mémorise quels poèmes-slides (voir [Pack]) un compte a mis en favori —
/// voir demande utilisateur : "un btn pour mettre un poème slide en
/// favori". Persistant localement, PAR COMPTE (userId), jamais côté
/// serveur ni partagé avec le binôme — c'est une préférence personnelle,
/// pas un envoi (à ne pas confondre avec `Send.isFavorite`, qui concerne
/// les poèmes déjà REÇUS, voir ContentService.toggleFavorite). Même
/// principe que GameGuideStorage : jamais mélangé entre deux comptes sur
/// un même appareil partagé.
class PackFavoriteStorage {
  PackFavoriteStorage._();
  static final PackFavoriteStorage instance = PackFavoriteStorage._();

  String _key(String userId) => 'cache_pack_favorites_$userId';

  Future<Set<String>> getFavoriteIds(String userId) async {
    final raw = await LocalCache.instance.readJson<List<dynamic>>(_key(userId));
    return raw?.map((e) => e.toString()).toSet() ?? <String>{};
  }

  Future<bool> isFavorite(String userId, String packId) async {
    final ids = await getFavoriteIds(userId);
    return ids.contains(packId);
  }

  /// Bascule l'état et renvoie le nouvel état (true = désormais favori).
  Future<bool> toggleFavorite(String userId, String packId) async {
    final ids = await getFavoriteIds(userId);
    final nowFavorite = !ids.contains(packId);
    if (nowFavorite) {
      ids.add(packId);
    } else {
      ids.remove(packId);
    }
    await LocalCache.instance.writeJson(_key(userId), ids.toList());
    return nowFavorite;
  }
}
