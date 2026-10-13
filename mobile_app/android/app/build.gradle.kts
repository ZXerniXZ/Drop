import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val envKeystorePath = System.getenv("KEYSTORE_PATH")?.takeIf { it.isNotBlank() }
val envKeystorePassword = System.getenv("KEYSTORE_PASSWORD")?.takeIf { it.isNotBlank() }
val envKeyAlias = System.getenv("KEY_ALIAS")?.takeIf { it.isNotBlank() }
val envKeyPassword = System.getenv("KEY_PASSWORD")?.takeIf { it.isNotBlank() }
val envKeystoreValues = listOf(envKeystorePath, envKeystorePassword, envKeyAlias, envKeyPassword)
val hasEnvKeystore = envKeystoreValues.all { it != null }
if (envKeystoreValues.any { it != null } && !hasEnvKeystore) {
    throw GradleException(
        "Firma release incompleta: servono KEYSTORE_PATH, KEYSTORE_PASSWORD, KEY_ALIAS e KEY_PASSWORD.",
    )
}
if (hasEnvKeystore && !file(envKeystorePath!!).isFile) {
    throw GradleException("Keystore non trovato: $envKeystorePath")
}

val envVersionCode = System.getenv("VERSION_CODE")?.takeIf { it.isNotBlank() }?.let { raw ->
    raw.toIntOrNull() ?: throw GradleException("VERSION_CODE non è un intero: $raw")
}
val envVersionName = System.getenv("VERSION_NAME")?.takeIf { it.isNotBlank() }
if (envVersionCode != null && envVersionCode <= 38) {
    throw GradleException("versionCode $envVersionCode deve essere > 38 (ultimo pubblicato su Play).")
}

android {
    namespace = "xyz.drop.app"
    compileSdk = maxOf(flutter.compileSdkVersion, 36)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "xyz.drop.app"
        minSdk = 24
        targetSdk = 36
        versionCode = envVersionCode ?: flutter.versionCode
        versionName = envVersionName ?: flutter.versionName
    }

    signingConfigs {
        if (hasEnvKeystore || hasReleaseKeystore) {
            create("release") {
                if (hasEnvKeystore) {
                    keyAlias = envKeyAlias!!
                    keyPassword = envKeyPassword!!
                    storeFile = file(envKeystorePath!!)
                    storePassword = envKeystorePassword!!
                } else {
                    keyAlias = keystoreProperties["keyAlias"] as String
                    keyPassword = keystoreProperties["keyPassword"] as String
                    storeFile = file(keystoreProperties["storeFile"] as String)
                    storePassword = keystoreProperties["storePassword"] as String
                }
            }
        }
    }

    buildTypes {
        release {
            // In CI la firma arriva dalle variabili d'ambiente. In locale, da android/key.properties.
            // Senza nessuna delle due resta la chiave di debug: Play non accetta quell'AAB.
            signingConfig = if (hasEnvKeystore || hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    implementation("androidx.activity:activity-ktx:1.10.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
