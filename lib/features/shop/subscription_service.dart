import '../../core/api_client.dart';
import '../../models/subscription.dart';
import '../../models/subscription_order.dart';
import '../../models/subscription_plan.dart';

/// Appels API pour l'Abonnement — alternative au système de pièces (voir
/// ShopService), même esprit : pas d'état partagé ici, seul le statut
/// "abonné actuellement" (géré par [SubscriptionStatusNotifier]) a besoin
/// d'être réactif entre écrans.
class SubscriptionService {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  Future<List<SubscriptionPlan>> fetchPlans() async {
    final data = await ApiClient.instance.get('/subscription-plans') as List;
    return data.map((e) => SubscriptionPlan.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<SubscriptionOrder> createOrder({required String subscriptionPlanId, required String provider}) async {
    final data = await ApiClient.instance.post('/subscription-orders', body: {
      'subscription_plan_id': subscriptionPlanId,
      'provider': provider,
    }) as Map<String, dynamic>;
    return SubscriptionOrder.fromJson(data);
  }

  Future<List<SubscriptionOrder>> fetchOrders({int page = 1, int limit = 20}) async {
    final data = await ApiClient.instance.get('/subscription-orders?page=$page&per_page=$limit') as Map<String, dynamic>;
    final items = data['data'] as List;
    return items.map((e) => SubscriptionOrder.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// L'abonnement actif de l'utilisateur courant, ou `null`.
  Future<Subscription?> fetchMySubscription() async {
    final data = await ApiClient.instance.get('/subscription');
    if (data == null) return null;
    return Subscription.fromJson(data as Map<String, dynamic>);
  }
}
