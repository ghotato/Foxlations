import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The vendored eu.kanade.tachiyomi.* runtime models use kotlinx.serialization.
    id("org.jetbrains.kotlin.plugin.serialization")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

android {
    namespace = "com.foxlations.manga_reader"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
        // The vendored ApkBridge runtime (OkHttpExtensions.asObservableSuccess/awaitSuccess)
        // uses the older context-RECEIVERS syntax `context(Type)` (it targets Kotlin 2.1);
        // enable that so it compiles under our 2.2.20 (context parameters would require names).
        freeCompilerArgs += "-Xcontext-receivers"
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.foxlations.manga_reader"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Ship arm64 only. `flutter build --target-platform android-arm64`
        // constrains Flutter's own engine libs, but plugin AARs (media_kit,
        // ML Kit, rhttp, …) bundle every ABI, so the APK was carrying
        // armeabi-v7a (30 MB) and x86_64 (44 MB) it never needs — 74 MB of dead
        // weight. arm64 covers every device from ~2015 on (Play has required
        // 64-bit since 2019); x86_64 is emulators only.
        ndk {
            abiFilters.add("arm64-v8a")
        }
    }

    signingConfigs {
        if (keyPropertiesFile.exists()) {
            create("release") {
                keyAlias = keyProperties["keyAlias"] as String
                keyPassword = keyProperties["keyPassword"] as String
                storeFile = file(keyProperties["storeFile"] as String)
                storePassword = keyProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keyPropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
            // Extensions + the vendored runtime + kotlinx.serialization rely on generic type
            // metadata at runtime; R8 minification strips it ("TypeReference constructed
            // without actual type information"). Keep it off (as Mihon/ApkBridge do).
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // The eu.kanade.tachiyomi.* extension-API runtime is vendored (from ApkBridge,
    // Apache-2.0) into src/main/ext-runtime by scripts/vendor_ext_runtime.sh / CI. It's
    // gitignored (not our code), so populate it before building.
    sourceSets {
        getByName("main") {
            java.srcDir("src/main/ext-runtime")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ML Kit script models for non-Latin text recognition
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
    implementation("com.google.mlkit:text-recognition-japanese:16.0.1")
    implementation("com.google.mlkit:text-recognition-korean:16.0.1")
    implementation("com.google.mlkit:text-recognition-devanagari:16.0.1")

    // ── Tachiyomi/Mihon extension runtime ────────────────────────────────────────
    // Extensions are compiled `compileOnly` against the extension API, so the host app
    // must supply every eu.kanade.tachiyomi.* class + its deps at runtime. The API
    // classes are vendored from ApkBridge (Apache-2.0) by CI into src/main/kotlin; these
    // are the libraries they need, at the versions the current extensions expect.
    implementation("com.squareup.okhttp3:okhttp:5.0.0-alpha.16")
    implementation("com.squareup.okhttp3:logging-interceptor:5.0.0-alpha.16")
    implementation("com.squareup.okhttp3:okhttp-brotli:5.0.0-alpha.16")
    implementation("com.squareup.okio:okio:3.8.0")
    implementation("io.reactivex:rxjava:1.3.8")        // extension API still exposes RxJava 1.x
    implementation("io.reactivex:rxandroid:1.2.1")
    implementation("org.jsoup:jsoup:1.21.1")
    implementation("uy.kohesive.injekt:injekt-core:1.16.1")
    // Match keiyoushi's version catalog (serialization 1.11.0). Extensions' generated
    // @Serializable serializers are compiled against 1.11.0; an older runtime (1.7.3)
    // throws "AbstractMethodError: GeneratedSerializer.typeParametersSerializers()" when
    // deserializing their responses (Asura, etc.). Verified to compile under Kotlin 2.2.20.
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json-okio:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
    implementation("androidx.preference:preference-ktx:1.2.1")
}
