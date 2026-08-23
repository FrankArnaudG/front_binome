import 'package:flutter/widgets.dart';

import 'locale_controller.dart';

/// Rend la langue personnelle choisie disponible à toute l'app — monté une
/// seule fois dans `main.dart`, comme [ThemeScope]. Les écrans qui n'ont
/// pas encore été migrés vers ce système restent simplement en français en
/// dur, sans avoir besoin de ce scope pour fonctionner.
class LocaleScope extends InheritedNotifier<LocaleController> {
  LocaleScope({super.key, required super.child}) : super(notifier: LocaleController.instance);

  static LocaleController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LocaleScope>();
    assert(scope != null, 'LocaleScope.of() appelé sans LocaleScope ancêtre.');
    return scope!.notifier!;
  }

  /// Raccourci : `LocaleScope.t(context, 'dashboard_welcome', {'name': x})`.
  static String t(BuildContext context, String key, [Map<String, String>? params]) => of(context).t(key, params);
}
