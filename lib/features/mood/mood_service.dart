import '../../core/api_client.dart';
import '../../core/local_cache.dart';
import '../../models/mood.dart';

/// "Notre Humeur du Jour" — voir MoodController côté backend.
class MoodService {
  MoodService._();
  static final MoodService instance = MoodService._();

  static const _cacheKey = 'cache_mood_today';

  /// Dernière réponse connue de `/mood/today` (voir LocalCache), sans appel
  /// réseau — permet au Dashboard d'afficher une météo déjà renseignée
  /// instantanément au lancement, plutôt qu'un état vide le temps du
  /// réseau (voir demande utilisateur : garder en cache, puis vérifier et
  /// mettre à jour depuis le serveur). Périmée dès que le jour a changé
  /// depuis la mise en cache (voir `mood_date` de `mine`/`partner`) : une
  /// météo d'hier ne doit jamais s'afficher comme celle d'aujourd'hui,
  /// même brièvement (voir demande utilisateur : "si la date limite
  /// arrive ça disparaît") — dans ce cas, `null` comme si rien n'était en
  /// cache.
  Future<(Mood?, Mood?, MoodSuggestion?, MoodSuggestion?)?> cachedToday() async {
    final data = await LocalCache.instance.readJson<Map<String, dynamic>>(_cacheKey);
    if (data == null) return null;
    final mine = data['mine'] != null ? Mood.fromJson(data['mine'] as Map<String, dynamic>) : null;
    if (mine != null && !_isToday(mine.moodDate)) return null;
    final partner = data['partner'] != null ? Mood.fromJson(data['partner'] as Map<String, dynamic>) : null;
    if (partner != null && !_isToday(partner.moodDate)) return null;
    final mineSuggestion =
        data['mine_suggestion'] != null ? MoodSuggestion.fromJson(data['mine_suggestion'] as Map<String, dynamic>) : null;
    final partnerSuggestion =
        data['partner_suggestion'] != null ? MoodSuggestion.fromJson(data['partner_suggestion'] as Map<String, dynamic>) : null;
    return (mine, partner, mineSuggestion, partnerSuggestion);
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  /// Les humeurs du jour du couple : `mine` et `partner`, chacune `null` si
  /// pas encore postée aujourd'hui — accompagnées du conseil/défi
  /// personnalisé pour leur combinaison humeur+besoin+envie (voir
  /// MoodSuggestion), calculé côté serveur.
  Future<(Mood?, Mood?, MoodSuggestion?, MoodSuggestion?)> fetchToday() async {
    final data = await ApiClient.instance.get('/mood/today') as Map<String, dynamic>;
    await LocalCache.instance.writeJson(_cacheKey, data);
    final mine = data['mine'] != null ? Mood.fromJson(data['mine'] as Map<String, dynamic>) : null;
    final partner = data['partner'] != null ? Mood.fromJson(data['partner'] as Map<String, dynamic>) : null;
    final mineSuggestion =
        data['mine_suggestion'] != null ? MoodSuggestion.fromJson(data['mine_suggestion'] as Map<String, dynamic>) : null;
    final partnerSuggestion =
        data['partner_suggestion'] != null ? MoodSuggestion.fromJson(data['partner_suggestion'] as Map<String, dynamic>) : null;
    return (mine, partner, mineSuggestion, partnerSuggestion);
  }

  /// Pose ou met à jour l'humeur du jour de l'utilisateur courant
  /// (modifiable dans la journée).
  Future<Mood> share({required String moodKey, String? needKey, String? desireKey}) async {
    final data = await ApiClient.instance.post('/mood', body: {
      'mood_key': moodKey,
      if (needKey != null) 'need_key': needKey,
      if (desireKey != null) 'desire_key': desireKey,
    }) as Map<String, dynamic>;
    return Mood.fromJson(data);
  }
}
