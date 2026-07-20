import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Play upload signing. The keystore and its passwords live in <repo>/secrets/,
// which .gitignore excludes as a whole directory — no key material is ever
// committed, and the path is absolute in key.properties so it resolves from any
// working directory or git worktree.
//
// The file is deliberately optional: a fresh clone or a CI job without the
// secrets must still be able to run `flutter run --release` and the Robolectric
// suite. When it is missing we fall back to the debug keys and warn loudly,
// because a debug-signed artifact looks perfectly normal locally and is only
// rejected once you try to upload it.
// SIGNING_KEY_PROPERTIES lets a build that is not rooted in the developer's main
// checkout (a git worktree, a CI runner, a release box) point at the real file.
// secrets/ is gitignored, so it does NOT exist in a fresh worktree, and the
// repo-relative default silently resolves to nothing there.
val keystorePropertiesFile =
    System.getenv("SIGNING_KEY_PROPERTIES")?.let { file(it) }
        ?: rootProject.file("../secrets/key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}
val hasUploadKey = keystorePropertiesFile.exists()

// Hard-fail the Play artifact rather than emit a debug-signed one. `flutter build`
// swallows Gradle's configuration-time warnings, so a warning here is invisible in
// practice: the build reports success and you only learn the truth when Play
// rejects the upload. `assembleRelease` is deliberately NOT covered - it backs
// `flutter run --release`, which must keep working without the secrets.
if (!hasUploadKey && gradle.startParameter.taskNames.any { it.contains("bundleRelease", true) }) {
    throw GradleException(
        "Cannot build a release bundle: no upload key at $keystorePropertiesFile.\n" +
            "The signing material lives in <repo>/secrets/ (gitignored). Either build from a " +
            "checkout that has it, or set SIGNING_KEY_PROPERTIES to its absolute path.",
    )
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

    signingConfigs {
        if (hasUploadKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                // The upload keystore is PKCS#12 (keytool deprecates JKS). Stated
                // explicitly rather than relying on the JDK's default store type,
                // so the build does not change meaning under a different JDK.
                storeType = keystoreProperties.getProperty("storeType") ?: "PKCS12"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasUploadKey) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "WARNING: secrets/key.properties not found — signing the release build " +
                        "with DEBUG keys. This artifact cannot be uploaded to Google Play.",
                )
                signingConfigs.getByName("debug")
            }

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
