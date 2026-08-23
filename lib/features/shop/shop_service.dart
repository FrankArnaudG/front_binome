import '../../core/api_client.dart';
import '../../core/local_cache.dart';
import '../../models/coin_pack.dart';
import '../../models/coin_purchase_order.dart';
import '../../models/gift.dart';
import '../../models/send.dart';

/// Appels API pour la Boutique (pièces + cadeaux) — même esprit que
/// ContentService : pas d'état partagé ici, seul le solde (ailleurs géré
/// par [WalletBalanceNotifier]) a besoin d'être réactif entre écrans.
class ShopService {
  ShopService._();
  static final ShopService instance = ShopService._();

  static const _cacheKey = 'cache_coin_packs';

  /// Derniers packs connus (voir LocalCache), sans appel réseau — permet à
  /// ShopScreen d'afficher instantanément quelque chose au lancement plutôt
  /// qu'un loader, avant même de tenter le réseau. `null` si rien n'a jamais
  /// été mis en cache (tout premier lancement).
  Future<List<CoinPack>?> cachedCoinPacks() async {
    final cached = await LocalCache.instance.readJson<List<dynamic>>(_cacheKey);
    if (cached == null) return null;
    return cached.map((entry) => CoinPack.fromJson(entry as Map<String, dynamic>)).toList();
  }

  /// Mis en cache (voir LocalCache) pour rester consultable hors ligne —
  /// en cas d'échec réseau, on retombe sur la dernière liste connue plutôt
  /// que de laisser l'écran vide.
  Future<List<CoinPack>> fetchCoinPacks() async {
    try {
      final data = await ApiClient.instance.get('/coin-packs') as List;
      await LocalCache.instance.writeJson(_cacheKey, data);
      return data.map((e) => CoinPack.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      final cached = await cachedCoinPacks();
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<CoinPurchaseOrder> createOrder({required String coinPackId, required String provider}) async {
    final data = await ApiClient.instance.post('/coin-purchase-orders', body: {
      'coin_pack_id': coinPackId,
      'provider': provider,
    }) as Map<String, dynamic>;
    return CoinPurchaseOrder.fromJson(data);
  }

  Future<List<CoinPurchaseOrder>> fetchOrders({int page = 1, int limit = 20}) async {
    final data = await ApiClient.instance.get('/coin-purchase-orders?page=$page&per_page=$limit') as Map<String, dynamic>;
    final items = data['data'] as List;
    return items.map((e) => CoinPurchaseOrder.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Gift>> fetchGifts() async {
    final data = await ApiClient.instance.get('/gifts') as List;
    return data.map((e) => Gift.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Send> sendGift(String giftId, {String? message}) async {
    final data = await ApiClient.instance.post('/gifts/$giftId/send', body: {
      if (message != null && message.isNotEmpty) 'message': message,
    }) as Map<String, dynamic>;
    return Send.fromJson(data);
  }
}
