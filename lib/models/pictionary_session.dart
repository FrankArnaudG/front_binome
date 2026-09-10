/// Un segment de trait dessiné à main levée — coordonnées brutes (voir
/// [PictionaryCanvas]) réutilisées par "Mots & dessins" (Doodle, partage
/// asynchrone d'un dessin unique) pour sérialiser le tracé composé par
/// l'auteur avant envoi.
class PictionaryStroke {
  final List<List<double>> points;
  final String color;
  final double width;

  const PictionaryStroke({required this.points, required this.color, required this.width});

  factory PictionaryStroke.fromJson(Map<String, dynamic> json) => PictionaryStroke(
        points: (json['points'] as List).map((p) => (p as List).map((e) => (e as num).toDouble()).toList()).toList(),
        color: json['color'] as String,
        width: (json['width'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'points': points, 'color': color, 'width': width};
}
