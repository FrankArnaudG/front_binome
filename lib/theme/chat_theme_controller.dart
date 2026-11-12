import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'chat_theme.dart';

/// Préférence de thème de discussion (voir ChatTheme) — strictement locale à
/// cet appareil, jamais envoyée au backend ni au/à la partenaire (voir
/// demande utilisateur : "comme dans WhatsApp, vous seul·e pouvez voir le
/// thème"). Même mécanique que ThemeController (thème général de l'app),
/// mais une clé de stockage séparée et aucun appel réseau.
class ChatThemeController extends ChangeNotifier {
  ChatThemeController._();
  static final ChatThemeController instance = ChatThemeController._();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _key = 'chat_theme_id';

  ChatTheme _current = ChatThemes.classic;
  ChatTheme get current => _current;

  bool _loaded = false;

  /// À appeler une fois au démarrage (idempotent) — avant ça, [current]
  /// renvoie le thème par défaut (voir ThemeController.load, même principe).
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;

    final savedId = await _storage.read(key: _key);
    if (savedId != null) {
      _current = ChatThemes.byId(savedId);
      notifyListeners();
    }
  }

  Future<void> select(ChatTheme theme) async {
    _current = theme;
    notifyListeners();
    await _storage.write(key: _key, value: theme.id);
  }
}
