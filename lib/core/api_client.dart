import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'api_config.dart';
import 'server_clock.dart';
import 'token_storage.dart';

class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException(this.message, this.statusCode);
  @override
  String toString() => message;
}

/// Client HTTP partagé pour l'API Binome : centralise l'ajout du token, le
/// décodage JSON et la vérification `success`, pour éviter de dupliquer ce
/// boilerplate dans chaque service (voir l'ancien AuthService avant refacto).
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  Future<dynamic> get(String path) => _send('GET', path);

  Future<dynamic> post(String path, {Map<String, dynamic>? body}) => _send('POST', path, body: body);

  Future<dynamic> put(String path, {Map<String, dynamic>? body}) => _send('PUT', path, body: body);

  Future<dynamic> delete(String path, {Map<String, dynamic>? body}) => _send('DELETE', path, body: body);

  /// Upload multipart (ex. photo du Jardin secret) — les autres méthodes ne
  /// gèrent que du JSON, un envoi de fichier a besoin de son propre chemin
  /// (`multipart/form-data`, pas de `jsonEncode` possible sur un [File]).
  Future<dynamic> postMultipart(String path, {required String fieldName, required File file}) async {
    final token = await TokenStorage.instance.readToken();
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');

    final request = http.MultipartRequest('POST', uri)
      ..headers['Accept'] = 'application/json'
      ..files.add(await http.MultipartFile.fromPath(fieldName, file.path));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';

    try {
      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);
      return _decode(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _networkErrorToApiException(e);
    }
  }

  Future<dynamic> _send(String method, String path, {Map<String, dynamic>? body}) async {
    final token = await TokenStorage.instance.readToken();
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    // 25s (pas 10s) : certaines listes (ex. GET /games/{id}/boxes, qui
    // renvoie TOUTES les questions de TOUTES les catégories d'un coup, voir
    // GameBoxController::index) peuvent peser jusqu'à ~1 Mo une fois le
    // contenu bien fourni — 10s suffisait tant que le catalogue était
    // modeste, mais expirait silencieusement sur certains jeux depuis
    // (fetchBoxes avale l'erreur et retombe sur GameSessionScreen, voir
    // GamesMenuScreen._playGame).
    const timeout = Duration(seconds: 25);
    late final http.Response response;
    // Pas de filtrage des caractères de contrôle ici : STX/ETX (0x02/0x03)
    // sont utilisés DÉLIBÉRÉMENT par GameCardThreadScreen pour encoder une
    // citation dans le texte d'un message (voir _encodeQuoted/_decodeQuoted)
    // — les retirer casserait cette fonctionnalité. Ce qui ressemblait à un
    // glitch clavier était en fait ce mécanisme (voir demande utilisateur).
    final encodedBody = jsonEncode(body ?? {});
    try {
      switch (method) {
        case 'GET':
          response = await _get(uri, headers, timeout);
          break;
        case 'POST':
          response = await _client.post(uri, headers: headers, body: encodedBody).timeout(timeout);
          break;
        case 'PUT':
          response = await _client.put(uri, headers: headers, body: encodedBody).timeout(timeout);
          break;
        case 'DELETE':
          response = await _client.delete(uri, headers: headers, body: encodedBody).timeout(timeout);
          break;
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw _networkErrorToApiException(e);
    }

    // Jeton refusé par le serveur (déconnecté à distance depuis un autre appareil, voir « Déconnecter
    // les autres appareils ») : l'écran doit revenir à la connexion au lieu de rester affiché comme
    // connecté. Jamais pour les appels de déconnexion eux-mêmes.
    if (response.statusCode == 401 && token != null && !path.startsWith('/auth/logout') && !path.startsWith('/auth/device-tokens')) {
      unawaited(onSessionRevoked?.call());
    }

    // Maintenance qui vient de démarrer (voir EnsureNotInMaintenance côté
    // backend) : ne pas attendre le prochain événement temps réel pour
    // afficher l'écran de blocage (voir MaintenanceService.onBlockedResponse).
    if (response.statusCode == 503) {
      onMaintenanceBlocked?.call();
    }

    // Compte sanctionné pour avoir trop sollicité le serveur (voir
    // EnsureNotRateLimitSuspended côté backend) — même principe que le 503
    // ci-dessus (voir SuspensionService.onBlockedResponse).
    if (response.statusCode == 423) {
      onRateLimitSuspended?.call();
    }

    return _decode(response);
  }

  // Client HTTP PARTAGÉ : les fonctions http.get/http.post ouvraient une connexion neuve (TCP + TLS,
  // plusieurs allers-retours réseau) à CHAQUE appel. Sur un réseau mobile à forte latence, une connexion
  // vocale (serveurs ICE, offre, réponse, un appel par candidat réseau) perdait ainsi 30 à 40 secondes
  // (voir demande utilisateur). On réutilise désormais la même connexion ; inactive plus de 20 s elle est
  // fermée, pour ne pas garder un lien devenu caduc après un changement de réseau.
  static final http.Client _client = IOClient(HttpClient()..idleTimeout = const Duration(seconds: 20));

  /// GET avec une seule nouvelle tentative si la connexion réutilisée était devenue caduque (jamais pour
  /// un envoi : rejouer un POST pourrait le dupliquer).
  Future<http.Response> _get(Uri uri, Map<String, String> headers, Duration timeout) async {
    try {
      return await _client.get(uri, headers: headers).timeout(timeout);
    } on TimeoutException {
      rethrow;
    } catch (_) {
      return await _client.get(uri, headers: headers).timeout(timeout);
    }
  }

  /// Appelé (une fois à la fois) quand le serveur refuse le jeton de cet appareil — branché par
  /// AppShell, donc actif uniquement pendant qu'un compte est connecté.
  static Future<void> Function()? onSessionRevoked;

  /// Appelé (au moins une fois, sans attendre) quand le serveur répond 503
  /// (maintenance active, voir EnsureNotInMaintenance) — branché par
  /// AppShell comme [onSessionRevoked].
  static void Function()? onMaintenanceBlocked;

  /// Appelé (au moins une fois, sans attendre) quand le serveur répond 423
  /// (compte sanctionné pour abus de débit, voir EnsureNotRateLimitSuspended)
  /// — branché par AppShell comme [onMaintenanceBlocked].
  static void Function()? onRateLimitSuspended;

  /// Une panne réseau (serveur injoignable, DNS, timeout...) lève une
  /// exception BRUTE (SocketException/TimeoutException/ClientException),
  /// PAS une [ApiException] — sans cette conversion, tout appelant qui ne
  /// rattrape QUE `on ApiException` (le cas le plus courant dans l'app,
  /// voir startMemoryGameAndPush par ex.) laisse l'exception se propager
  /// sans jamais réinitialiser son état de chargement local : l'écran
  /// reste bloqué sur un loader indéfiniment, sans le moindre message
  /// (voir demande utilisateur : "ça tourne (le loader) depuis sans rien
  /// d'autre" après un souci réseau côté serveur local).
  ApiException _networkErrorToApiException(Object error) {
    if (error is TimeoutException) {
      return ApiException('Le serveur met trop de temps à répondre. Réessaie dans un instant.', 0);
    }
    if (error is SocketException || error is http.ClientException) {
      return ApiException('Impossible de joindre le serveur. Vérifie ta connexion.', 0);
    }
    return ApiException('Une erreur réseau est survenue.', 0);
  }

  dynamic _decode(http.Response response) {
    ServerClock.instance.updateFromHeader(response.headers['date']);
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode < 200 || response.statusCode >= 300 || decoded['success'] != true) {
      throw ApiException(decoded['message'] as String? ?? 'Une erreur est survenue.', response.statusCode);
    }

    return decoded['data'];
  }
}
