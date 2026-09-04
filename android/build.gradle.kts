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

// Corrige UNIQUEMENT le module Android du plugin screen_protector (voir
// demande utilisateur : blocage de capture d'écran dans le lecteur
// roman-photo) — son propre build.gradle (paquet tiers, non modifiable ici)
// vise le SDK 36 avec un JVM target Kotlin auto-détecté à 21, incohérent
// avec son propre javac resté à 17 ("Inconsistent JVM-target
// compatibility"). Scopé à CE seul module (project.name == "screen_protector")
// plutôt qu'à tous les sous-projets : une première tentative plus large avait
// cassé shared_preferences_android, qui a son propre couple Java/Kotlin déjà
// cohérent — pas la peine d'y toucher.
subprojects {
    if (project.name != "screen_protector") return@subprojects

    fun alignScreenProtector() {
        extensions.findByType<com.android.build.gradle.BaseExtension>()?.let { ext ->
            val current = ext.compileSdkVersion?.removePrefix("android-")?.toIntOrNull() ?: 0
            if (current < 36) ext.compileSdkVersion(36)
        }
        // Seul le JVM target Kotlin est réaligné, pas compileOptions (une
        // Property déjà "finalized" par AGP à ce stade — la modifier lève
        // "sourceCompatibility has been finalized") : son javac est déjà à
        // 17 (voir message d'erreur d'origine), seul le côté Kotlin (21,
        // auto-détecté) doit redescendre pour matcher.
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            kotlinOptions.jvmTarget = "17"
        }
    }
    // `state.executed` : évite "Cannot run Project.afterEvaluate(Action)
    // when the project is already evaluated" si ce module a déjà fini de
    // s'évaluer au moment où ce bloc racine s'exécute pour lui (voir
    // evaluationDependsOn(":app") ci-dessus).
    if (state.executed) alignScreenProtector() else afterEvaluate { alignScreenProtector() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
