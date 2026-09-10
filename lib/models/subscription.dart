import 'subscription_plan.dart';

class Subscription {
  final String id;
  final SubscriptionPlan? plan;
  final DateTime startedAt;
  final DateTime expiresAt;

  const Subscription({
    required this.id,
    this.plan,
    required this.startedAt,
    required this.expiresAt,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
        id: json['id'] as String,
        plan: json['plan'] != null ? SubscriptionPlan.fromJson(json['plan'] as Map<String, dynamic>) : null,
        startedAt: DateTime.parse(json['started_at'] as String),
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );
}
