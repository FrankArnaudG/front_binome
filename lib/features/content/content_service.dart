import '../../core/api_client.dart';
import '../../core/local_cache.dart';
import '../../models/pack.dart';
import '../../models/pack_category.dart';
import '../../models/replies_page.dart';
import '../../models/send.dart';

/// Appels API pour les Packs/Slides/Envois ("principe TikTok" : parcourir
/// un pack, choisir une slide, l'envoyer). Pas d'état partagé nécessaire
/// (contrairement à BoxService) — chaque écran refetch ce dont il a besoin.
class ContentService {
  ContentService._();
  static final ContentService instance = ContentService._();

  Future<List<Pack>> fetchPacks() async {
    final data = await ApiClient.instance.get('/packs') as List;
    return data.map((e) => Pack.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Pack> fetchPack(String id) async {
    final data = await ApiClient.instance.get('/packs/$id') as Map<String, dynamic>;
    return Pack.fromJson(data);
  }

  static const _categoriesCacheKey = 'cache_pack_categories';

  // Copie en mémoire de la dernière liste chargée — permet [categoryLabelSync]
  // ci-dessous de résoudre un libellé de façon synchrone (voir
  // SlideVisualCard, un StatelessWidget qui ne peut pas attendre un fetch
  // réseau dans build()) ; `null` tant qu'aucun écran n'a encore appelé
  // [fetchPackCategories] cette session.
  List<PackCategory>? _memoryCategories;

  /// Gérées depuis l'admin (voir PackCategoryController côté backend), avec
  /// leurs 12 traductions déjà incluses — mises en cache comme les packs
  /// pour un premier affichage instantané.
  Future<List<PackCategory>> fetchPackCategories() async {
    try {
      final data = await ApiClient.instance.get('/pack-categories') as List;
      await LocalCache.instance.writeJson(_categoriesCacheKey, data);
      final categories = data.map((e) => PackCategory.fromJson(e as Map<String, dynamic>)).toList();
      _memoryCategories = categories;
      return categories;
    } catch (e) {
      final cached = await LocalCache.instance.readJson<List<dynamic>>(_categoriesCacheKey);
      if (cached != null) {
        final categories = cached.map((entry) => PackCategory.fromJson(entry as Map<String, dynamic>)).toList();
        _memoryCategories = categories;
        return categories;
      }
      rethrow;
    }
  }

  /// Résolution synchrone d'un libellé de catégorie, depuis la dernière
  /// liste chargée en mémoire — `null` si [fetchPackCategories] n'a encore
  /// jamais été appelé cette session (l'appelant retombe alors sur le slug
  /// brut, voir SlideVisualCard).
  String? categoryLabelSync(String slug, String localeCode) {
    for (final category in _memoryCategories ?? const <PackCategory>[]) {
      if (category.slug == slug) return category.labelFor(localeCode);
    }
    return null;
  }

  /// Envoie le pack entier (toutes ses slides) au/à la partenaire, pour un
  /// seul prix (Pack.sendCoinPrice) — on ne choisit pas une carte à envoyer,
  /// on envoie le poème complet.
  Future<Send> sendPack(String packId, {String? message, String? replyToSendId}) async {
    final data = await ApiClient.instance.post('/packs/$packId/send', body: {
      if (message != null && message.isNotEmpty) 'message': message,
      if (replyToSendId != null) 'reply_to_send_id': replyToSendId,
    }) as Map<String, dynamic>;
    return Send.fromJson(data);
  }

  /// Ajoute une réaction à un envoi — cumulable : chaque appel ajoute une
  /// nouvelle réaction sans remplacer les précédentes. Retourne l'envoi mis
  /// à jour avec toutes ses réactions.
  Future<Send> reactToSend(String sendId, String emoji) async {
    final data = await ApiClient.instance.post('/sends/$sendId/reactions', body: {
      'emoji': emoji,
    }) as Map<String, dynamic>;
    return Send.fromJson(data);
  }

  /// Envoie un NOUVEAU message composé uniquement d'émojis, en réponse à un
  /// envoi — depuis la barre de composition toujours visible (voir
  /// EmojiComposeBar). Contrairement à [reactToSend], ceci crée sa propre
  /// capsule dans le Carnet de bord au lieu de s'accrocher à la bulle
  /// existante ; gratuit, comme les réactions.
  Future<Send> sendEmojiReply(String sendId, String emojis) async {
    final data = await ApiClient.instance.post('/sends/$sendId/emoji-reply', body: {
      'emojis': emojis,
    }) as Map<String, dynamic>;
    return Send.fromJson(data);
  }

  /// Envoie un message texte libre en réponse à un envoi — transforme un
  /// fil ponctuel (ex. carte-question "À nous deux") en vraie discussion,
  /// des deux côtés, sans limite de nombre de messages (voir
  /// GameCardThreadScreen).
  Future<Send> sendTextReply(String sendId, String text) async {
    final data = await ApiClient.instance.post('/sends/$sendId/reply', body: {
      'text': text,
    }) as Map<String, dynamic>;
    return Send.fromJson(data);
  }

  /// Dernière page (les plus récentes) du fil de discussion connue pour cet
  /// envoi (voir LocalCache), sans appel réseau — permet à SlideDetailScreen
  /// de l'afficher instantanément au lieu d'un fil vide le temps du fetch.
  /// `null` si jamais mis en cache.
  Future<RepliesPage?> cachedReplies(String sendId) async {
    final cached = await LocalCache.instance.readJson<Map<String, dynamic>>('cache_replies_$sendId');
    if (cached == null) return null;
    return RepliesPage.fromJson(cached);
  }

  /// Le fil de discussion d'un envoi — les réponses directes (poème ou
  /// message émoji) qui pointent dessus, les plus récentes d'abord.
  /// Permet à SlideDetailScreen d'afficher une vraie bulle de discussion
  /// sous la carte plutôt que des capsules dispersées dans le Carnet de
  /// bord. Paginé (voir SendController::replies côté backend) — un fil peut
  /// grossir indéfiniment, [beforeId] charge la page plus ancienne
  /// (l'id de la plus ancienne réponse déjà chargée). Seule la toute
  /// première page (sans [beforeId]) est mise en cache (voir LocalCache) —
  /// remonter plus loin dans l'historique nécessite déjà une connexion.
  Future<RepliesPage> fetchReplies(String sendId, {String? beforeId, int limit = 30}) async {
    final query = {
      'limit': '$limit',
      if (beforeId != null) 'before': beforeId,
    };
    final uri = Uri(path: '/sends/$sendId/replies', queryParameters: query);
    final cacheKey = 'cache_replies_$sendId';

    try {
      final data = await ApiClient.instance.get(uri.toString()) as Map<String, dynamic>;
      final page = RepliesPage.fromJson(data);
      if (beforeId == null) await LocalCache.instance.writeJson(cacheKey, data);
      return page;
    } catch (e) {
      if (beforeId == null) {
        final cached = await LocalCache.instance.readJson<Map<String, dynamic>>(cacheKey);
        if (cached != null) return RepliesPage.fromJson(cached);
      }
      rethrow;
    }
  }

  /// Un envoi précis par id — sert l'ouverture directe depuis une
  /// notification push (voir PushNotificationOpenScreen) plutôt que de
  /// passer par la liste paginée.
  Future<Send> fetchSend(String sendId) async {
    final data = await ApiClient.instance.get('/sends/$sendId') as Map<String, dynamic>;
    return Send.fromJson(data);
  }

  /// Dernière page par défaut connue (voir LocalCache), sans appel réseau —
  /// permet à TimelineScreen d'afficher instantanément quelque chose au
  /// lancement plutôt qu'un loader, avant même de tenter le réseau. `null`
  /// si rien n'a jamais été mis en cache (tout premier lancement).
  Future<List<Send>?> cachedSends() async {
    final cached = await LocalCache.instance.readJson<List<dynamic>>('cache_sends_default');
    if (cached == null) return null;
    return cached.map((entry) => Send.fromJson(entry as Map<String, dynamic>)).toList();
  }

  /// Mis en cache (voir LocalCache) pour rester consultable hors ligne —
  /// uniquement la vue par défaut (première page, aucun filtre) : filtrer
  /// ou paginer plus loin nécessite déjà une connexion, pas la peine de
  /// mettre ces variantes en cache pour un cas d'usage marginal.
  Future<List<Send>> fetchSends({int page = 1, int limit = 20, bool favoriteOnly = false, String? type}) async {
    final query = {
      'page': '$page',
      'per_page': '$limit',
      if (favoriteOnly) 'favorite': '1',
      if (type != null) 'type': type,
    };
    final uri = Uri(path: '/sends', queryParameters: query);
    final cacheable = page == 1 && !favoriteOnly && type == null;
    const cacheKey = 'cache_sends_default';

    try {
      final data = await ApiClient.instance.get(uri.toString()) as Map<String, dynamic>;
      final items = data['data'] as List;
      if (cacheable) await LocalCache.instance.writeJson(cacheKey, items);
      return items.map((e) => Send.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      if (cacheable) {
        final cached = await LocalCache.instance.readJson<List<dynamic>>(cacheKey);
        if (cached != null) {
          return cached.map((entry) => Send.fromJson(entry as Map<String, dynamic>)).toList();
        }
      }
      rethrow;
    }
  }

  Future<Send> markSeen(String sendId) async {
    final data = await ApiClient.instance.put('/sends/$sendId/seen') as Map<String, dynamic>;
    return Send.fromJson(data);
  }

  Future<Send> markDelivered(String sendId) async {
    final data = await ApiClient.instance.put('/sends/$sendId/delivered') as Map<String, dynamic>;
    return Send.fromJson(data);
  }

  /// Rattrapage appelé à la (re)connexion (voir DeliveryAckService) — marque
  /// "reçu" d'un coup tout ce qui m'était destiné et encore "sent", plutôt
  /// qu'un accusé par envoi depuis un gestionnaire de notification en
  /// arrière-plan (voir la doc de DeliveryAckService pour ce choix).
  Future<void> markPendingDelivered() async {
    await ApiClient.instance.post('/sends/mark-pending-delivered');
  }

  Future<Send> toggleFavorite(String sendId) async {
    final data = await ApiClient.instance.put('/sends/$sendId/favorite') as Map<String, dynamic>;
    return Send.fromJson(data);
  }

  /// "Faire battre le cœur de son/sa partenaire" — sans [message], le
  /// serveur en choisit un aléatoirement dans le catalogue admin ; avec,
  /// c'est le petit mot personnalisé de l'appui long qui est envoyé.
  /// [replyToSendId] : répondre à un envoi précis (voir SlideDetailScreen)
  /// par un battement de cœur plutôt qu'un poème/émoji.
  Future<Send> sendHeartbeat({String? message, String? replyToSendId}) async {
    final trimmed = message?.trim();
    final body = <String, dynamic>{
      if (trimmed != null && trimmed.isNotEmpty) 'message': trimmed,
      if (replyToSendId != null) 'reply_to_send_id': replyToSendId,
    };
    final data = await ApiClient.instance.post(
      '/heartbeat',
      body: body.isNotEmpty ? body : null,
    ) as Map<String, dynamic>;
    return Send.fromJson(data);
  }

  /// Prix courant en pièces d'un battement de cœur, réglable depuis l'espace
  /// admin — affiché sur la tuile du Dashboard avant l'envoi.
  Future<int> fetchHeartbeatPrice() async {
    final data = await ApiClient.instance.get('/heartbeat/price') as Map<String, dynamic>;
    return data['coin_cost'] as int;
  }
}
