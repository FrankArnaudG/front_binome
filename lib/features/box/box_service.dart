import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/api_client.dart';
import '../../core/local_cache.dart';
import '../../models/box.dart';
import '../../models/box_stats.dart';

/// État partagé de la Box du couple (singleton `ChangeNotifier`, dans le
/// même esprit que AuthService/TokenStorage). Exposé aux écrans via
/// [BoxScope] pour qu'ils se reconstruisent sur changement sans avoir à
/// passer la Box en paramètre partout — contrairement à AppUser (identité
/// stable), l'état de la Box change en direct (temps réel + actions).
class BoxService extends ChangeNotifier {
  BoxService._();
  static final BoxService instance = BoxService._();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _cacheKey = 'box_cache';

  Box? _currentBox;
  Box? get currentBox => _currentBox;

  /// Applique une réponse serveur (Box ou `null`) : met à jour l'état, le
  /// cache local, et notifie les écouteurs. Utilisé par toutes les
  /// mutations pour ne jamais dupliquer la logique de cache.
  Future<Box?> _apply(Map<String, dynamic>? json) async {
    final box = json != null ? Box.fromJson(json) : null;
    _currentBox = box;
    notifyListeners();

    if (json != null) {
      await _storage.write(key: _cacheKey, value: jsonEncode(json));
    } else {
      await _storage.delete(key: _cacheKey);
    }

    return box;
  }

  Future<Box> createBox() async {
    final data = await ApiClient.instance.post('/boxes') as Map<String, dynamic>;
    return (await _apply(data))!;
  }

  Future<Box> joinBox(String code) async {
    final data = await ApiClient.instance.post('/boxes/join', body: {'code': code}) as Map<String, dynamic>;
    return (await _apply(data))!;
  }

  /// Récupère la Box courante. Si l'appel échoue pour une raison réseau
  /// transitoire (pas une réponse explicite du serveur), on retombe sur la
  /// dernière Box connue en cache plutôt que de considérer qu'il n'y en a
  /// pas — sinon un simple accroc réseau au démarrage renvoie
  /// systématiquement vers l'écran de jumelage, même quand une Box active
  /// existe bel et bien côté serveur (voir AuthService pour le même
  /// principe côté session).
  Future<Box?> fetchCurrent() async {
    try {
      final data = await ApiClient.instance.get('/boxes/current');
      return await _apply(data as Map<String, dynamic>?);
    } catch (_) {
      final cached = await _storage.read(key: _cacheKey);
      if (cached == null) return null;
      try {
        return await _apply(jsonDecode(cached) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> leaveBox() async {
    await ApiClient.instance.post('/boxes/leave');
    await _apply(null);
  }

  Future<Box> updateSettings({
    bool? eveningRitualEnabled,
    String? eveningRitualTime,
    bool? morningRitualEnabled,
    String? morningRitualTime,
    String? motto,
    DateTime? togetherSince,
  }) async {
    final data = await ApiClient.instance.put('/boxes/settings', body: {
      if (eveningRitualEnabled != null) 'evening_ritual_enabled': eveningRitualEnabled,
      if (eveningRitualTime != null) 'evening_ritual_time': eveningRitualTime,
      if (morningRitualEnabled != null) 'morning_ritual_enabled': morningRitualEnabled,
      if (morningRitualTime != null) 'morning_ritual_time': morningRitualTime,
      if (motto != null) 'motto': motto,
      if (togetherSince != null) 'together_since': togetherSince.toIso8601String().split('T').first,
    }) as Map<String, dynamic>;
    return (await _apply(data))!;
  }

  /// Photo de couple (voir DarkDayCounterCard) — remplace l'ancienne s'il y
  /// en avait une (voir BoxController::uploadPhoto côté backend).
  Future<Box> uploadPhoto(File file) async {
    final data = await ApiClient.instance.postMultipart(
      '/boxes/photo',
      fieldName: 'photo',
      file: file,
    ) as Map<String, dynamic>;
    return (await _apply(data))!;
  }

  Future<Box> deletePhoto() async {
    final data = await ApiClient.instance.delete('/boxes/photo') as Map<String, dynamic>;
    return (await _apply(data))!;
  }

  static const _statsCacheKey = 'cache_box_stats';

  /// Dernier score connu, lu instantanément sans requête réseau — permet à
  /// [CoupleStatsCard] de s'afficher tout de suite à l'ouverture au lieu
  /// d'attendre le réseau, pendant que [fetchStats] rafraîchit derrière.
  /// `null` si rien n'a jamais été mis en cache (tout premier lancement).
  Future<BoxStats?> cachedStats() async {
    final cached = await LocalCache.instance.readJson<Map<String, dynamic>>(_statsCacheKey);
    if (cached == null) return null;
    return BoxStats.fromJson(cached);
  }

  Future<BoxStats> fetchStats() async {
    final data = await ApiClient.instance.get('/boxes/stats') as Map<String, dynamic>;
    await LocalCache.instance.writeJson(_statsCacheKey, data);
    return BoxStats.fromJson(data);
  }

}
