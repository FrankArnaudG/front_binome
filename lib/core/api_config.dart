class ApiConfig {
  ApiConfig._();

  /// Client ID web Google OAuth (doit matcher GOOGLE_CLIENT_ID côté backend).
  static const String googleWebClientId =
      '1061033674265-c4mt2ca975t4bo26kd2isab2958djm3t.apps.googleusercontent.com';

  static String get baseUrl {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) return override;

    // Nécessite `adb reverse tcp:8000 tcp:8000` (et tcp:8080 pour Reverb) avant
    // de lancer l'app, sur émulateur comme sur appareil réel (USB ou wifi-adb).
    return 'http://localhost:8000/api';
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
    return 8080;
  }

  static bool get reverbUseTLS {
    const override = String.fromEnvironment('REVERB_SCHEME');
    if (override.isNotEmpty) return override == 'https';
    return false;
  }
}
