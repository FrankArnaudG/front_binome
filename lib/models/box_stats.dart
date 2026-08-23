/// "Score de complicité" du couple — statistiques ludiques calculées
/// côté serveur à partir des échanges de la Box (voir Onglet Jeux).
class BoxStats {
  final int daysTogether;
  final int slidesSent;
  final int giftsSent;
  final int heartbeatsSent;
  final int totalSends;

  /// `null` durant la première semaine du couple, sauf si le score dépasse
  /// déjà 15 % avant ça (voir BoxController::stats) — un score qui plafonne
  /// autour de 2 % dès le jumelage se lit comme un jugement plutôt qu'un
  /// point de départ, donc masqué le temps que l'activité s'installe.
  final int? complicityScore;

  const BoxStats({
    required this.daysTogether,
    required this.slidesSent,
    required this.giftsSent,
    required this.heartbeatsSent,
    required this.totalSends,
    required this.complicityScore,
  });

  factory BoxStats.fromJson(Map<String, dynamic> json) => BoxStats(
        daysTogether: json['days_together'] as int? ?? 0,
        slidesSent: json['slides_sent'] as int? ?? 0,
        giftsSent: json['gifts_sent'] as int? ?? 0,
        heartbeatsSent: json['heartbeats_sent'] as int? ?? 0,
        totalSends: json['total_sends'] as int? ?? 0,
        complicityScore: json['complicity_score'] as int?,
      );
}
