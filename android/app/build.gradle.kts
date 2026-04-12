import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "app.feedbacktome"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.feedbacktome"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (!keystorePropertiesFile.exists()) {
                throw GradleException(
                    "Play Store yayını için android/key.properties gerekli. " +
                        "Şablon: android/key.properties.example — keystore: android/app/*.jks"
                )
            }
            keyAlias = keystoreProperties.getProperty("keyAlias")
                ?: error("key.properties: keyAlias eksik")
            keyPassword = keystoreProperties.getProperty("keyPassword")
                ?: error("key.properties: keyPassword eksik")
            storePassword = keystoreProperties.getProperty("storePassword")
                ?: error("key.properties: storePassword eksik")
            val storeFileProp = keystoreProperties.getProperty("storeFile")
                ?: error("key.properties: storeFile eksik")
            storeFile = file(storeFileProp)
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}
