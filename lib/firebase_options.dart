import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Options Firebase générées à la main (projet `binome-9fd27`) plutôt que via
/// `flutterfire configure` — valeurs iOS reprises du GoogleService-Info.plist
/// téléchargé depuis la console Firebase (app iOS com.binome.app déjà créée).
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('DefaultFirebaseOptions n\'est pas configuré pour le web.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions n\'est configuré que pour Android/iOS — plateforme actuelle : ${Platform.operatingSystem}.',
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

  static const ios = FirebaseOptions(
    apiKey: 'AIzaSyBOhpivdmW1kkB-wG-WxCBrZgs9vcbc-8o',
    appId: '1:306017765426:ios:41fae94039488e139e542b',
    messagingSenderId: '306017765426',
    projectId: 'binome-9fd27',
    storageBucket: 'binome-9fd27.firebasestorage.app',
    iosBundleId: 'com.binome.app',
  );
}
