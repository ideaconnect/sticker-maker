# Development environment

This documents how to get a working Sticker Maker build environment. It is **Windows-first**
(the primary development machine) with notes for macOS/Linux. Everything installs into
`%USERPROFILE%\dev` and requires **no administrator rights**.

> Implements issue #10. The exact toolchain used by CI and the maintainers is pinned below —
> match these versions to avoid "works on my machine" drift.

## Pinned toolchain

| Tool | Version | Notes |
|---|---|---|
| Flutter | **3.44.6** (stable) | Bundles Dart **3.12.2** |
| JDK | **Temurin 17** (LTS) | Required by Gradle / the Android build |
| Android command-line tools | **15859902** | `sdkmanager` / `avdmanager` |
| Android platform | **android-36** (compileSdk) | Installed via `sdkmanager` |
| Android build-tools | **36.0.0** | |
| Android min SDK | **26** (Android 8.0) | App runtime floor |
| Gradle | provided by the Flutter Android template | Uses the Gradle wrapper |

> If `flutter doctor` reports a different required Android platform/build-tools version after a
> Flutter upgrade, install that version with `sdkmanager` and update this table.

## Automated setup (Windows)

The repo ships the exact installer the maintainers use. From a PowerShell prompt:

```powershell
# 1. Download + extract JDK 17, Flutter, and Android cmdline-tools into %USERPROFILE%\dev,
#    set persistent env vars, and pre-accept SDK licenses.
powershell -NoProfile -ExecutionPolicy Bypass -File tools\install_tools.ps1

# 2. Install the Android SDK packages, point Flutter at the SDK/JDK, and run flutter doctor.
powershell -NoProfile -ExecutionPolicy Bypass -File tools\setup_sdk.ps1
```

Both scripts are idempotent — safe to re-run. After they finish, **open a new terminal** so the
updated `PATH` / `JAVA_HOME` / `ANDROID_SDK_ROOT` take effect.

### What gets installed where

```
%USERPROFILE%\dev\
  jdk-17\                       JAVA_HOME
  flutter\                      Flutter SDK  (flutter\bin on PATH)
  android-sdk\                  ANDROID_SDK_ROOT / ANDROID_HOME
    cmdline-tools\latest\bin\   sdkmanager, avdmanager
    platform-tools\             adb
    platforms\android-36\
    build-tools\36.0.0\
```

Environment variables set (User scope): `JAVA_HOME`, `ANDROID_SDK_ROOT`, `ANDROID_HOME`, and
`PATH` gains `flutter\bin`, `jdk-17\bin`, `cmdline-tools\latest\bin`, `platform-tools`.

## Manual setup (macOS / Linux)

1. Install a JDK 17 (`brew install temurin@17` / your distro's `openjdk-17-jdk`).
2. Install Flutter 3.44.6 from <https://docs.flutter.dev/get-started/install> (or `fvm`).
3. Install the Android command-line tools, then:
   ```bash
   sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
   yes | sdkmanager --licenses
   flutter config --android-sdk "$ANDROID_SDK_ROOT" --jdk-dir "$JAVA_HOME"
   ```
4. `flutter doctor` — resolve anything not related to Xcode unless you're building for iOS.

iOS builds require macOS + Xcode; see milestone **M8**.

## Verify

```bash
flutter doctor -v      # Android toolchain must be a green check
flutter --version      # 3.44.6, Dart 3.12.2
```

A clean Android toolchain in `flutter doctor` is the bar for this issue. The
"Chrome"/"Visual Studio"/"Xcode" categories are irrelevant to the Android target and may show
warnings.

## Running the app

```bash
flutter pub get
flutter run                       # on a connected device / emulator
flutter build apk --debug         # produces build/app/outputs/flutter-apk/app-debug.apk
```

### Android emulator (optional, no physical device)

```bash
sdkmanager "system-images;android-34;google_apis;x86_64" "emulator"
avdmanager create avd -n pixel -k "system-images;android-34;google_apis;x86_64" -d pixel_6
flutter emulators --launch pixel
```

## Quality gates

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

CI runs all three on every PR (see `.github/workflows/`). Match them locally before pushing.
