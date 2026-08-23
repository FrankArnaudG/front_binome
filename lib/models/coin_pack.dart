class CoinPack {
  final String id;
  final String name;
  final int coinAmount;
  final double priceAmount;
  final String priceCurrency;
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
    this.bonusCoins,
    this.imagePath,
  });

  factory CoinPack.fromJson(Map<String, dynamic> json) => CoinPack(
        id: json['id'] as String,
        name: json['name'] as String,
        coinAmount: json['coin_amount'] as int,
        priceAmount: double.parse(json['price_amount'].toString()),
        priceCurrency: json['price_currency'] as String,
        bonusCoins: json['bonus_coins'] as int?,
        imagePath: json['image_path'] as String?,
      );
}
