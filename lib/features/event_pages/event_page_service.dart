import '../../core/api_client.dart';
import 'event_page.dart';
import 'event_page_rsvp.dart';

/// Service CRUD des pages événement — même gabarit que RomanPhotoService.
///
/// IMPORTANT : ApiClient.get/post/put/delete() DÉCODENT DÉJÀ l'enveloppe
/// {success, message, data} et renvoient directement le contenu de `data`
/// (voir ApiClient._decode : `return decoded['data'];`). Ne JAMAIS refaire
/// `['data']` ici par-dessus — ça provoquait un TypeError ("Null n'est pas
/// un Map") à chaque appel, affiché comme un message d'erreur générique
/// côté UI alors que le backend avait réussi (voir demande utilisateur :
/// "quand je clique sur enregistrer, on me dit qu'une erreur est
/// survenue" — page bien créée en base malgré le message).
class EventPageService {
  EventPageService._();
  static final EventPageService instance = EventPageService._();

  Future<List<EventPage>> list() async {
    final data = await ApiClient.instance.get('/event-pages') as List;
    return data.map((e) => EventPage.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Création en un seul envoi — tout le contenu du formulaire (design
  /// inclus) d'un coup, voir demande utilisateur : "un formulaire simple
  /// pour demander les info necessaire... dans ca on aura les theme a
  /// choisir aussi". Aucun appel réseau avant cet envoi (le choix du
  /// design seul ne crée plus rien côté serveur).
  Future<EventPage> create(Map<String, dynamic> fields) async {
    final data = await ApiClient.instance.post('/event-pages', body: fields) as Map<String, dynamic>;
    return EventPage.fromJson(data);
  }

  Future<EventPage> update(String id, Map<String, dynamic> fields) async {
    final data = await ApiClient.instance.put('/event-pages/$id', body: fields) as Map<String, dynamic>;
    return EventPage.fromJson(data);
  }

  Future<void> destroy(String id) async {
    await ApiClient.instance.delete('/event-pages/$id');
  }

  Future<EventPage> publish(String id) async {
    final data = await ApiClient.instance.post('/event-pages/$id/publish') as Map<String, dynamic>;
    return EventPage.fromJson(data);
  }

  Future<EventPage> unpublish(String id) async {
    final data = await ApiClient.instance.post('/event-pages/$id/unpublish') as Map<String, dynamic>;
    return EventPage.fromJson(data);
  }

  Future<List<EventPageRsvp>> listRsvps(String id) async {
    final data = await ApiClient.instance.get('/event-pages/$id/rsvps') as List;
    return data.map((e) => EventPageRsvp.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Tarif courant de publication (pièces) — affiché avant confirmation.
  Future<double> fetchPublishFee() async {
    final data = await ApiClient.instance.get('/event-pages/settings') as Map<String, dynamic>;
    final fee = data['publish_fee_mariage'];
    return fee is num ? fee.toDouble() : double.tryParse('$fee') ?? 0;
  }

  /// Lien de prévisualisation signé (30 min), valable même en brouillon —
  /// voir demande utilisateur : "apres ca on peu previsualier".
  Future<String> fetchPreviewUrl(String id) async {
    final data = await ApiClient.instance.get('/event-pages/$id/preview-url') as Map<String, dynamic>;
    return data['url'] as String;
  }
}
