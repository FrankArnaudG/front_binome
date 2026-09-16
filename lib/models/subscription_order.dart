import 'subscription_plan.dart';

class SubscriptionOrder {
  final String id;
  final double priceAmount;
  final String priceCurrency;
  final String provider; // orange_money | wave | manual | yengapay
  final String status; // pending | paid | failed | cancelled
  final DateTime? paidAt;
  final DateTime createdAt;
  final SubscriptionPlan? plan;
  // URL de paiement LigdiCash (voir CoinPurchaseOrder.paymentUrl — même
  // logique, absente/null si LigdiCash n'est pas joignable/configuré).
  final String? paymentUrl;

  const SubscriptionOrder({
    required this.id,
    required this.priceAmount,
    required this.priceCurrency,
    required this.provider,
    required this.status,
    this.paidAt,
    required this.createdAt,
    this.plan,
    this.paymentUrl,
  });

  factory SubscriptionOrder.fromJson(Map<String, dynamic> json) => SubscriptionOrder(
        id: json['id'] as String,
        priceAmount: double.parse(json['price_amount'].toString()),
        priceCurrency: json['price_currency'] as String,
        provider: json['provider'] as String,
        status: json['status'] as String,
        paidAt: json['paid_at'] != null ? DateTime.parse(json['paid_at'] as String) : null,
        createdAt: DateTime.parse(json['created_at'] as String),
        plan: json['plan'] != null ? SubscriptionPlan.fromJson(json['plan'] as Map<String, dynamic>) : null,
        paymentUrl: json['payment_url'] as String?,
      );
}
