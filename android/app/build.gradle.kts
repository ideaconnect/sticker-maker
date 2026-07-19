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

// Release builds ship only real-device ABIs (arm64-v8a, armeabi-v7a). Every
// ABI carries ~60-76 MiB of native code (ONNX Runtime + the ffmpeg libav*
// family), and x86_64 is emulator-only — shipping it fattened the universal
// APK to 243 MB (docs/reviews/2026-07-19-review.md, "243 MB fat release APK").
//
// This uses the variant packaging API because buildType-level ndk.abiFilters
// is silently clobbered under the Flutter Gradle plugin — verified
// empirically: with the filter set, the universal release APK still packaged
// lib/x86_64 byte-for-byte. Scoped to release variants so debug builds keep
// all ABIs and x86_64 emulators work unchanged.
//
// Skipped when the Flutter tool requests `--split-per-abi` so the x86_64
// split APK (a never-distributed byproduct, see
// docs/release/building-releases.md) stays a valid artifact.
val isSplitPerAbiBuild =
    project.findProperty("split-per-abi")?.toString()?.toBoolean() ?: false
if (!isSplitPerAbiBuild) {
    androidComponents {
        onVariants(selector().withBuildType("release")) { variant ->
            variant.packaging.jniLibs.excludes.add("**/x86_64/**")
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
