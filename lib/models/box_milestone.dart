/// Jalon important du couple (anniversaire, date de rencontre, mariage...)
/// — voir CoupleProfileScreen. Libellé libre, pas de type figé côté
/// backend (voir BoxMilestoneController).
class BoxMilestone {
  final String id;
  final String label;
  final DateTime date;

  const BoxMilestone({required this.id, required this.label, required this.date});

  factory BoxMilestone.fromJson(Map<String, dynamic> json) => BoxMilestone(
        id: json['id'] as String,
        label: json['label'] as String,
        date: DateTime.parse(json['date'] as String),
      );
}
