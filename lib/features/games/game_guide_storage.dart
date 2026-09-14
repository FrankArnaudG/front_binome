import '../../core/local_cache.dart';

/// Mémorise si un joueur a déjà vu le guide pas-à-pas d'un jeu donné (voir
/// demande utilisateur : "pour quelqu'un qui ne connaît pas le jeu... le
/// guider la première fois") — persistant localement, PAR COMPTE (userId),
/// jamais par Box : un même téléphone partagé entre deux comptes (voir
/// demande utilisateur d'une session précédente sur NearbyBillingTracker)
/// ne doit jamais mélanger qui a déjà vu quoi.
class GameGuideStorage {
  GameGuideStorage._();
  static final GameGuideStorage instance = GameGuideStorage._();

  String _key(String userId, String gameKey) => 'cache_game_guide_seen_${gameKey}_$userId';

  Future<bool> hasSeen(String userId, String gameKey) async {
    final seen = await LocalCache.instance.readJson<bool>(_key(userId, gameKey));
    return seen ?? false;
  }

  Future<void> markSeen(String userId, String gameKey) async {
    await LocalCache.instance.writeJson(_key(userId, gameKey), true);
  }
}
