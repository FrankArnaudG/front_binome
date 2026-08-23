import 'package:flutter/material.dart';

/// Habillage produit par le studio admin (image/texte/couleur/police/
/// position) — voir binome_back resources/views/admin/slides/studio.blade.php.
/// `null` sur [Slide.design] = rendu par défaut (aucune personnalisation).
class SlideDesign {
  final Color textColor;
  final String fontFamily;
  final double textX;
  final double textY;

  const SlideDesign({
    required this.textColor,
    required this.fontFamily,
    required this.textX,
    required this.textY,
  });

  factory SlideDesign.fromJson(Map<String, dynamic> json) => SlideDesign(
    textColor: _parseHexColor(json['text_color'] as String?) ?? Colors.white,
    fontFamily: json['font_family'] as String? ?? 'playfair_display_italic',
    textX: (json['text_x'] as num?)?.toDouble() ?? 10,
    textY: (json['text_y'] as num?)?.toDouble() ?? 70,
  );

  static Color? _parseHexColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var value = hex.replaceFirst('#', '');
    if (value.length == 6) value = 'FF$value';
    final parsed = int.tryParse(value, radix: 16);
    return parsed != null ? Color(parsed) : null;
  }
}

class Slide {
  final String id;
  final String packId;
  final String mediaType; // image | text
  final String? mediaPath;
  final Map<String, String>? text;
  final int order;
  final SlideDesign? design;
  final String? category;

  const Slide({
    required this.id,
    required this.packId,
    required this.mediaType,
    this.mediaPath,
    this.text,
    required this.order,
    this.design,
    this.category,
  });

  String? textFor(String localeCode) => text?[localeCode] ?? text?['fr'];

  factory Slide.fromJson(Map<String, dynamic> json) => Slide(
    id: json['id'] as String,
    packId: json['pack_id'] as String,
    mediaType: json['media_type'] as String,
    mediaPath: json['media_path'] as String?,
    text: json['text'] != null
        ? (json['text'] as Map).map((k, v) => MapEntry(k as String, v as String))
        : null,
    order: json['order'] as int? ?? 0,
    design: json['design'] != null
        ? SlideDesign.fromJson(json['design'] as Map<String, dynamic>)
        : null,
    category: json['category'] as String?,
  );
}
