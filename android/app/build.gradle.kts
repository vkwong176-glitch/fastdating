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

fun keystoreProp(name: String): String =
    (keystoreProperties.getProperty(name) ?: "").trim()

/** 密碼以環境變數優先（便於在終端臨時覆寫、勿與 key.properties 內舊值打架）；未設定時再讀 key.properties。 */
fun passwordFromFileOrEnv(propName: String, envName: String): String {
    val fromEnv = (System.getenv(envName) ?: "").trim()
    if (fromEnv.isNotEmpty()) return fromEnv
    return keystoreProp(propName)
}

val releaseStoreFilePath = keystoreProp("storeFile")
val releaseStoreFile = if (releaseStoreFilePath.isNotEmpty()) {
    file(releaseStoreFilePath)
} else {
    null
}

val storePasswordResolved =
    passwordFromFileOrEnv("storePassword", "FD_STORE_PASSWORD")
val keyPasswordResolved =
    passwordFromFileOrEnv("keyPassword", "FD_KEY_PASSWORD")
        .ifEmpty { storePasswordResolved }

val hasReleaseKeystore = hasKeyProperties &&
    keystoreProp("keyAlias").isNotEmpty() &&
    keystoreProp("storeFile").isNotEmpty() &&
    releaseStoreFile?.exists() == true &&
    storePasswordResolved.isNotEmpty() &&
    keyPasswordResolved.isNotEmpty()

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
                keyAlias = keystoreProp("keyAlias")
                keyPassword = keyPasswordResolved
                storeFile = releaseStoreFile
                storePassword = storePasswordResolved
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
            // R8／資源縮減 — 顯著縮小上架 APK；規則見 [proguard-rules.pro]
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}
