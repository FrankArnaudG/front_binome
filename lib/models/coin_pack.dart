class CoinPack {
  final String id;
  final String name;
  final int coinAmount;
  final double priceAmount;
  final String priceCurrency;
  // Montant réellement facturé par YengaPay (toujours XOF, voir demande
  // utilisateur : "faire savoir que le paiement se fera en FCFA et donner
  // l'équivalent") — distinct de [priceAmount] quand [priceCurrency] n'est
  // pas déjà XOF.
  final double priceAmountXofNative;
  // Nombre brut (pas de texte pré-formaté) — le libellé complet
  // ("+{n} offertes"/"+{n} free"...) se compose dans ShopScreen avec la
  // langue courante, contrairement à `name` qui reste tel quel dans toutes
  // les langues.
  final int? bonusCoins;
  final String? imagePath;

  const CoinPack({
    required this.id,
    required this.name,
    required this.coinAmount,
    required this.priceAmount,
    required this.priceCurrency,
    required this.priceAmountXofNative,
    this.bonusCoins,
    this.imagePath,
  });

  factory CoinPack.fromJson(Map<String, dynamic> json) => CoinPack(
        id: json['id'] as String,
        name: json['name'] as String,
        coinAmount: json['coin_amount'] as int,
        priceAmount: double.parse(json['price_amount'].toString()),
        priceCurrency: json['price_currency'] as String,
        // Absent quand ce CoinPack est imbriqué dans une réponse de
        // commande (CoinPurchaseOrderController::store charge la relation
        // coinPack brute, sans passer par CoinPackController::index qui est
        // le seul endroit ajoutant ce champ) : repli sur price_amount, déjà
        // la valeur XOF native dans ce contexte (jamais convertie). Sans ce
        // repli, FormatException sur `null` ici plantait silencieusement le
        // parsing de la commande fraîchement créée (catch générique côté
        // _payViaYengaPay masquait ce vrai bug derrière un faux message
        // réseau — voir demande utilisateur).
        priceAmountXofNative: json['price_amount_xof_native'] != null
            ? double.parse(json['price_amount_xof_native'].toString())
            : double.parse(json['price_amount'].toString()),
        bonusCoins: json['bonus_coins'] as int?,
        imagePath: json['image_path'] as String?,
      );
}
