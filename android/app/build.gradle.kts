import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeyProperties = keystorePropertiesFile.exists()

if (hasKeyProperties) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun requiredKeystoreValue(name: String): String =
    (keystoreProperties.getProperty(name) ?: "").trim()

val releaseStoreFilePath = requiredKeystoreValue("storeFile")
val releaseStoreFile = if (releaseStoreFilePath.isNotEmpty()) {
    file(releaseStoreFilePath)
} else {
    null
}
val hasReleaseKeystore = hasKeyProperties &&
    requiredKeystoreValue("keyAlias").isNotEmpty() &&
    requiredKeystoreValue("keyPassword").isNotEmpty() &&
    requiredKeystoreValue("storePassword").isNotEmpty() &&
    releaseStoreFile?.exists() == true

android {
    namespace = "com.fastdating1.app"
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
        applicationId = "com.fastdating1.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = requiredKeystoreValue("keyAlias")
                keyPassword = requiredKeystoreValue("keyPassword")
                storeFile = releaseStoreFile
                storePassword = requiredKeystoreValue("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // 在提供正式 keystore 前先回退到 debug，避免目前無法出包時整個建置失效。
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isDebuggable = false
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
