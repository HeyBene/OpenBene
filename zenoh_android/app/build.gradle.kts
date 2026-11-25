plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "io.openbene.zenoh"
    compileSdk = 35

    defaultConfig {
        applicationId = "io.openbene.zenoh"
        minSdk = 30
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }
}

dependencies {
    // Official Android build of the Zenoh Kotlin JNI binding.
    implementation("org.eclipse.zenoh:zenoh-kotlin-android:1.10.2")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
