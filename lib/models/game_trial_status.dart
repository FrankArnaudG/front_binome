/// Essai gratuit du mode à distance pour la Box courante (voir
/// GameTrialController côté backend) — [hasTrial] à `false` si aucun groupe
/// n'a jamais été accordé à cette Box (ex: Box créée avant la mise en place
/// de la fonctionnalité, ou aucune offre active au moment de sa création).
class GameTrialStatus {
  final bool hasTrial;
  final int secondsRemaining;
  final bool depleted;

  const GameTrialStatus({
    required this.hasTrial,
    required this.secondsRemaining,
    required this.depleted,
  });

  factory GameTrialStatus.fromJson(Map<String, dynamic> json) {
    return GameTrialStatus(
      hasTrial: json['has_trial'] as bool? ?? false,
      secondsRemaining: json['seconds_remaining'] as int? ?? 0,
      depleted: json['depleted'] as bool? ?? false,
    );
  }
}
