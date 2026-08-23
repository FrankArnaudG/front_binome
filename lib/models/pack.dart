import 'slide.dart';

/// Titre/description dans les 12 langues de l'app (voir migration
/// convert_pack_and_slide_text_to_translatable_json côté backend) — comme
/// pour PackCategory, la carte complète arrive du serveur et [titleFor]/
/// [descriptionFor] choisissent la langue courante avec repli sur le
/// français. Seul un premier lot de packs a des traductions au-delà du
/// français pour l'instant ; le repli couvre les autres.
class Pack {
  final String id;
  final Map<String, String> title;
  final Map<String, String>? description;
  final String category; // morning | night | distance | celebration | reconciliation | humor
  final String? coverPath;
  final int sendCoinPrice;
  final List<Slide> slides;

  const Pack({
    required this.id,
    required this.title,
    this.description,
    required this.category,
    this.coverPath,
    this.sendCoinPrice = 1,
    this.slides = const [],
  });

  String titleFor(String localeCode) {
    if (title.containsKey(localeCode)) return title[localeCode]!;
    if (title.containsKey('fr')) return title['fr']!;
    return title.values.isNotEmpty ? title.values.first : '';
  }

  String? descriptionFor(String localeCode) => description?[localeCode] ?? description?['fr'];

  factory Pack.fromJson(Map<String, dynamic> json) => Pack(
        id: json['id'] as String,
        title: _localeMap(json['title']),
        description: json['description'] != null ? _localeMap(json['description']) : null,
        category: json['category'] as String? ?? 'night',
        coverPath: json['cover_path'] as String?,
        sendCoinPrice: json['send_coin_price'] as int? ?? 1,
        slides: json['slides'] != null
            ? (json['slides'] as List).map((e) => Slide.fromJson(e as Map<String, dynamic>)).toList()
            : const [],
      );

  static Map<String, String> _localeMap(dynamic value) =>
      (value as Map).map((k, v) => MapEntry(k as String, v as String));
}
