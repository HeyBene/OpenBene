plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.openbene.arindoornav"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.openbene.arindoornav"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        viewBinding = false
    }

    packaging {
        resources.excludes += setOf("META-INF/DEPENDENCIES")
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")

    // ARCore: session, camera background, augmented image tracking (the anchor).
    implementation("com.google.ar:core:1.42.0")

    // Follow mode: the operator's face box comes from the on-device face detector.
    implementation("com.google.mlkit:face-detection:16.1.7")
}
