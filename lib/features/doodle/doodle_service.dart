import '../../core/api_client.dart';
import '../../core/local_cache.dart';
import '../../models/doodle.dart';
import '../../models/pictionary_session.dart';

const _cacheKey = 'cache_doodles_default';

/// Doodle envoyé au binôme — voir DoodleController côté backend.
class DoodleService {
  DoodleService._();
  static final DoodleService instance = DoodleService._();

  Future<Doodle> sendDoodle(List<PictionaryStroke> strokes) async {
    final data = await ApiClient.instance.post(
      '/doodles',
      body: {'strokes': strokes.map((s) => s.toJson()).toList()},
    ) as Map<String, dynamic>;
    return Doodle.fromJson(data);
  }

  /// Dernière liste connue (voir LocalCache), sans appel réseau — même
  /// principe que ContentService.cachedSends : permet à TimelineScreen
  /// d'afficher instantanément l'entrée "Petits mots" au lancement, plutôt
  /// que de la voir apparaître avec un temps de retard le temps du fetch
  /// réseau (voir demande utilisateur : "ça n'apparaît pas immédiatement
  /// comme les autres"). `null` si rien n'a jamais été mis en cache.
  Future<List<Doodle>?> cachedDoodles() async {
    final cached = await LocalCache.instance.readJson<List<dynamic>>(_cacheKey);
    if (cached == null) return null;
    return cached.map((entry) => Doodle.fromJson(entry as Map<String, dynamic>)).toList();
  }

  /// Historique complet des doodles échangés dans la Box, du plus ancien
  /// au plus récent — voir demande utilisateur : une seule discussion pour
  /// tous les envois, consultable à tout moment (voir DoodleHistoryScreen).
  Future<List<Doodle>> fetchDoodles() async {
    final data = await ApiClient.instance.get('/doodles') as List;
    await LocalCache.instance.writeJson(_cacheKey, data);
    return data.map((e) => Doodle.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Dernier doodle non vu qui m'est destiné — `null` s'il n'y en a aucun
  /// (poll de secours, voir DoodleNotifier).
  Future<Doodle?> fetchPendingDoodle() async {
    final data = await ApiClient.instance.get('/doodles/pending');
    if (data == null) return null;
    return Doodle.fromJson(data as Map<String, dynamic>);
  }

  Future<Doodle> markDoodleViewed(String doodleId) async {
    final data = await ApiClient.instance.put('/doodles/$doodleId/viewed') as Map<String, dynamic>;
    return Doodle.fromJson(data);
  }
}
