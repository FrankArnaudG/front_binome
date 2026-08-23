/// Son partagé du couple — voir BoxSoundController côté backend (plafonné à
/// 5 par Box, diffusé en direct via l'événement SoundPlayed).
class BoxSound {
  final String id;
  final String url;
  final String uploadedBy;
  final DateTime createdAt;

  const BoxSound({required this.id, required this.url, required this.uploadedBy, required this.createdAt});

  factory BoxSound.fromJson(Map<String, dynamic> json) => BoxSound(
        id: json['id'] as String,
        url: json['url'] as String,
        uploadedBy: json['uploaded_by'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
