import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/api_client.dart';
import '../../core/api_config.dart';
import '../../core/delivery_ack_service.dart';
import '../../core/local_cache.dart';
import '../../core/push_notification_service.dart';
import '../../core/token_storage.dart';
import '../../models/app_user.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

/// Résultat null = l'utilisateur a annulé la connexion Google (pas une erreur).
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  // `serverClientId` (Android/iOS) sert à obtenir un idToken vérifiable côté
  // backend ; le plugin web n'accepte pas ce paramètre (assertion : "not
  // supported on Web") et attend `clientId` à la place — le même client ID
  // OAuth web y produit déjà un idToken exploitable tel quel.
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: const ['email'],
    serverClientId: kIsWeb ? null : ApiConfig.googleWebClientId,
    clientId: kIsWeb ? ApiConfig.googleWebClientId : null,
  );

  /// [promoCode] n'a d'effet que pour un tout nouveau compte (voir
  /// AuthenticationController::loginWithGoogle) — sans effet, ignoré
  /// silencieusement, pour un compte déjà existant qui se reconnecte.
  Future<AppUser?> signInWithGoogle({String? promoCode}) async {
    final account = await _googleSignIn.signIn();
    if (account == null) return null; // annulé par l'utilisateur

    final googleAuth = await account.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null) {
      throw AuthException("Impossible de récupérer le jeton d'identité Google.");
    }

    try {
      final data = await ApiClient.instance.post('/auth/login/google', body: {
        'id_token': idToken,
        if (promoCode != null && promoCode.trim().isNotEmpty) 'promo_code': promoCode.trim(),
      }) as Map<String, dynamic>;
      final userJson = data['user'] as Map<String, dynamic>;

      await TokenStorage.instance.saveToken(data['token'] as String);
      await TokenStorage.instance.saveUserJson(jsonEncode(userJson));
      return AppUser.fromJson(userJson);
    } on ApiException catch (e) {
      throw AuthException(e.message);
    }
  }

  /// Vérifie la session stockée. Retourne l'utilisateur si le token est
  /// encore valide.
  ///
  /// Si `/auth/me` échoue pour une raison réseau transitoire (pas un rejet
  /// explicite du token), on retombe sur le dernier profil mis en cache
  /// plutôt que de forcer une reconnexion — sinon un simple accroc réseau
  /// au démarrage de l'app se traduit par "la session n'est pas gardée".
  Future<AppUser?> restoreSession() async {
    final token = await TokenStorage.instance.readToken();
    if (token == null) return null;

    try {
      final data = await ApiClient.instance.get('/auth/me') as Map<String, dynamic>;
      final userJson = data['user'] as Map<String, dynamic>;
      await TokenStorage.instance.saveUserJson(jsonEncode(userJson));
      return AppUser.fromJson(userJson);
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await TokenStorage.instance.clear();
        return null;
      }
      return _cachedUser();
    } catch (_) {
      return _cachedUser();
    }
  }

  Future<AppUser?> _cachedUser() async {
    final cached = await TokenStorage.instance.readUserJson();
    if (cached == null) return null;
    try {
      return AppUser.fromJson(jsonDecode(cached) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> signOut() async {
    await PushNotificationService.instance.unregisterToken();
    DeliveryAckService.instance.stop();
    try {
      await ApiClient.instance.post('/auth/logout');
    } catch (_) {
      // best effort
    }
    await TokenStorage.instance.clear();
    // Sinon un autre compte connecté ensuite sur ce même appareil verrait,
    // même brièvement hors ligne, l'historique mis en cache du compte
    // précédent (voir LocalCache).
    await LocalCache.instance.clear();
    await _googleSignIn.signOut();
  }

  Future<AppUser> updateProfile({
    String? name,
    String? prenom,
    String? gender,
    String? country,
    List<String>? loveName,
  }) async {
    try {
      final data = await ApiClient.instance.put('/auth/update-profile', body: {
        if (name != null) 'name': name,
        if (prenom != null) 'prenom': prenom,
        if (gender != null) 'gender': gender,
        if (country != null) 'country': country,
        if (loveName != null) 'love_name': loveName,
      }) as Map<String, dynamic>;
      final userJson = data['user'] as Map<String, dynamic>;
      await TokenStorage.instance.saveUserJson(jsonEncode(userJson));
      return AppUser.fromJson(userJson);
    } on ApiException catch (e) {
      throw AuthException(e.message);
    }
  }

  /// Photo de profil personnelle — remplace celle fournie par Google (ou une
  /// précédente) plutôt que de la garder à côté (voir
  /// ProfileController::uploadAvatar côté backend).
  Future<AppUser> uploadAvatar(File file) async {
    try {
      final data = await ApiClient.instance.postMultipart(
        '/auth/avatar',
        fieldName: 'avatar',
        file: file,
      ) as Map<String, dynamic>;
      final userJson = data['user'] as Map<String, dynamic>;
      await TokenStorage.instance.saveUserJson(jsonEncode(userJson));
      return AppUser.fromJson(userJson);
    } on ApiException catch (e) {
      throw AuthException(e.message);
    }
  }

  Future<AppUser> deleteAvatar() async {
    try {
      final data = await ApiClient.instance.delete('/auth/avatar') as Map<String, dynamic>;
      final userJson = data['user'] as Map<String, dynamic>;
      await TokenStorage.instance.saveUserJson(jsonEncode(userJson));
      return AppUser.fromJson(userJson);
    } on ApiException catch (e) {
      throw AuthException(e.message);
    }
  }

  /// Étape obligatoire juste après l'authentification tant que
  /// [AppUser.needsProfileCompletion] est vrai (voir AppRouter.routeAfterAuth)
  /// — contrairement à [updateProfile], tous les champs sont requis ici.
  Future<AppUser> completeProfile({
    required String name,
    required String prenom,
    required String gender,
    required String country,
  }) async {
    try {
      final data = await ApiClient.instance.put('/auth/complete-profile', body: {
        'name': name,
        'prenom': prenom,
        'gender': gender,
        'country': country,
      }) as Map<String, dynamic>;
      final userJson = data['user'] as Map<String, dynamic>;
      await TokenStorage.instance.saveUserJson(jsonEncode(userJson));
      return AppUser.fromJson(userJson);
    } on ApiException catch (e) {
      throw AuthException(e.message);
    }
  }

  Future<void> updatePassword({
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) async {
    try {
      await ApiClient.instance.put('/auth/update-password', body: {
        'current_password': currentPassword,
        'password': password,
        'password_confirmation': passwordConfirmation,
      });
    } on ApiException catch (e) {
      throw AuthException(e.message);
    }
  }

  /// [password] est ignoré côté backend pour un compte Google (pas de mot
  /// de passe local) — voir ProfileController::deleteAccount.
  Future<void> deleteAccount({String? password}) async {
    await PushNotificationService.instance.unregisterToken();
    DeliveryAckService.instance.stop();
    try {
      await ApiClient.instance.delete('/auth/delete-account', body: {
        if (password != null) 'password': password,
      });
    } on ApiException catch (e) {
      throw AuthException(e.message);
    }
    await TokenStorage.instance.clear();
    await LocalCache.instance.clear();
    await _googleSignIn.signOut();
  }
}
