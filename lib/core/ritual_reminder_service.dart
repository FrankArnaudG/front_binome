import 'package:flutter/material.dart';

import '../features/box/box_service.dart';
import '../models/box.dart';
import 'push_notification_service.dart';

/// Synchronise les rappels locaux (rituel du soir/matin) sur l'état actuel
/// de la Box — écoute [BoxService] (`ChangeNotifier`) plutôt que d'être
/// appelé ponctuellement depuis les cartes de réglages, pour rester à jour
/// même quand le changement vient de l'autre appareil du couple (après un
/// `fetchCurrent`), pas seulement d'une modification faite localement.
class RitualReminderService {
  RitualReminderService._();
  static final RitualReminderService instance = RitualReminderService._();

  static const _eveningId = 9001;
  static const _morningId = 9002;

  // Évite de reprogrammer inutilement à chaque notifyListeners() de Box
  // (ex. changement de score, de photo...) qui n'a rien à voir avec les
  // rituels — seule une vraie différence de valeur déclenche un appel au
  // plugin de notifications.
  String? _lastEveningKey;
  String? _lastMorningKey;

  /// À appeler une fois au démarrage (voir main.dart).
  void start() {
    BoxService.instance.addListener(_onBoxChanged);
    _onBoxChanged();
  }

  void _onBoxChanged() {
    final box = BoxService.instance.currentBox;
    if (box == null) {
      _cancelAll();
      return;
    }
    _sync(box);
  }

  Future<void> _sync(Box box) async {
    final eveningKey = '${box.eveningRitualEnabled}_${box.eveningRitualTime}';
    if (eveningKey != _lastEveningKey) {
      _lastEveningKey = eveningKey;
      if (box.eveningRitualEnabled) {
        await PushNotificationService.instance.scheduleDailyReminder(
          id: _eveningId,
          title: 'Rituel du soir 🌙',
          body: 'Un petit mot doux avant de dormir ?',
          time: _parseTime(box.eveningRitualTime),
        );
      } else {
        await PushNotificationService.instance.cancelReminder(_eveningId);
      }
    }

    final morningKey = '${box.morningRitualEnabled}_${box.morningRitualTime}';
    if (morningKey != _lastMorningKey) {
      _lastMorningKey = morningKey;
      if (box.morningRitualEnabled) {
        await PushNotificationService.instance.scheduleDailyReminder(
          id: _morningId,
          title: 'Rituel du matin ☀️',
          body: 'Un petit mot pour bien commencer la journée ?',
          time: _parseTime(box.morningRitualTime),
        );
      } else {
        await PushNotificationService.instance.cancelReminder(_morningId);
      }
    }
  }

  Future<void> _cancelAll() async {
    _lastEveningKey = null;
    _lastMorningKey = null;
    await PushNotificationService.instance.cancelReminder(_eveningId);
    await PushNotificationService.instance.cancelReminder(_morningId);
  }

  TimeOfDay _parseTime(String value) {
    final parts = value.split(':');
    return TimeOfDay(hour: int.tryParse(parts[0]) ?? 21, minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0);
  }
}
