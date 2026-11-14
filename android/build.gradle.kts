allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Corrige le module Android du plugin screen_protector (voir demande
// utilisateur : blocage de capture d'écran dans le lecteur roman-photo) —
// son propre build.gradle (paquet tiers, non modifiable ici) vise le SDK 36
// avec un JVM target Kotlin auto-détecté à 21, incohérent avec son propre
// javac resté à 17 ("Inconsistent JVM-target compatibility").
subprojects {
    if (project.name != "screen_protector") return@subprojects

    // Depuis AGP 9, le build.gradle de ce plugin (paquet tiers, non
    // modifiable ici) ne s'applique plus LUI-MÊME le plugin Kotlin — il
    // parie sur le "Built-in Kotlin" natif d'AGP 9, inactif dans ce projet
    // (app/build.gradle.kts applique encore explicitement kotlin-android,
    // voir avertissement Flutter au build). Ses sources .kt ne sont alors
    // jamais compilées, d'où "cannot find symbol: ScreenProtectorPlugin"
    // au moment de la liaison (voir issue GitHub prongbang/screen_protector
    // #77, même bug). `withPlugin` (pas afterEvaluate/state.executed,
    // beaucoup trop tard ici : "KotlinPluginLifecycle cannot be started in
    // ProjectState 'EXECUTING'") réagit exactement au moment où AGP vient
    // d'être appliqué sur ce module, avant que son propre script ne décide
    // de ne PAS appliquer Kotlin lui-même.
    pluginManager.withPlugin("com.android.library") {
        if (!plugins.hasPlugin("org.jetbrains.kotlin.android")) {
            pluginManager.apply("org.jetbrains.kotlin.android")
        }
    }

    fun alignScreenProtector() {
        // Seul le JVM target Kotlin est réaligné, pas compileOptions (une
        // Property déjà "finalized" par AGP à ce stade — la modifier lève
        // "sourceCompatibility has been finalized") : son javac est déjà à
        // 17 (voir message d'erreur d'origine), seul le côté Kotlin (21,
        // auto-détecté) doit redescendre pour matcher. `kotlinOptions` (API
        // historique) a été retiré par une mise à jour du plugin Kotlin
        // Gradle ("Please migrate to the compilerOptions DSL") — remplacé
        // par `compilerOptions.jvmTarget`, seule API encore disponible.
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
    // `state.executed` : évite "Cannot run Project.afterEvaluate(Action)
    // when the project is already evaluated" si ce module a déjà fini de
    // s'évaluer au moment où ce bloc racine s'exécute pour lui (voir
    // evaluationDependsOn(":app") ci-dessus).
    if (state.executed) alignScreenProtector() else afterEvaluate { alignScreenProtector() }
}

// flutter_plugin_android_lifecycle (dépendance transitive de plusieurs
// plugins) exige compileSdk >= 36 chez tout module qui dépend de lui. Les
// plugins tiers compilés contre flutter.compileSdkVersion (34/35 avec le
// Flutter SDK actuel, voir settings.gradle.kts/app build.gradle.kts qui
// forcent déjà compileSdk=36 côté app) ne sont pas alignés — ex. file_picker
// ("file_picker is currently compiled against android-34... Update this
// project to use a newer compileSdk of at least 36"). Relève compileSdk à 36
// pour CHAQUE sous-projet Android (library ou application), sans toucher
// minSdk/targetSdk — rétrocompatible. `afterEvaluate` (pas `withPlugin`,
// essayé d'abord : trop tôt, écrasé ensuite par le `compileSdk =
// flutter.compileSdkVersion` du propre script du module) : il faut agir
// APRÈS que le script du sous-projet ait fixé sa propre valeur.
fun Project.alignCompileSdkTo36() {
    extensions.findByType<com.android.build.gradle.BaseExtension>()?.let { ext ->
        val current = ext.compileSdkVersion?.removePrefix("android-")?.toIntOrNull() ?: 0
        if (current < 36) ext.compileSdkVersion(36)
    }
}
subprojects {
    if (state.executed) alignCompileSdkTo36() else afterEvaluate { alignCompileSdkTo36() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
