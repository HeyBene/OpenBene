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
        // Optional local mirror for networks where Gradle's TLS to Maven Central
        // fails. Pass -PopenBeneMavenRepo=<path> to prepend it.
        providers.gradleProperty("openBeneMavenRepo").orNull?.let { localRepo ->
            maven { url = uri(localRepo) }
        }
        google()
        mavenCentral()
    }
}

rootProject.name = "OpenBeneZenohAndroid"
include(":app")
