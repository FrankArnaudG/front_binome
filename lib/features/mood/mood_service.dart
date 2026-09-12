import '../../core/api_client.dart';
import '../../models/mood.dart';

/// "Notre Humeur du Jour" — voir MoodController côté backend.
class MoodService {
  MoodService._();
  static final MoodService instance = MoodService._();

  /// Les humeurs du jour du couple : `mine` et `partner`, chacune `null` si
  /// pas encore postée aujourd'hui — accompagnées du conseil/défi
  /// personnalisé pour leur combinaison humeur+besoin+envie (voir
  /// MoodSuggestion), calculé côté serveur.
  Future<(Mood?, Mood?, MoodSuggestion?, MoodSuggestion?)> fetchToday() async {
    final data = await ApiClient.instance.get('/mood/today') as Map<String, dynamic>;
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
