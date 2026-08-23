class GameBoxQuestion {
  final String id;
  final Map<String, String> text;
  final int order;
  final String? category; // verite | defi | null (jeux "classiques")
  final List<String> options; // uniquement pour un sondage à l'aveugle

  const GameBoxQuestion({
    required this.id,
    required this.text,
    required this.order,
    this.category,
    this.options = const [],
  });

  bool get isVerite => category == 'verite';
  bool get isDefi => category == 'defi';

  String textFor(String localeCode) {
    if (text.containsKey(localeCode)) return text[localeCode]!;
    if (text.containsKey('fr')) return text['fr']!;
    return text.values.isNotEmpty ? text.values.first : '';
  }

  factory GameBoxQuestion.fromJson(Map<String, dynamic> json) => GameBoxQuestion(
        id: json['id'] as String,
        text: _localeMap(json['text']),
        order: json['order'] as int? ?? 0,
        category: json['category'] as String?,
        options: (json['options'] as String?)
                ?.split('\n')
                .map((o) => o.trim())
                .where((o) => o.isNotEmpty)
                .toList() ??
            const [],
      );

  static Map<String, String> _localeMap(dynamic value) =>
      (value as Map).map((k, v) => MapEntry(k as String, v as String));
}

/// Un "niveau" thématique d'un jeu (voir GameBox côté backend) — débloqué
/// une fois la boîte précédente terminée par le couple.
class GameBox {
  final String id;
  final Map<String, String> title;
  final Map<String, String> theme;
  final String? iconKey;
  final String? imagePath;
  final int order;
  final bool completed;
  final bool unlocked;
  final List<GameBoxQuestion> questions;

  const GameBox({
    required this.id,
    required this.title,
    required this.theme,
    this.iconKey,
    this.imagePath,
    required this.order,
    required this.completed,
    required this.unlocked,
    required this.questions,
  });

  String titleFor(String localeCode) {
    if (title.containsKey(localeCode)) return title[localeCode]!;
    if (title.containsKey('fr')) return title['fr']!;
    return title.values.isNotEmpty ? title.values.first : '';
  }

  String themeFor(String localeCode) {
    if (theme.containsKey(localeCode)) return theme[localeCode]!;
    if (theme.containsKey('fr')) return theme['fr']!;
    return theme.values.isNotEmpty ? theme.values.first : '';
  }

  factory GameBox.fromJson(Map<String, dynamic> json) => GameBox(
        id: json['id'] as String,
        title: _localeMap(json['title']),
        theme: _localeMap(json['theme']),
        iconKey: json['icon_key'] as String?,
        imagePath: json['image_path'] as String?,
        order: json['order'] as int? ?? 0,
        completed: json['completed'] as bool? ?? false,
        unlocked: json['unlocked'] as bool? ?? false,
        questions: (json['questions'] as List<dynamic>? ?? [])
            .map((q) => GameBoxQuestion.fromJson(q as Map<String, dynamic>))
            .toList(),
      );

  static Map<String, String> _localeMap(dynamic value) =>
      (value as Map).map((k, v) => MapEntry(k as String, v as String));
}
