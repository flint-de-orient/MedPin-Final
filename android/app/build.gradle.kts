plugins {
    id("com.android.application")
    id("kotlin-android")
    // Reads google-services.json (Firebase phone sign-in).
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.fdo.medpin"
    compileSdk = flutter.compileSdkVersion
    // NDK 28.2: required by the jni plugin (NDKs are backward compatible).
    ndkVersion = "28.2.13676358"

    compileOptions {
        // Desugaring: scheduled notifications (medicine alarms) on older Android versions.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.fdo.medpin"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Firebase Auth needs Android 6.0 (API 23) or newer.
        minSdk = maxOf(flutter.minSdkVersion, 26) // Health Connect needs Android 8+
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

// App lock (local_auth): the biometric prompt needs an AppCompat theme on Android 8 and below.
dependencies {
    implementation("androidx.appcompat:appcompat:1.7.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Avoids a reported crash with desugaring on Android 12L+.
    implementation("androidx.window:window:1.0.0")
    implementation("androidx.window:window-java:1.0.0")
}
