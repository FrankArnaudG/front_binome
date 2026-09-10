import 'pictionary_session.dart';

/// Doodle envoyé au binôme (voir demande utilisateur : composer un dessin
/// sur son écran, l'envoyer, qu'il s'affiche en plein écran chez l'autre) —
/// réutilise [PictionaryStroke] tel quel, même forme de trait (points
/// normalisés 0..1, couleur, épaisseur), même si ce n'est pas un jeu.
class Doodle {
  final String id;
  final String boxId;
  final String fromUserId;
  final String toUserId;
  final List<PictionaryStroke> strokes;
  final DateTime? viewedAt;
  final DateTime createdAt;

  const Doodle({
    required this.id,
    required this.boxId,
    required this.fromUserId,
    required this.toUserId,
    required this.strokes,
    this.viewedAt,
    required this.createdAt,
  });

  factory Doodle.fromJson(Map<String, dynamic> json) => Doodle(
        id: json['id'] as String,
        boxId: json['box_id'] as String,
        fromUserId: json['from_user_id'] as String,
        toUserId: json['to_user_id'] as String,
        strokes: (json['strokes'] as List).map((e) => PictionaryStroke.fromJson(e as Map<String, dynamic>)).toList(),
        viewedAt: json['viewed_at'] != null ? DateTime.parse(json['viewed_at'] as String) : null,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
