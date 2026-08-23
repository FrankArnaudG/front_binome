import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Code de verrouillage local à 6 chiffres (optionnel), demandé à chaque
/// ouverture de l'app. Purement local à l'appareil — jamais envoyé au
/// backend, protégé par le même chiffrement au repos (Keystore/Keychain)
/// que le token d'auth.
class PinStorage {
  PinStorage._();
  static final PinStorage instance = PinStorage._();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _pinKey = 'app_lock_pin';

  Future<bool> isEnabled() async => (await _storage.read(key: _pinKey)) != null;

  Future<void> setPin(String pin) => _storage.write(key: _pinKey, value: pin);

  Future<bool> verify(String pin) async => (await _storage.read(key: _pinKey)) == pin;

  Future<void> clear() => _storage.delete(key: _pinKey);
}
