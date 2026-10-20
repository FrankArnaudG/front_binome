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
  // Montant réellement facturé par YengaPay (toujours XOF, voir demande
  // utilisateur : "faire savoir que le paiement se fera en FCFA et donner
  // l'équivalent") — distinct de [priceAmountXof] (malgré son nom, ce champ
  // est déjà converti dans [priceCurrency]) quand celle-ci n'est pas XOF.
  final double priceAmountXofNative;
  // Avantage éligible pour CET utilisateur sur CE plan, à l'instant de
  // l'appel (voir demande utilisateur, module de promotions : "l'avantage
  // doit apparaître à l'utilisateur avant qu'il paie") — simple aperçu,
  // re-résolu (et figé) pour de vrai côté serveur à la création de la
  // commande (voir SubscriptionService.createOrder).
  final PlanPromotion? promotion;

  const SubscriptionPlan({
    required this.id,
    required this.key,
    required this.scope,
    required this.name,
    required this.period,
    required this.priceAmountXof,
    required this.priceCurrency,
    required this.priceAmountXofNative,
    this.promotion,
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
        // Absent quand ce plan est imbriqué dans SubscriptionOrder/
        // Subscription (relation chargée brute côté backend, sans passer
        // par SubscriptionPlanController::index qui seul ajoute ce champ) :
        // repli sur price_amount_xof, déjà natif XOF dans ce contexte (voir
        // le même repli et sa justification dans CoinPack.fromJson).
        priceAmountXofNative: json['price_amount_xof_native'] != null
            ? double.parse(json['price_amount_xof_native'].toString())
            : double.parse(json['price_amount_xof'].toString()),
        promotion: json['promotion'] != null ? PlanPromotion.fromJson(json['promotion'] as Map<String, dynamic>) : null,
      );
}

/// Voir SubscriptionPlan.promotion.
class PlanPromotion {
  final String name;
  final String advantageType; // extra_days | percent_discount
  final double advantageValue;

  const PlanPromotion({required this.name, required this.advantageType, required this.advantageValue});

  bool get isExtraDays => advantageType == 'extra_days';

  factory PlanPromotion.fromJson(Map<String, dynamic> json) => PlanPromotion(
        name: json['name'] as String,
        advantageType: json['advantage_type'] as String,
        advantageValue: double.parse(json['advantage_value'].toString()),
      );
}
