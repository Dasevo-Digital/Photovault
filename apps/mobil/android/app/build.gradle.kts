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
    namespace = "de.dasevo.photovault"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Die Kennung der App im Store (de.dasevo.<app>); die Testvariante
        // hängt ".test" an und liegt neben der echten. Die Telefon-Bauten
        // des Desktop-Projekts heissen de.dasevo.photovault.desktop.
        applicationId = "de.dasevo.photovault"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Der Name unter dem Symbol kommt je Variante aus resValue.
    buildFeatures {
        resValues = true
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
        debug {
            applicationIdSuffix = ".test"
            resValue("string", "app_name", "Photo Vault (Test)")
        }
        getByName("profile") {
            applicationIdSuffix = ".test"
            resValue("string", "app_name", "Photo Vault (Test)")
        }
        release {
            resValue("string", "app_name", "Photo Vault")
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
