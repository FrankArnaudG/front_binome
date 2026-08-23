import 'package:flutter/foundation.dart';

/// Signal minimal pour forcer un rafraîchissement du Carnet de bord depuis
/// l'extérieur (ex. tap sur une notification push) — [TimelineScreen] garde
/// son état vivant dans l'[IndexedStack] de [MainTabScreen] et ne se
/// recharge donc jamais tout seul en y revenant, même si un nouvel envoi est
/// arrivé entre-temps.
class TimelineRefreshSignal extends ChangeNotifier {
  TimelineRefreshSignal._();
  static final instance = TimelineRefreshSignal._();

  void requestRefresh() => notifyListeners();
}
