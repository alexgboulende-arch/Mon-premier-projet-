plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.buteo.buteo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Requis par flutter_local_notifications (notifications programmées).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Identifiant définitif sur le Play Store : ne plus le changer après la première publication.
        applicationId = "com.buteo.pronostics"
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

    // Clé de TEST, publique : elle permet seulement d'installer les versions de test
    // les unes par-dessus les autres. La clé du Play Store sera différente et secrète.
    // Clé d'envoi Play Store : fournie par GitHub Actions (secrets), jamais dans le dépôt.
    val uploadKeystore = System.getenv("BUTEO_UPLOAD_KEYSTORE")

    signingConfigs {
        create("test") {
            storeFile = file("../keystores/buteo-test.keystore")
            storePassword = "buteo-test"
            keyAlias = "buteo-test"
            keyPassword = "buteo-test"
        }
        if (uploadKeystore != null) {
            create("upload") {
                storeFile = file(uploadKeystore)
                storePassword = System.getenv("BUTEO_UPLOAD_STORE_PASSWORD")
                keyAlias = System.getenv("BUTEO_UPLOAD_KEY_ALIAS")
                keyPassword = System.getenv("BUTEO_UPLOAD_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("upload") ?: signingConfigs.getByName("test")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
