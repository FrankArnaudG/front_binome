import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  TokenStorage._();
  static final TokenStorage instance = TokenStorage._();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';

  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  /// Genre ("Homme"/"Femme"/autre) du profil connecté, gardé en mémoire pour
  /// les widgets synchrones (ex. image de catégorie selon le genre de la
  /// personne qui envoie un poème). Mis à jour à chaque sauvegarde/lecture du
  /// profil, remis à null à la déconnexion.
  static String? currentGender;

  static void _rememberGender(String json) {
    try {
      currentGender =
          (jsonDecode(json) as Map<String, dynamic>)['gender'] as String?;
    } catch (_) {
      // JSON illisible : on garde la dernière valeur connue.
    }
  }

  /// Cache brute (JSON) du dernier profil connu — sert de repli quand
  /// `/auth/me` échoue au démarrage pour une raison réseau transitoire,
  /// pour ne pas forcer une reconnexion alors que le token est toujours
  /// valide.
  Future<void> saveUserJson(String json) {
    _rememberGender(json);
    return _storage.write(key: _userKey, value: json);
  }

  Future<String?> readUserJson() async {
    final json = await _storage.read(key: _userKey);
    if (json != null && currentGender == null) _rememberGender(json);
    return json;
  }

  Future<void> clear() async {
    currentGender = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
  }
}
