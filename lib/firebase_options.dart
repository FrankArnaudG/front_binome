import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Options Firebase générées à la main (projet `binome-9fd27`) plutôt que via
/// `flutterfire configure` — Android uniquement pour l'instant, iOS reporté
/// tant que l'inscription Apple Developer Program n'est pas active.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('DefaultFirebaseOptions n\'est pas configuré pour le web.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions n\'est configuré que pour Android (iOS à venir) — plateforme actuelle : ${Platform.operatingSystem}.',
        );
    }
  }

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyDJMQ6UUzwaJ7uVnWvyrGQOSES2How_8ok',
    appId: '1:306017765426:android:0da88cd82c72d4529e542b',
    messagingSenderId: '306017765426',
    projectId: 'binome-9fd27',
    storageBucket: 'binome-9fd27.firebasestorage.app',
  );
}
