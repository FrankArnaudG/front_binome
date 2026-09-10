import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../features/box/box_service.dart';
import 'local_cache.dart';

/// Partage de position EN DIRECT, mais UNIQUEMENT tant que l'app est au
/// premier plan (voir demande utilisateur : "dès que l'application est
/// ouverte, pas seulement l'écran Notre distance") — jamais en arrière-plan,
/// jamais sans que la personne l'ait explicitement activé (voir [enabled],
/// piloté par un interrupteur sur DistanceScreen, pas actif par défaut).
///
/// S'appuie sur [AppLifecycleState] (pas un service natif ni une tâche de
/// fond) : le flux de position démarre quand l'app repasse au premier plan
/// et s'arrête dès qu'elle quitte cet état — ne nécessite donc que la
/// permission "pendant l'utilisation" (jamais "Toujours autoriser"), voir
/// discussion avec l'utilisateur sur les compromis d'un vrai suivi
/// permanent (batterie, review Play Store/App Store, risque de contrôle
/// dans une app de couple).
class LiveLocationService with WidgetsBindingObserver {
  LiveLocationService._();
  static final LiveLocationService instance = LiveLocationService._();

  static const _prefsKey = 'cache_live_location_sharing_enabled';

  bool _initialized = false;
  bool _enabled = false;
  bool get enabled => _enabled;

  StreamSubscription<Position>? _positionSub;

  /// À appeler une fois après connexion (voir AppRouter.routeAfterAuth) —
  /// lit le réglage précédemment choisi et démarre le flux tout de suite
  /// si l'app est déjà au premier plan et que la personne l'a activé.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _enabled = (await LocalCache.instance.readJson<bool>(_prefsKey)) ?? false;

    WidgetsBinding.instance.addObserver(this);
    BoxService.instance.addListener(_onBoxChanged);

    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      unawaited(_startIfNeeded());
    }
  }

  /// Piloté par l'interrupteur de DistanceScreen — la demande de permission
  /// se fait LÀ (avec le contexte visible de pourquoi), jamais depuis ce
  /// service qui ne fait ensuite que vérifier l'état déjà accordé.
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await LocalCache.instance.writeJson(_prefsKey, value);
    if (value) {
      await _startIfNeeded();
    } else {
      _stop();
    }
  }

  void _onBoxChanged() {
    if (BoxService.instance.currentBox?.isActive == true) {
      unawaited(_startIfNeeded());
    } else {
      _stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_startIfNeeded());
    } else {
      // Tout état non "resumed" (paused/inactive/hidden/detached) — l'app
      // n'est plus au premier plan, on arrête immédiatement (voir doc de
      // classe : jamais de suivi hors de ce cas précis).
      _stop();
    }
  }

  Future<void> _startIfNeeded() async {
    if (!_enabled || _positionSub != null) return;
    final box = BoxService.instance.currentBox;
    if (box == null || !box.isActive) return;

    // Vérifie seulement — ne demande jamais la permission ici (voir
    // setEnabled, demandée au moment du geste explicite sur l'interrupteur).
    // Si jamais retirée depuis les réglages système entre-temps, le flux
    // reste simplement inactif plutôt que d'insister.
    final status = await Permission.locationWhenInUse.status;
    if (!status.isGranted && !status.isLimited) return;

    // Précision maximale (voir demande utilisateur : l'écart affiché doit
    // rester au plus proche possible de la réalité) — le distanceFilter
    // reste le principal levier pour la batterie, pas la précision.
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 25),
    ).listen(
      (position) {
        // Best-effort — voir doc de classe, une mise à jour manquée n'a
        // aucune conséquence, la suivante (au prochain déplacement) la
        // rattrape simplement.
        BoxService.instance.shareLocation(latitude: position.latitude, longitude: position.longitude).ignore();
      },
      onError: (_) {},
    );
  }

  void _stop() {
    _positionSub?.cancel();
    _positionSub = null;
  }
}
