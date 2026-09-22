import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Trace un état de jeu ignoré parce qu'il est plus ancien que celui déjà affiché (voir
/// HasStateVersion côté serveur) — permet de confirmer, dans les journaux, qu'un message en retard
/// ou dans le désordre est bien la cause quand un écran « revenait en arrière ». Ne lève jamais.
void logStaleGameState(String game, {required int incoming, required int current}) {
  final message = 'Etat de jeu ancien ignoré ($game) : version $incoming < $current';
  debugPrint(message);
  try {
    FirebaseCrashlytics.instance.log(message);
  } catch (_) {
    // Crashlytics non initialisé (dev, tests) : sans importance.
  }
}
