import java.util.Properties

val releaseProperties = Properties().apply {
    val file = rootProject.file("keystore.properties")
    if (file.exists()) file.inputStream().use(::load)
}
val storeFilePath = releaseProperties.getProperty("storeFile")
val storePassword = releaseProperties.getProperty("storePassword")
val keyAlias = releaseProperties.getProperty("keyAlias")
val keyPassword = releaseProperties.getProperty("keyPassword")
val hasConfiguredReleaseSigning = listOf(
    storeFilePath,
    storePassword,
    keyAlias,
    keyPassword,
).all { !it.isNullOrBlank() }

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "de.photo_vault.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "de.photo_vault.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val releaseSigning = if (hasConfiguredReleaseSigning) {
        signingConfigs.create("release") {
            storeFile = file(storeFilePath)
            this.storePassword = storePassword
            this.keyAlias = keyAlias
            this.keyPassword = keyPassword
        }
    } else null

    buildTypes {
        release {
            // Nie mit dem Debug-Schlüssel veröffentlichen. Die lokale,
            // gitignorierte Datei android/keystore.properties liefert die
            // vier nötigen Werte; ohne sie entsteht kein signierter Release.
            signingConfig = releaseSigning
        }
    }
}

tasks.configureEach {
    if (name == "packageRelease" || name == "signReleaseBundle") {
        doFirst {
            check(hasConfiguredReleaseSigning) {
                "Für einen Android-Release muss android/keystore.properties " +
                    "vollständig eingerichtet sein. Siehe keystore.properties.example."
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
