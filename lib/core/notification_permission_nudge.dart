import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Vérifie l'état de la permission notifications et ouvre les réglages
/// système pour l'activer — voir NotificationPermissionCard (Paramètres),
/// seul appelant : la carte reste affichée en continu tant que la
/// permission est refusée, jamais de plafond/cooldown à gérer ici.
class NotificationPermissionNudge {
  NotificationPermissionNudge._();
  static final NotificationPermissionNudge instance = NotificationPermissionNudge._();

  bool get _supported => !kIsWeb && Platform.isAndroid;

  /// `true` seulement si la permission a été explicitement refusée — le cas
  /// "jamais encore demandée" (premier lancement) est géré par le prompt
  /// système classique dans PushNotificationService.init, pas par cette
  /// relance.
  Future<bool> isPermissionDenied() async {
    if (!_supported) return false;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.denied;
  }

  Future<void> openSystemSettings() => openAppSettings();
}
