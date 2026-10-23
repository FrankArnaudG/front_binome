import 'dart:io';

import '../../core/api_client.dart';
import '../../core/api_config.dart';
import '../../core/local_cache.dart';
import 'models/invitation_models.dart';

/// Appels API du module "Invitations numériques" — même esprit que
/// RomanPhotoService/PhotoVaultService : pas d'état partagé ici, chaque
/// écran recharge ce dont il a besoin.
class InvitationService {
  InvitationService._();
  static final InvitationService instance = InvitationService._();

  static const _templatesCacheKey = 'cache_invitation_templates';
  static const _invitationsCacheKey = 'cache_my_invitations';

  /// Dernière liste connue, sans appel réseau (voir RomanPhotoService.cachedFirstPage)
  /// — permet au catalogue de s'afficher instantanément au lieu d'un loader
  /// bloquant (voir demande utilisateur : "les loaders tournent longtemps").
  Future<List<InvitationTemplate>?> cachedTemplates() async {
    final cached = await LocalCache.instance.readJson<List<dynamic>>(_templatesCacheKey);
    if (cached == null) return null;
    return cached.map((e) => InvitationTemplate.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<List<Invitation>?> cachedMyInvitations() async {
    final cached = await LocalCache.instance.readJson<List<dynamic>>(_invitationsCacheKey);
    if (cached == null) return null;
    return cached.map((e) => Invitation.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<List<InvitationTemplate>> fetchTemplates() async {
    final data = await ApiClient.instance.get('/invitation-templates') as List;
    await LocalCache.instance.writeJson(_templatesCacheKey, data);
    return data.map((e) => InvitationTemplate.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<List<Invitation>> fetchMyInvitations() async {
    final data = await ApiClient.instance.get('/invitations') as List;
    await LocalCache.instance.writeJson(_invitationsCacheKey, data);
    return data.map((e) => Invitation.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  /// Bibliothèque de textes prédéfinis pour le bloc "message romantique"
  /// (voir RomanticMessageController) — jamais mis en cache local, c'est un
  /// contenu éditorial statique, pas une donnée propre à l'utilisateur.
  Future<(List<RomanticCategory>, List<RomanticMessage>)> fetchRomanticMessages() async {
    final data = await ApiClient.instance.get('/invitations/romantic-messages') as Map<String, dynamic>;
    final categories = (data['categories'] as List).map((e) => RomanticCategory.fromJson((e as Map).cast<String, dynamic>())).toList();
    final messages = (data['messages'] as List).map((e) => RomanticMessage.fromJson((e as Map).cast<String, dynamic>())).toList();
    return (categories, messages);
  }

  Future<Invitation> fetchInvitation(String id) async {
    final data = await ApiClient.instance.get('/invitations/$id') as Map<String, dynamic>;
    return Invitation.fromJson(data);
  }

  Future<Invitation> createInvitation(String templateId) async {
    final data = await ApiClient.instance.post('/invitations', body: {'invitation_template_id': templateId}) as Map<String, dynamic>;
    return Invitation.fromJson(data);
  }

  Future<Invitation> updateInvitation(String id, Map<String, dynamic> fields) async {
    final data = await ApiClient.instance.put('/invitations/$id', body: fields) as Map<String, dynamic>;
    return Invitation.fromJson(data);
  }

  Future<void> deleteInvitation(String id) async {
    await ApiClient.instance.delete('/invitations/$id');
  }

  Future<InvitationCeremony> addCeremony(String invitationId, Map<String, dynamic> fields) async {
    final data = await ApiClient.instance.post('/invitations/$invitationId/ceremonies', body: fields) as Map<String, dynamic>;
    return InvitationCeremony.fromJson(data);
  }

  Future<InvitationCeremony> updateCeremony(String invitationId, String ceremonyId, Map<String, dynamic> fields) async {
    final data = await ApiClient.instance.put('/invitations/$invitationId/ceremonies/$ceremonyId', body: fields) as Map<String, dynamic>;
    return InvitationCeremony.fromJson(data);
  }

  Future<void> deleteCeremony(String invitationId, String ceremonyId) async {
    await ApiClient.instance.delete('/invitations/$invitationId/ceremonies/$ceremonyId');
  }

  Future<void> reorderCeremonies(String invitationId, List<String> orderedIds) async {
    await ApiClient.instance.post('/invitations/$invitationId/ceremonies/reorder', body: {'ceremony_ids': orderedIds});
  }

  Future<InvitationMedia> uploadMedia(
    String invitationId,
    File file, {
    required String blockKey,
    String? caption,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final data = await ApiClient.instance.postMultipart(
      '/invitations/$invitationId/media',
      fieldName: 'photo',
      file: file,
      fields: {'block_key': blockKey, if (caption != null) 'caption': caption},
      onSendProgress: onSendProgress,
    ) as Map<String, dynamic>;
    return InvitationMedia.fromJson(data);
  }

  Future<void> deleteMedia(String invitationId, String mediaId) async {
    await ApiClient.instance.delete('/invitations/$invitationId/media/$mediaId');
  }

  /// Lance la génération d'un lien de prévisualisation (jeton signé, 30 min,
  /// voir cahier des charges §8) — à ouvrir dans le navigateur externe via
  /// url_launcher, jamais dans une WebView interne.
  Future<String> requestPreviewUrl(String invitationId) async {
    final data = await ApiClient.instance.post('/invitations/$invitationId/preview') as Map<String, dynamic>;
    return data['preview_url'] as String;
  }

  /// Peut lever [ApiException] avec un message listant les champs
  /// manquants (voir InvitationPublishController::publish) — à afficher
  /// tel quel plutôt que de revalider côté client, pour ne jamais diverger
  /// des règles serveur. Renvoie `(invitation, public_url)` — l'URL n'est
  /// construite QUE côté serveur (voir url('/i/'.$invitation->slug)).
  Future<(Invitation, String)> publish(String invitationId) async {
    final data = await ApiClient.instance.post('/invitations/$invitationId/publish') as Map<String, dynamic>;
    return (Invitation.fromJson((data['invitation'] as Map).cast<String, dynamic>()), data['public_url'] as String);
  }

  /// Reconstruit l'URL publique d'une invitation DÉJÀ publiée (slug connu),
  /// même hôte que l'API (voir ApiConfig.baseUrl) sans son suffixe `/api` —
  /// évite un aller-retour réseau juste pour réafficher un lien déjà généré.
  String publicUrlFor(String slug) {
    final uri = Uri.parse(ApiConfig.baseUrl);
    return '${uri.scheme}://${uri.authority}/i/$slug';
  }

  Future<Invitation> suspend(String invitationId) async {
    final data = await ApiClient.instance.post('/invitations/$invitationId/suspend') as Map<String, dynamic>;
    return Invitation.fromJson(data);
  }

  Future<Invitation> resume(String invitationId) async {
    final data = await ApiClient.instance.post('/invitations/$invitationId/resume') as Map<String, dynamic>;
    return Invitation.fromJson(data);
  }

  Future<Invitation> archive(String invitationId) async {
    final data = await ApiClient.instance.post('/invitations/$invitationId/archive') as Map<String, dynamic>;
    return Invitation.fromJson(data);
  }
}
