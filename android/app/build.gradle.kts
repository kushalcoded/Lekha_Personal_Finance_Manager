import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing, read from android/key.properties — gitignored, and the one
// file that must be backed up somewhere other than this machine. Android
// refuses to update an app signed with a different key, so if it is lost every
// install in the world can only move forward by uninstalling first, which
// wipes local data. See android/key.properties.example.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.example.personal_expanse_tracker"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.expanse.personal_tracker"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Debug keys keep `flutter run --release` working on a fresh
            // checkout; anything published must carry the real key, or the
            // in-app updater hands users an APK Android will not install.
            signingConfig = signingConfigs.getByName(
                if (hasReleaseKey) "release" else "debug"
            )
        }
    }
}

dependencies {
    // NotificationCompat, for the SMS detection notification the receiver posts
    // while the app is dead. Pulled in transitively by the embedding too, but
    // pinned here so a Flutter bump can't silently drop it.
    implementation("androidx.core:core-ktx:1.13.1")
}

flutter {
    source = "../.."
}
