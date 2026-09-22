import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

// android/key.properties (optionnel) : voir le bloc signingConfigs plus bas.
// Déclaré APRÈS plugins { } (Gradle exige que ce bloc passe en premier).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
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

    // Clé de publication : lue dans android/key.properties (jamais commité, voir
    // android/.gitignore). Tant que ce fichier n'existe pas, la version publiée
    // reste signée avec la clé de débogage comme jusqu'ici — ce qui garde les
    // mises à jour compatibles avec les APK déjà installés. Changer de clé
    // oblige les utilisateurs actuels à désinstaller/réinstaller : voir le
    // dossier de reprise (doc_binome) avant de créer key.properties.
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
