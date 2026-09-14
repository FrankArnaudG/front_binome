plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.binome.app"
    // Forcé à 36 (au lieu de flutter.compileSdkVersion, qui vaut 35 avec le
    // Flutter SDK actuel) — le plugin screen_protector (voir demande
    // utilisateur : blocage de capture d'écran dans le lecteur roman-photo)
    // exige d'être compilé contre le SDK 36 ; rétrocompatible, ne change pas
    // minSdk/targetSdk.
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.binome.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Forcé à 23 (au lieu de flutter.minSdkVersion, qui vaut 21) — le
        // plugin `record` (voir NearbyComms : voix en direct en présentiel
        // connecté, capture micro brute PCM16) exige Android 6.0 minimum ;
        // part de marché Android 5.0/5.1 aujourd'hui négligeable (décision
        // utilisateur validée).
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
