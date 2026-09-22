import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';

/// Permissions du mode « présentiel connecté » (Bluetooth / Nearby Connections), communes aux 7 jeux.
///
/// Avant, chaque écran exigeait que les CINQ permissions soient accordées, quel que soit le téléphone.
/// Or celles-ci n'existent qu'à partir d'une certaine version d'Android — Bluetooth « scan / advertise /
/// connect » dès Android 12 (SDK 31), « appareils à proximité » dès Android 13 (SDK 33) — et la
/// bibliothèque de permissions répond « refusée » pour une permission inexistante. Sur un téléphone plus
/// ancien (ex. Android 8.1), le message « Autorise Bluetooth et localisation » s'affichait donc toujours,
/// même avec la localisation déjà accordée. On ne demande maintenant que ce qui existe sur ce téléphone.
class NearbyPermissions {
  NearbyPermissions._();

  static const _permissionDeniedKey = 'memory_nearby_permission_denied';
  static const _locationOffKey = 'nearby_location_service_off';

  /// `null` si tout est en règle ; sinon la clé de traduction du message à afficher.
  static Future<String?> problemKey() async {
    final permissions = <Permission>[Permission.locationWhenInUse];

    if (!kIsWeb && Platform.isAndroid) {
      final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      if (sdk >= 31) {
        permissions.addAll([Permission.bluetoothAdvertise, Permission.bluetoothConnect, Permission.bluetoothScan]);
      }
      if (sdk >= 33) permissions.add(Permission.nearbyWifiDevices);
    }

    final statuses = await permissions.request();
    final granted = statuses.values.every((s) => s.isGranted || s.isLimited);
    if (!granted) return _permissionDeniedKey;

    // La recherche d'appareils proches exige aussi que la localisation (GPS) du téléphone soit ALLUMÉE,
    // pas seulement autorisée pour l'application.
    try {
      if (!await Permission.locationWhenInUse.serviceStatus.isEnabled) return _locationOffKey;
    } catch (_) {
      // État du service illisible : on laisse tenter la connexion plutôt que de bloquer à tort.
    }
    return null;
  }
}
