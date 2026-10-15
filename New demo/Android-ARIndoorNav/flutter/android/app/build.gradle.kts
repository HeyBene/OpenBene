plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.openbene.arindoornav"
    compileSdk = 34
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    defaultConfig {
        applicationId = "com.openbene.arindoornav"
        minSdk = 24
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    // Compile the exact same native sources; there is one AR/BLE implementation.
    sourceSets {
        getByName("main") {
            java.srcDir("../../../app/src/main/java")
            res.setSrcDirs(listOf("../../../app/src/main/res"))
            assets.srcDir("../../../app/src/main/assets")
        }
        getByName("test") { java.srcDir("../../../app/src/test/java") }
    }
    packaging { resources.excludes += setOf("META-INF/DEPENDENCIES") }
}
flutter { source = "../.." }
dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("com.google.ar:core:1.42.0")
    implementation("com.google.mlkit:face-detection:16.1.7")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
