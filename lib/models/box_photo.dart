/// Photo du "Jardin secret" — voir BoxPhotoController côté backend
/// (recompressée à l'envoi, plafonnée à 100 par Box).
class BoxPhoto {
  final String id;
  final String url;
  final String uploadedBy;
  final DateTime createdAt;

  const BoxPhoto({required this.id, required this.url, required this.uploadedBy, required this.createdAt});

  factory BoxPhoto.fromJson(Map<String, dynamic> json) => BoxPhoto(
        id: json['id'] as String,
        url: json['url'] as String,
        uploadedBy: json['uploaded_by'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
