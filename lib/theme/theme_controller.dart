import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/api_client.dart';
import 'theme_palette.dart';
import 'theme_presets.dart';

/// Préférence de thème — locale à l'appareil, chacun choisit la sienne
/// indépendamment ; [load] ne restaure jamais depuis le serveur, seulement
/// depuis le stockage local de cet appareil. [select] envoie quand même
/// l'id choisi au backend (best effort) pour une seule raison : permettre
/// au/à la partenaire de voir "sa" couleur sur le badge de présence du
/// Dashboard (voir CoupleAvatarsBadge) — jamais pour restaurer son propre
/// thème.
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _key = 'app_theme_id';

  ThemePalette _current = ThemePresets.defaultTheme;
  ThemePalette get current => _current;

  bool _loaded = false;

  /// À appeler une fois au démarrage (idempotent) pour restaurer le choix
  /// précédent — avant ça, [current] renvoie le thème par défaut.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;

    final savedId = await _storage.read(key: _key);
    if (savedId != null) {
      _current = ThemePresets.byId(savedId);
      notifyListeners();
    }
  }

  Future<void> select(String id) async {
    _current = ThemePresets.byId(id);
    notifyListeners();
    await _storage.write(key: _key, value: id);

    // Best effort : si ça échoue (hors-ligne...), le/la partenaire verra
    // juste une couleur de présence obsolète — jamais bloquant ici.
    ApiClient.instance.put('/auth/update-profile', body: {'theme_id': id}).catchError((_) => null);
  }
}
