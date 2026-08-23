/// Catégorie de Poèmes-Slides — gérée depuis l'admin (voir PackCategoryController
/// côté backend), avec traduction dans les 12 langues de l'app. Contrairement
/// aux noms de cadeaux/packs (texte libre admin, jamais traduits), ces
/// catégories viennent avec leurs 12 traductions toutes faites : [labelFor]/
/// [taglineFor] choisissent celle de la langue courante, avec repli sur le
/// français si absente (même logique que LocaleController.t côté app).
class PackCategory {
  final String id;
  final String slug;
  final Map<String, String> labels;
  final Map<String, String> taglines;

  const PackCategory({
    required this.id,
    required this.slug,
    required this.labels,
    required this.taglines,
  });

  String labelFor(String localeCode) => labels[localeCode] ?? labels['fr'] ?? slug;

  String taglineFor(String localeCode) => taglines[localeCode] ?? taglines['fr'] ?? '';

  factory PackCategory.fromJson(Map<String, dynamic> json) => PackCategory(
        id: json['id'] as String,
        slug: json['slug'] as String,
        labels: (json['labels'] as Map).map((k, v) => MapEntry(k as String, v as String)),
        taglines: (json['taglines'] as Map).map((k, v) => MapEntry(k as String, v as String)),
      );
}
