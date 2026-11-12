import 'package:flutter/material.dart';

/// Thème visuel de la discussion "Carnet de bord" — voir demande
/// utilisateur : "peut-on changer de thème de discussion comme dans [la
/// capture WhatsApp]". Distinct du thème général de l'app (voir
/// ThemeController/ThemePresets, qui colore toute l'interface) : celui-ci ne
/// touche QUE les bulles et le fond de SlideDetailScreen (le fil de réponse
/// à un poème/battement de cœur), jamais le reste de l'app.
class ChatTheme {
  final String id;
  final String name;

  /// Couleur pleine de la bulle "mine" (voir _textBubble) — jamais un
  /// dégradé ici, pour rester simple à définir/prévisualiser.
  final Color bubbleColor;

  /// `null` = fond uni (voir [backgroundColor]) ; sinon chemin d'asset vers
  /// une image de fond (voir assets/chat_themes/, pubspec.yaml).
  final String? backgroundAsset;

  /// Utilisée seule si [backgroundAsset] est `null`, sinon comme couleur de
  /// repli pendant le chargement de l'image.
  final Color backgroundColor;

  /// Voir demande utilisateur : "en fonction de certains thèmes, l'entête
  /// n'est pas totalement visible" — un fond sombre (Nuit douce, Étoilé) a
  /// besoin d'icônes/texte clairs dans l'en-tête ET d'une barre de statut
  /// système claire, pas de la couleur fixe du thème général de l'app.
  final bool isDark;

  const ChatTheme({
    required this.id,
    required this.name,
    required this.bubbleColor,
    required this.backgroundColor,
    this.backgroundAsset,
    this.isDark = false,
  });
}

/// Catalogue des thèmes disponibles — voir demande utilisateur, 4 thèmes
/// "couleur" (pas d'image) + 4 thèmes avec fond illustré (images fournies
/// par l'utilisateur, voir assets/chat_themes/).
class ChatThemes {
  ChatThemes._();

  static const classic = ChatTheme(
    id: 'classic',
    name: 'Classique',
    bubbleColor: Color(0xFFE94584),
    backgroundColor: Color(0xFFFCE9EF),
  );

  static const softNight = ChatTheme(
    id: 'soft_night',
    name: 'Nuit douce',
    bubbleColor: Color(0xFF4B3AA6),
    backgroundColor: Color(0xFF1A1733),
    isDark: true,
  );

  static const rosePastel = ChatTheme(
    id: 'rose_pastel',
    name: 'Pastel rosé',
    bubbleColor: Color(0xFFFF7E79),
    backgroundColor: Color(0xFFFFF1EE),
  );

  static const ocean = ChatTheme(
    id: 'ocean',
    name: 'Océan',
    bubbleColor: Color(0xFF2CA7C4),
    backgroundColor: Color(0xFFE6F6FA),
  );

  static const hearts = ChatTheme(
    id: 'hearts',
    name: 'Doodle amour',
    bubbleColor: Color(0xFFE64C66),
    backgroundColor: Color(0xFFFCE4E9),
    backgroundAsset: 'assets/chat_themes/hearts.jpg',
  );

  static const floral = ChatTheme(
    id: 'floral',
    name: 'Fleurs',
    bubbleColor: Color(0xFF9B5DE5),
    backgroundColor: Color(0xFFF3E8FC),
    backgroundAsset: 'assets/chat_themes/floral.jpg',
  );

  static const sunset = ChatTheme(
    id: 'sunset',
    name: 'Coucher de soleil',
    bubbleColor: Color(0xFFFF8552),
    backgroundColor: Color(0xFFFFE8DC),
    backgroundAsset: 'assets/chat_themes/sunset.jpg',
  );

  static const starfield = ChatTheme(
    id: 'starfield',
    name: 'Étoilé',
    bubbleColor: Color(0xFF6A4FD6),
    backgroundColor: Color(0xFF151029),
    backgroundAsset: 'assets/chat_themes/starfield.jpg',
    isDark: true,
  );

  static const all = [classic, softNight, rosePastel, ocean, hearts, floral, sunset, starfield];

  static ChatTheme byId(String? id) => all.firstWhere((t) => t.id == id, orElse: () => classic);
}
