import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Identifiant stable de l'appareil (voir demande utilisateur : empêcher de
/// cumuler l'essai gratuit des jeux en recréant un compte sur le même
/// téléphone, voir GameTrialService côté backend) — androidId sur Android
/// (survit à la désinstallation, seulement remis à zéro par un retour aux
/// réglages d'usine), identifierForVendor sur iOS ; `null` si indisponible
/// (web, erreur), dans ce cas le serveur ne bloque simplement pas sur le
/// device, seul le verrou par compte s'applique.
class DeviceIdentifier {
  DeviceIdentifier._();

  static String? _cached;

  static Future<String?> get() async {
    if (_cached != null) return _cached;
    try {
      if (kIsWeb) return null;
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        _cached = (await info.androidInfo).id;
      } else if (Platform.isIOS) {
        _cached = (await info.iosInfo).identifierForVendor;
      }
    } catch (_) {
      return null;
    }
    return _cached;
  }
}
