import 'coin_pack.dart';

class CoinPurchaseOrder {
  final String id;
  final int coinAmount;
  final double priceAmount;
  final String priceCurrency;
  final String provider; // orange_money | wave | manual
  final String status; // pending | paid | failed | cancelled
  final DateTime? paidAt;
  final DateTime createdAt;
  final CoinPack? coinPack;

  const CoinPurchaseOrder({
    required this.id,
    required this.coinAmount,
    required this.priceAmount,
    required this.priceCurrency,
    required this.provider,
    required this.status,
    this.paidAt,
    required this.createdAt,
    this.coinPack,
  });

  factory CoinPurchaseOrder.fromJson(Map<String, dynamic> json) => CoinPurchaseOrder(
        id: json['id'] as String,
        coinAmount: json['coin_amount'] as int,
        priceAmount: double.parse(json['price_amount'].toString()),
        priceCurrency: json['price_currency'] as String,
        provider: json['provider'] as String,
        status: json['status'] as String,
        paidAt: json['paid_at'] != null ? DateTime.parse(json['paid_at'] as String) : null,
        createdAt: DateTime.parse(json['created_at'] as String),
        coinPack: json['coin_pack'] != null ? CoinPack.fromJson(json['coin_pack'] as Map<String, dynamic>) : null,
      );
}
