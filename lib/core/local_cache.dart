import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Cache de LECTURE (jamais la source de vérité) pour éviter un écran vide
/// quand l'app est ouverte hors connexion — pas une vraie synchronisation
/// offline-first : le serveur reste seul autorité, ce cache ne fait que
/// mémoriser la dernière réponse réseau réussie pour un endpoint donné (voir
/// ContentService.fetchSends/fetchReplies). Écrit dans le stockage privé de
/// l'app (pas un "cache" que l'OS pourrait purger), donc persiste tant que
/// l'app n'est pas désinstallée ou ses données effacées manuellement.
class LocalCache {
  LocalCache._();
  static final LocalCache instance = LocalCache._();

  Future<void> writeJson(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(value));
  }

  Future<T?> readJson<T>(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as T;
    } catch (_) {
      return null;
    }
  }

  /// Vide tout le cache — appelé à la déconnexion pour qu'un compte suivant
  /// connecté sur le même appareil ne voie jamais, même brièvement hors
  /// ligne, l'historique d'un autre compte (voir AuthService.signOut).
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where((k) => k.startsWith('cache_'))) {
      await prefs.remove(key);
    }
  }
}
