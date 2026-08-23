import 'package:flutter/widgets.dart';

import 'box_service.dart';

/// Rend [BoxService] disponible à toute la sous-arborescence sans passer la
/// Box en paramètre de constructeur : `BoxScope.of(context).currentBox`.
/// Les widgets qui l'utilisent dans `build()` se reconstruisent
/// automatiquement quand la Box change (jumelage, rupture, réglages...).
class BoxScope extends InheritedNotifier<BoxService> {
  BoxScope({super.key, required super.child}) : super(notifier: BoxService.instance);

  static BoxService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<BoxScope>();
    assert(scope != null, 'BoxScope.of() appelé sans BoxScope ancêtre.');
    return scope!.notifier!;
  }
}
