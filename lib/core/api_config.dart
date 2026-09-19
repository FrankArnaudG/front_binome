import 'package:flutter/foundation.dart' show kReleaseMode;

class ApiConfig {
  ApiConfig._();

  /// Client ID web Google OAuth (doit matcher GOOGLE_CLIENT_ID côté backend).
  static const String googleWebClientId =
      '1061033674265-c4mt2ca975t4bo26kd2isab2958djm3t.apps.googleusercontent.com';

  /// API de production (HTTPS, certificat Let's Encrypt).
  static const String productionApiUrl = 'https://api.binomecouple.com/api';

  static String get baseUrl {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) return override;

    // Version publiée (release) : toujours la production en HTTPS, sans rien à
    // passer en ligne de commande. En développement (debug/profile) : serveur
    // local, ce qui nécessite `adb reverse tcp:8000 tcp:8000` (et tcp:8080
    // pour Reverb) avant de lancer l'app, sur émulateur comme sur appareil
    // réel (USB ou wifi-adb) — ou --dart-define=API_BASE_URL=... pour viser
    // un autre serveur.
    return kReleaseMode ? productionApiUrl : 'http://localhost:8000/api';
  }

  /// Vrai si l'API est jointe en HTTPS — le temps réel suit alors le même
  /// chemin (wss sur le port 443, proxifié par Nginx vers Reverb).
  static bool get _baseIsHttps => Uri.parse(baseUrl).scheme == 'https';

  /// Garde-fou à appeler au tout début de `main()` : une version publiée ne
  /// doit JAMAIS partir avec une API locale ou non chiffrée (Android bloque de
  /// toute façon le trafic HTTP en release, l'app serait inutilisable — voir
  /// rapport d'audit du 13/09/2026). Sans effet en debug/profile.
  static void assertSafeForRelease() {
    if (!kReleaseMode) return;
    final uri = Uri.parse(baseUrl);
    const localHosts = {'localhost', '127.0.0.1', '10.0.2.2', '0.0.0.0'};
    if (uri.scheme != 'https' || localHosts.contains(uri.host)) {
      throw StateError('API_BASE_URL non sécurisée pour une version publiée : $baseUrl');
    }
  }

  /// URL d'autorisation des canaux privés/presence (Laravel Broadcasting),
  /// dérivée de [baseUrl] (même hôte, sans le préfixe /api).
  static String get broadcastAuthUrl {
    final uri = Uri.parse(baseUrl);
    return '${uri.scheme}://${uri.authority}/broadcasting/auth';
  }
  /// juste à identifier l'app côté client, comme une clé Pusher classique).
  static String get reverbAppKey {
    const override = String.fromEnvironment('REVERB_APP_KEY');
    if (override.isNotEmpty) return override;
    return '8900bcfa736cee9f7051c16963935c7b';
  }

  /// Même hôte que [baseUrl] par défaut (un seul tu
  ///
  ///
  ///
  /// nnel `adb reverse`/IP à
  /// gérer en dev), surchageable si Reverb est exposé ailleurs.
  static String get reverbHost {
    const override = String.fromEnvironment('REVERB_HOST');
    if (override.isNotEmpty) return override;
    return Uri.parse(baseUrl).host;
  }

  static int get reverbPort {
    const override = int.fromEnvironment('REVERB_PORT');
    if (override != 0) return override;
    return _baseIsHttps ? 443 : 8080;
  }

  static bool get reverbUseTLS {
    const override = String.fromEnvironment('REVERB_SCHEME');
    if (override.isNotEmpty) return override == 'https';
    return _baseIsHttps;
  }
}
