import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/api_client.dart';
import '../../core/device_identifier.dart';
import '../../core/local_cache.dart';
import '../../core/realtime_client.dart';
import '../../models/app_user.dart';
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
  // Copie du JSON Box juste avant une dissolution détectée EN DIRECT (voir
  // _apply) — permet au message "ton binôme a quitté" de survivre à une
  // fermeture complète de l'app (voir demande utilisateur), alors que
  // `_cacheKey` lui est déjà effacé à ce moment-là (plus de Box active).
  static const _partnerLeftCacheKey = 'partner_left_box_cache';

  Box? _currentBox;
  Box? get currentBox => _currentBox;

  /// Identifiant du compte connecté — retenu une seule fois (voir
  /// [rememberUserId], appelé par AppRouter.routeAfterAuth) pour pouvoir
  /// déterminer, dans [partnerWhoLeft], LEQUEL de creator/partner est "mon
  /// binôme" plutôt que moi. BoxService ne reçoit jamais l'AppUser complet
  /// par ailleurs.
  String? _myUserId;
  void rememberUserId(String userId) => _myUserId = userId;

  /// Box telle qu'elle était juste AVANT que le/la binôme ne la quitte (voir
  /// demande utilisateur : bannière "ton binôme a quitté la Box") —
  /// nécessaire pour retrouver son prénom/genre, puisque `currentBox`
  /// devient `null`/`dissolved` une fois la dissolution effective côté
  /// serveur. `null` tant qu'aucune dissolution externe n'a eu lieu, ou dès
  /// qu'une nouvelle Box valide a été créée/rejointe (voir [_apply]).
  Box? _partnerLeftSnapshot;
  Box? get partnerLeftSnapshot => _partnerLeftSnapshot;

  /// Le/la binôme qui vient de quitter, `null` si rien à signaler ou si
  /// [rememberUserId] n'a pas encore été appelé.
  AppUser? get partnerWhoLeft => _myUserId != null ? _partnerLeftSnapshot?.partnerOf(_myUserId!) : null;

  /// Recharge, sans appel réseau, le dernier "ton binôme a quitté" connu —
  /// à appeler au démarrage (voir SplashScreen), AVANT que
  /// AppRouter.routeAfterAuth ne décide de rediriger vers BoxChoiceScreen,
  /// pour que le message survive à une fermeture complète de l'app entre
  /// le départ du binôme et la prochaine ouverture (voir demande
  /// utilisateur). No-op si rien n'a jamais été persisté.
  Future<void> loadPersistedPartnerLeft() async {
    final cached = await _storage.read(key: _partnerLeftCacheKey);
    if (cached == null) return;
    try {
      _partnerLeftSnapshot = Box.fromJson(jsonDecode(cached) as Map<String, dynamic>);
    } catch (_) {
      // Cache corrompu : pas grave, le message sera simplement absent.
    }
  }

  /// Applique une réponse serveur (Box ou `null`) : met à jour l'état, le
  /// cache local, et notifie les écouteurs. Utilisé par toutes les
  /// mutations pour ne jamais dupliquer la logique de cache.
  ///
  /// [selfInitiated] : vrai UNIQUEMENT depuis [leaveBox] — un départ décidé
  /// par SOI-MÊME redirige immédiatement vers BoxChoiceScreen (voir
  /// SettingsScreen._leaveBox), la bannière "ton binôme a quitté" n'a donc
  /// pas lieu d'être déclenchée dans ce cas précis.
  Future<Box?> _apply(Map<String, dynamic>? json, {bool selfInitiated = false}) async {
    final box = json != null ? Box.fromJson(json) : null;

    if (!selfInitiated && _currentBox?.isActive == true && _currentBox?.partnerId != null && (box == null || box.isDissolved)) {
      _partnerLeftSnapshot = _currentBox;
      // Capturé AVANT l'effacement de `_cacheKey` plus bas : c'est encore
      // le JSON de la Box active d'avant la dissolution à cet instant.
      final previousJson = await _storage.read(key: _cacheKey);
      if (previousJson != null) {
        await _storage.write(key: _partnerLeftCacheKey, value: previousJson);
      }
    } else if (box != null && !box.isDissolved) {
      _partnerLeftSnapshot = null;
      await _storage.delete(key: _partnerLeftCacheKey);
    }

    _currentBox = box;
    notifyListeners();
    _subscribeRealtimeBoxEvents();

    if (json != null) {
      await _storage.write(key: _cacheKey, value: jsonEncode(json));
    } else {
      await _storage.delete(key: _cacheKey);
    }

    return box;
  }

  String? _boxEventsSubBoxId;

  /// Écoute globale (voir demande utilisateur : la position devait déjà
  /// être à jour même si on n'est pas sur l'écran "Notre distance" au
  /// moment où le binôme la partage — et, depuis, le départ du binôme doit
  /// aussi se refléter tout de suite, "sans attendre que j'actualise la
  /// page") — même principe que DoodleNotifier : une seule souscription
  /// vivant tant que l'app tourne, jamais limitée à la durée de vie d'un
  /// écran en particulier.
  void _subscribeRealtimeBoxEvents() {
    final boxId = _currentBox?.id;
    if (boxId == _boxEventsSubBoxId) return;
    if (_boxEventsSubBoxId != null) {
      RealtimeClient.instance.unsubscribeFromBox(_boxEventsSubBoxId!, onEvent: _onRealtimeBoxEvent);
    }
    _boxEventsSubBoxId = boxId;
    if (boxId != null) {
      RealtimeClient.instance.subscribeToBox(boxId, onEvent: _onRealtimeBoxEvent);
    }
  }

  void _onRealtimeBoxEvent(RealtimeEvent event) {
    if (event.event != 'BoxLocationShared' && event.event != 'BoxDissolved') return;
    fetchCurrent();
  }

  Future<Box> createBox() async {
    final deviceId = await DeviceIdentifier.get();
    final data = await ApiClient.instance.post(
      '/boxes',
      body: {if (deviceId != null) 'device_id': deviceId},
    ) as Map<String, dynamic>;
    return (await _apply(data))!;
  }

  Future<Box> joinBox(String code) async {
    final deviceId = await DeviceIdentifier.get();
    final data = await ApiClient.instance.post(
      '/boxes/join',
      body: {'code': code, if (deviceId != null) 'device_id': deviceId},
    ) as Map<String, dynamic>;
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

  /// Dernière Box connue, sans appel réseau (`null` si aucune en cache) —
  /// pour un démarrage instantané ; [fetchCurrent] la rafraîchit ensuite.
  Future<Box?> loadCached() async {
    final cached = await _storage.read(key: _cacheKey);
    if (cached == null) return null;
    try {
      return await _apply(jsonDecode(cached) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> leaveBox() async {
    await ApiClient.instance.post('/boxes/leave');
    await _apply(null, selfInitiated: true);
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

  /// Partage PONCTUEL de la position courante (voir demande utilisateur :
  /// jamais de suivi continu — un bouton "Partager ma position", appelé une
  /// fois par tap, jamais en tâche de fond).
  Future<Box> shareLocation({required double latitude, required double longitude}) async {
    final data = await ApiClient.instance.post('/boxes/location', body: {
      'latitude': latitude,
      'longitude': longitude,
    }) as Map<String, dynamic>;
    return (await _apply(data))!;
  }

  /// Définit/déplace le repère "maison" partagé de la Box (voir demande
  /// utilisateur) — même esprit que [shareLocation], modifiable par
  /// n'importe lequel des deux membres.
  Future<Box> setHomeLocation({required double latitude, required double longitude}) async {
    final data = await ApiClient.instance.put('/boxes/home', body: {
      'latitude': latitude,
      'longitude': longitude,
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
