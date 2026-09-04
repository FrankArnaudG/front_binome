import '../../core/api_client.dart';
import '../../core/local_cache.dart';
import 'roman_photo_story.dart';

/// Une page de l'étagère (voir RomanPhotoController::index côté backend) —
/// volontairement SANS les tomes/pages complets de chaque histoire (voir
/// RomanPhotoStory.volumes, vide ici) : ne charger que ce qu'il faut pour
/// dessiner des couvertures, pas tout le contenu de la bibliothèque d'un
/// coup (voir demande utilisateur, consommation RAM/réseau à la connexion).
class RomanPhotoLibraryPage {
  final List<RomanPhotoStory> items;
  final bool hasMore;

  const RomanPhotoLibraryPage({required this.items, required this.hasMore});
}

class RomanPhotoService {
  RomanPhotoService._();
  static final RomanPhotoService instance = RomanPhotoService._();

  static const _cacheKey = 'cache_roman_photo_library';
  static const _perPage = 15;

  /// Dernière PREMIÈRE page connue (voir LocalCache), sans appel réseau —
  /// permet à RomanPhotoLibraryScreen de s'afficher instantanément, même
  /// principe que GameService.cachedBoxes. Les pages suivantes (scroll) ne
  /// sont jamais mises en cache — nécessitent déjà une connexion.
  Future<List<RomanPhotoStory>?> cachedFirstPage() async {
    final cached = await LocalCache.instance.readJson<List<dynamic>>(_cacheKey);
    if (cached == null) return null;
    return cached.map((e) => RomanPhotoStory.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// [onlyNew] pilote le filtre "Nouveautés" (voir RomanPhotoLibraryScreen) —
  /// résolu côté serveur (voir RomanPhotoController::index `?new=1`), jamais
  /// mis en cache (seule la vue par défaut, page 1 sans filtre, l'est).
  Future<RomanPhotoLibraryPage> fetchLibraryPage(int page, {bool onlyNew = false}) async {
    final cacheable = page == 1 && !onlyNew;
    try {
      final query = {'page': '$page', 'per_page': '$_perPage', if (onlyNew) 'new': '1'};
      final uri = Uri(path: '/roman-photos', queryParameters: query);
      final data = await ApiClient.instance.get(uri.toString()) as Map<String, dynamic>;
      final items = (data['data'] as List).map((e) => RomanPhotoStory.fromJson(e as Map<String, dynamic>)).toList();
      if (cacheable) await LocalCache.instance.writeJson(_cacheKey, data['data']);
      return RomanPhotoLibraryPage(items: items, hasMore: data['next_page_url'] != null);
    } catch (e) {
      if (cacheable) {
        final cached = await cachedFirstPage();
        if (cached != null) return RomanPhotoLibraryPage(items: cached, hasMore: false);
      }
      rethrow;
    }
  }

  /// Détail complet d'UNE histoire (tous ses tomes, toutes leurs pages,
  /// toutes les images teaser) — chargé à la demande à l'ouverture d'une
  /// histoire précise (voir RomanPhotoLibraryScreen._openStory), jamais
  /// pour toute l'étagère d'un coup.
  Future<RomanPhotoStory> fetchStoryDetail(String storyId) async {
    final data = await ApiClient.instance.get('/roman-photos/$storyId') as Map<String, dynamic>;
    return RomanPhotoStory.fromJson(data);
  }

  /// Confirme l'achat d'un tome payant (voir RomanPhotoPurchaseController) —
  /// débite le portefeuille COMMUN de la Box, partagé avec le/la partenaire.
  /// Sans effet (et sans débit) si déjà acheté ou gratuit.
  Future<void> purchaseVolume(String volumeId) async {
    await ApiClient.instance.post('/roman-photos/volumes/$volumeId/purchase');
  }
}
