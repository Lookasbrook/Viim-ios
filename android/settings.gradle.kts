pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "ViimAndroid"
include(":app")

// Aucun produit Android ne doit encombrer le dépôt canonique sur le SSD interne.
val devBuildsRoot = System.getenv("DEV_BUILDS_ROOT")
    ?: error("DEV_BUILDS_ROOT doit pointer vers le SSD de développement avant un build Android.")
gradle.beforeProject {
    layout.buildDirectory.set(file("$devBuildsRoot/Viim-ios/main/android/$name"))
}
