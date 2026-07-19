plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "tech.idct.sticker_maker"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Play Store identity. Kept distinct from `namespace` (the code package) on purpose.
        applicationId = "tech.idct.stickermaker"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // WhatsApp sticker ContentProvider authority (#46), consumed by the
        // <provider android:authorities> placeholder in AndroidManifest.
        manifestPlaceholders["contentProviderAuthority"] =
            "tech.idct.stickermaker.stickercontentprovider"
    }

    testOptions {
        unitTests {
            // Robolectric needs the merged manifest + resources on the JVM
            // test classpath (StickerContentProviderTest).
            isIncludeAndroidResources = true
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            // Release builds shrink + obfuscate. ONNX Runtime and ML Kit resolve
            // their Java classes by name via JNI, so they must be kept explicitly
            // (see proguard-rules.pro) or on-device inference aborts the VM.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
    // JVM unit tests for the WhatsApp StickerContentProvider (Robolectric).
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16")
    testImplementation("androidx.test:core:1.7.0")
}

// With isIncludeAndroidResources, AGP's package<Variant>UnitTestForUnitTest
// reads the merged assets dir that Flutter's copyFlutterAssets<Variant> also
// writes into; Gradle 9 fails the build unless that dependency is explicit.
tasks.configureEach {
    val match = Regex("package(.+)UnitTestForUnitTest").matchEntire(name)
    if (match != null) {
        dependsOn("copyFlutterAssets${match.groupValues[1]}")
    }
}
