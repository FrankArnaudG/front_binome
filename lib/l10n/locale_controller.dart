import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_locale.dart';
import 'translations.dart';

/// Préférence de langue — locale à l'appareil, jamais synchronisée via la
/// Box : chaque personne du couple choisit la sienne indépendamment (même
/// principe que [ThemeController]).
class LocaleController extends ChangeNotifier {
  LocaleController._();
  static final LocaleController instance = LocaleController._();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _key = 'app_locale_code';

  AppLocale _current = AppLocale.defaultLocale;
  AppLocale get current => _current;

  bool _loaded = false;

  /// À appeler une fois au démarrage (idempotent) pour restaurer le choix
  /// précédent — avant ça, [current] renvoie le français.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;

    final savedCode = await _storage.read(key: _key);
    if (savedCode != null) {
      _current = AppLocale.byCode(savedCode);
      notifyListeners();
    }
  }

  Future<void> select(String code) async {
    _current = AppLocale.byCode(code);
    notifyListeners();
    await _storage.write(key: _key, value: code);
  }

  /// Traduit [key] dans la langue courante, avec repli sur le français si
  /// la clé n'a pas encore de traduction (voir [kTranslations]). [params]
  /// remplace les `{jeton}` du gabarit, ex. `t('dashboard_welcome', {'name': 'Awa'})`.
  String t(String key, [Map<String, String>? params]) {
    final template = kTranslations[_current.code]?[key] ?? kTranslations['fr']![key] ?? key;
    if (params == null) return template;
    var result = template;
    for (final entry in params.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value);
    }
    return result;
  }
}
