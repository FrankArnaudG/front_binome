import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Code de verrouillage local à 6 chiffres (optionnel), demandé à chaque
/// ouverture de l'app. Purement local à l'appareil — jamais envoyé au
/// backend, protégé par le même chiffrement au repos (Keystore/Keychain)
/// que le token d'auth.
///
/// Le code n'est plus stocké en clair (voir rapport d'audit du 13/09/2026) :
/// on ne garde qu'un hachage salé PBKDF2-HMAC-SHA256, au format
/// `v1$<itérations>$<sel base64>$<hachage base64>`. Les codes déjà enregistrés
/// en clair par une version précédente restent valables : au premier
/// déverrouillage réussi, ils sont convertis en hachage sur place.
class PinStorage {
  PinStorage._();
  static final PinStorage instance = PinStorage._();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _pinKey = 'app_lock_pin';
  static const _formatPrefix = 'v1';
  static const _iterations = 60000;

  Future<bool> isEnabled() async => (await _storage.read(key: _pinKey)) != null;

  Future<void> setPin(String pin) async {
    await _storage.write(key: _pinKey, value: await _hashPin(pin));
  }

  Future<bool> verify(String pin) async {
    final stored = await _storage.read(key: _pinKey);
    if (stored == null) return false;

    if (!stored.startsWith('$_formatPrefix\$')) {
      // Ancien format (code en clair) : on compare, puis on convertit.
      final ok = _constantTimeEquals(utf8.encode(stored), utf8.encode(pin));
      if (ok) await setPin(pin);
      return ok;
    }

    final parts = stored.split(r'$');
    if (parts.length != 4) return false;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations <= 0) return false;
    try {
      final salt = base64Decode(parts[2]);
      final expected = base64Decode(parts[3]);
      final actual = await compute(_pbkdf2, _PbkdfInput(pin, salt, iterations));
      return _constantTimeEquals(actual, expected);
    } on FormatException {
      return false;
    }
  }

  Future<void> clear() => _storage.delete(key: _pinKey);

  Future<String> _hashPin(String pin) async {
    final random = Random.secure();
    final salt = Uint8List.fromList(List<int>.generate(16, (_) => random.nextInt(256)));
    final hash = await compute(_pbkdf2, _PbkdfInput(pin, salt, _iterations));
    return '$_formatPrefix\$$_iterations\$${base64Encode(salt)}\$${base64Encode(hash)}';
  }

  /// Comparaison en temps constant (ne révèle pas à quel octet ça diffère).
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

class _PbkdfInput {
  final String pin;
  final List<int> salt;
  final int iterations;
  const _PbkdfInput(this.pin, this.salt, this.iterations);
}

/// Accès de test à la fonction de dérivation (vérifiée contre les vecteurs de
/// test publics de PBKDF2-HMAC-SHA256, voir test/pin_storage_test.dart).
@visibleForTesting
Uint8List pinPbkdf2ForTest(String pin, List<int> salt, int iterations) => _pbkdf2(_PbkdfInput(pin, salt, iterations));

/// PBKDF2-HMAC-SHA256, un seul bloc de sortie (32 octets). Exécutée dans un
/// isolat (voir `compute`) : 60 000 itérations ne doivent pas bloquer l'écran.
Uint8List _pbkdf2(_PbkdfInput input) {
  final hmac = Hmac(sha256, utf8.encode(input.pin));
  final blockIndex = Uint8List(4)..[3] = 1; // INT_32_BE(1)
  var u = hmac.convert([...input.salt, ...blockIndex]).bytes;
  final result = List<int>.of(u);
  for (var i = 1; i < input.iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < result.length; j++) {
      result[j] ^= u[j];
    }
  }
  return Uint8List.fromList(result);
}
