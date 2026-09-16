import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/coin_purchase_order.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_chip.dart';
import 'currency_service.dart';
import 'shop_service.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  late Future<List<CoinPurchaseOrder>> _future;

  @override
  void initState() {
    super.initState();
    _future = ShopService.instance.fetchOrders();
  }

  Future<void> _refresh() async {
    final future = ShopService.instance.fetchOrders();
    setState(() { _future = future; });
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blush,
      appBar: AppBar(
        backgroundColor: AppColors.blush,
        elevation: 0,
        foregroundColor: AppColors.textOnBlush,
        title: Text('Mes commandes', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: AppColors.textOnBlush)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<List<CoinPurchaseOrder>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return ListView(
                  children: const [
                    EmptyState(icon: Icons.wifi_off_rounded, message: 'Impossible de charger tes commandes.'),
                  ],
                );
              }
              final orders = snapshot.data ?? [];
              if (orders.isEmpty) {
                return ListView(
                  children: const [
                    EmptyState(icon: Icons.receipt_long_rounded, message: 'Aucune commande pour le moment.'),
                  ],
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _OrderTile(order: orders[index]),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  final CoinPurchaseOrder order;

  const _OrderTile({required this.order});

  Color get _statusColor => switch (order.status) {
        'paid' => Colors.green,
        'pending' => AppColors.accent,
        'failed' || 'cancelled' => Colors.redAccent,
        _ => AppColors.textOnBlushMuted,
      };

  String get _statusLabel => switch (order.status) {
        'paid' => 'Payée',
        'pending' => 'En attente',
        'failed' => 'Échouée',
        'cancelled' => 'Annulée',
        _ => order.status,
      };

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.coinPack?.name ?? 'Pack de Tokens',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textOnBlush),
                ),
                const SizedBox(height: 4),
                Text(
                  '${order.coinAmount} Tokens • ${order.priceAmount.toStringAsFixed(0)} ${currencySymbol(order.priceCurrency)}',
                  style: GoogleFonts.nunito(fontSize: 13, color: AppColors.textOnBlushMuted),
                ),
              ],
            ),
          ),
          StatusChip(label: _statusLabel, color: _statusColor),
        ],
      ),
    );
  }
}
