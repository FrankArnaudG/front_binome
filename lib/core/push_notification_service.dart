import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'api_client.dart';
import 'app_router.dart';
import 'timeline_refresh_signal.dart';
import 'token_storage.dart';
import '../features/content/push_send_open_screen.dart';
import '../features/home/tab_navigation_controller.dart';
import '../models/app_user.dart';

/// Doit matcher le `channel_id` envoyé côté backend
/// (PushNotificationService::sendToUser) — sans un canal créé avec
/// l'importance MAX, Android affiche la notif directement dans le tiroir
/// sans bannière heads-up par-dessus l'écran (constaté en test réel).
const _highImportanceChannel = AndroidNotificationChannel(
  'binome_high_importance',
  'Notifications Binome',
  description: 'Battements de cœur, poèmes, cadeaux et autres envois de ton/ta binôme.',
  importance: Importance.max,
);

/// Reçoit les messages FCM alors que l'app est terminée/en arrière-plan — doit
/// rester une fonction top-level (contrainte du plugin, exécutée dans un
/// isolate séparé). Ne fait rien de plus que loguer : c'est le tray système
/// qui affiche la notification dans ce cas (payload `notification` déjà
/// rempli côté backend, voir PushNotificationService::sendToUser).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('FCM (arrière-plan) reçu : ${message.messageId}');
}

/// Enregistrement du jeton FCM auprès du backend + navigation au tap sur une
/// notification. Ne s'active que sur Android pour l'instant (iOS reporté,
/// voir DefaultFirebaseOptions) — `init()` est un no-op silencieux ailleurs.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final _localNotifications = FlutterLocalNotificationsPlugin();
  bool _tzReady = false;

  bool get _supported => !kIsWeb && Platform.isAndroid;

  /// `null` si non applicable (web/iOS) — sinon le statut réel, notamment
  /// [AuthorizationStatus.notDetermined] qui signale que l'utilisateur n'a
  /// encore jamais vu la demande système : c'est le seul cas où
  /// [showNotificationOptInPrompt] doit apparaître (voir AppRouter.routeAfterAuth),
  /// pas à chaque connexion.
  Future<AuthorizationStatus?> currentAuthorizationStatus() async {
    if (!_supported) return null;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return settings.authorizationStatus;
  }

  /// À appeler une fois au démarrage de l'app (avant toute connexion) — le
  /// canal doit exister pour qu'une notif reçue app fermée s'affiche déjà en
  /// heads-up, pas seulement celles reçues après un premier `init()`. Sert
  /// aussi à initialiser le plugin lui-même (nécessaire avant tout appel à
  /// [scheduleDailyReminder]), pas seulement à déclarer le canal.
  Future<void> createAndroidChannel() async {
    if (!_supported) return;
    await _localNotifications.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_highImportanceChannel);
  }

  /// Ne dépend jamais du fuseau du serveur — l'heure choisie dans
  /// [EveningRitualCard]/[MorningRitualCard] est une heure murale locale
  /// (`showTimePicker`), et la planification se fait directement sur
  /// l'appareil dans SON fuseau réel (détecté ici), pas celui du backend.
  Future<void> _ensureTimezone() async {
    if (_tzReady) return;
    tz_data.initializeTimeZones();
    try {
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (_) {
      // Repli silencieux sur UTC (fuseau par défaut du package `timezone`)
      // si la détection échoue — rare, ne doit jamais bloquer le reste.
    }
    _tzReady = true;
  }

  /// Rappel quotidien répété (rituel du soir/matin) — `id` doit être stable
  /// et propre à chaque rituel pour pouvoir le reprogrammer/annuler
  /// individuellement sans toucher à l'autre (voir RitualReminderService).
  Future<void> scheduleDailyReminder({
    required int id,
    required String title,
    required String body,
    required TimeOfDay time,
  }) async {
    if (!_supported) return;
    await _ensureTimezone();

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (scheduled.isBefore(now)) scheduled = scheduled.add(const Duration(days: 1));

    await _localNotifications.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _highImportanceChannel.id,
          _highImportanceChannel.name,
          channelDescription: _highImportanceChannel.description,
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      // "inexact" plutôt que "exact" : un rappel quotidien n'a pas besoin
      // d'une précision à la seconde, et l'exact nécessite une permission
      // spéciale (SCHEDULE_EXACT_ALARM) à demander séparément sur Android
      // 12+ — pas justifié ici, l'inexact se déclenche déjà à quelques
      // minutes près sans rien à configurer côté manifeste.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      // Ne matche que l'heure/minute, pas la date — répétition quotidienne
      // automatique gérée par le plugin, pas besoin de reprogrammer chaque
      // jour nous-mêmes.
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelReminder(int id) async {
    if (!_supported) return;
    await _localNotifications.cancel(id);
  }

  Future<void> init() async {
    if (!_supported) return;

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('FCM (premier plan) reçu : ${message.messageId}');
      TimelineRefreshSignal.instance.requestRefresh();
    });
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) _handleTap(initialMessage);

    await _registerToken();
    messaging.onTokenRefresh.listen((_) => _registerToken());
  }

  Future<void> _handleTap(RemoteMessage message) async {
    final context = AppRouter.navigatorKey.currentContext;
    if (context == null) return;

    Navigator.of(context).popUntil((r) => r.isFirst);
    // Index 0 : le Carnet de bord est devenu le premier onglet (page
    // d'accueil, voir TabNavigationController).
    TabNavigationController.instance.setIndex(0);
    TimelineRefreshSignal.instance.requestRefresh();

    // Ouvre directement l'envoi visé par-dessus le Carnet de bord (déjà
    // affiché ci-dessus en repli) plutôt que de laisser l'utilisateur le
    // rechercher — nécessite un profil en cache pour construire
    // SlideDetailScreen ; sans ça (ex. session perdue), on reste sur le
    // Carnet de bord déjà ouvert.
    final sendId = message.data['send_id'] as String?;
    if (sendId == null) return;
    final user = await _cachedUser();
    if (user == null || !context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PushSendOpenScreen(sendId: sendId, user: user)),
    );
  }

  Future<AppUser?> _cachedUser() async {
    final cached = await TokenStorage.instance.readUserJson();
    if (cached == null) return null;
    try {
      return AppUser.fromJson(jsonDecode(cached) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _registerToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await ApiClient.instance.post('/auth/device-tokens', body: {'token': token, 'platform': 'android'});
    } catch (e) {
      debugPrint('Enregistrement du jeton push ignoré (échec non bloquant) : $e');
    }
  }

  /// Retire le jeton courant côté serveur — à appeler à la déconnexion pour
  /// qu'un ancien utilisateur sur cet appareil ne reçoive plus les push d'un
  /// autre compte connecté ensuite.
  Future<void> unregisterToken() async {
    if (!_supported) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await ApiClient.instance.delete('/auth/device-tokens', body: {'token': token});
    } catch (e) {
      debugPrint('Retrait du jeton push ignoré (échec non bloquant) : $e');
    }
  }
}
