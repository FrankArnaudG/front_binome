import 'dart:convert';

import 'package:binome_app2/core/pin_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PBKDF2-HMAC-SHA256 (vecteurs de test publics, mot de passe "password", sel "salt")', () {
    final salt = utf8.encode('salt');

    test('1 itération', () {
      expect(
        _hex(pinPbkdf2ForTest('password', salt, 1)),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
    });

    test('2 itérations', () {
      expect(
        _hex(pinPbkdf2ForTest('password', salt, 2)),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      );
    });

    test('4096 itérations', () {
      expect(
        _hex(pinPbkdf2ForTest('password', salt, 4096)),
        'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
      );
    });
  });

  group('PinStorage', () {
    const storage = FlutterSecureStorage();

    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('le code n\'est jamais stocké en clair et se vérifie', () async {
      await PinStorage.instance.setPin('123456');
      final stored = await storage.read(key: 'app_lock_pin');

      expect(stored, isNotNull);
      expect(stored, isNot('123456'));
      expect(stored, isNot(contains('123456')));
      expect(stored, startsWith(r'v1$'));
      expect(await PinStorage.instance.isEnabled(), isTrue);
      expect(await PinStorage.instance.verify('123456'), isTrue);
      expect(await PinStorage.instance.verify('654321'), isFalse);
    });

    test('deux enregistrements du même code donnent des hachages différents (sel)', () async {
      await PinStorage.instance.setPin('123456');
      final first = await storage.read(key: 'app_lock_pin');
      await PinStorage.instance.setPin('123456');
      final second = await storage.read(key: 'app_lock_pin');

      expect(first, isNot(second));
    });

    test('un ancien code en clair reste valable, puis est converti en hachage', () async {
      FlutterSecureStorage.setMockInitialValues({'app_lock_pin': '123456'});

      expect(await PinStorage.instance.verify('000000'), isFalse);
      expect(await storage.read(key: 'app_lock_pin'), '123456'); // pas converti sur un échec

      expect(await PinStorage.instance.verify('123456'), isTrue);
      final migrated = await storage.read(key: 'app_lock_pin');
      expect(migrated, startsWith(r'v1$'));
      expect(migrated, isNot(contains('123456')));
      expect(await PinStorage.instance.verify('123456'), isTrue);
      expect(await PinStorage.instance.verify('000000'), isFalse);
    });

    test('sans code défini : désactivé, vérification refusée ; clear() supprime', () async {
      expect(await PinStorage.instance.isEnabled(), isFalse);
      expect(await PinStorage.instance.verify('123456'), isFalse);

      await PinStorage.instance.setPin('123456');
      await PinStorage.instance.clear();
      expect(await PinStorage.instance.isEnabled(), isFalse);
    });

    test('une valeur stockée corrompue est refusée sans planter', () async {
      FlutterSecureStorage.setMockInitialValues({'app_lock_pin': r'v1$abc$???$???'});
      expect(await PinStorage.instance.verify('123456'), isFalse);
    });
  });
}
