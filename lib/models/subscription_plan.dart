class SubscriptionPlan {
  final String id;
  final String key;
  // 'solo' (ne couvre que qui paie) ou 'couple' (couvre aussi le binôme de
  // la Box, voir User::hasActiveSubscription côté backend).
  final String scope;
  final String name;
  final String period; // month | year
  final double priceAmountXof;
  final String priceCurrency;

  const SubscriptionPlan({
    required this.id,
    required this.key,
    required this.scope,
    required this.name,
    required this.period,
    required this.priceAmountXof,
    required this.priceCurrency,
  });

  bool get isCouple => scope == 'couple';
  bool get isAnnual => period == 'year';

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) => SubscriptionPlan(
        id: json['id'] as String,
        key: json['key'] as String,
        scope: json['scope'] as String? ?? 'solo',
        name: json['name'] as String,
        period: json['period'] as String,
        priceAmountXof: double.parse(json['price_amount_xof'].toString()),
        priceCurrency: json['price_currency'] as String? ?? 'XOF',
      );
}
