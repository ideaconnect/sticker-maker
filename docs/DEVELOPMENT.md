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
| Python | **3.12** | Branding tooling (Pillow **12.3.0** + numpy **1.26.4**, pinned in `tools/requirements.txt`) |
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
sdkmanager "system-images;android-35;google_apis;x86_64" "emulator"
avdmanager create avd -n sm_test -k "system-images;android-35;google_apis;x86_64" -d pixel_6
flutter emulators --launch sm_test
```

Hardware acceleration on Windows uses WHPX (Windows Hypervisor Platform); check it with
`emulator -accel-check`. Boots take ~20–40s with acceleration.

## Branding assets

`assets/branding/*.png` and everything under `android/app/src/main/res/mipmap*`
/ `drawable*` are **generated**. Do not hand-edit them — edit
`design/branding/app-icon-master.png` (the master artwork, not bundled) and
re-run, in this order:

```bash
python tools/build_branding.py          # master -> assets/branding/*.png (deps: tools/requirements.txt)
dart run flutter_launcher_icons         # launcher + adaptive + Android 13 monochrome layers
dart run flutter_native_splash:create   # splash drawables, styles.xml (incl. night variants)
python tools/optimize_res.py            # lossless re-encode of the generated res/ PNGs
```

The last step must follow the two Dart generators every time — both re-emit
unoptimised RGBA PNGs. It is lossless and idempotent;
`python tools/optimize_res.py --check` fails if it was skipped, and CI enforces
it on every PR (`.github/workflows/ci.yaml`, first step of the job). Install the
Python deps with `python -m pip install -r tools/requirements.txt` so local runs
match the CI pins — an unpinned Pillow can re-encode a byte smaller and make the
check disagree with CI.

`tools/build_branding.py` is deterministic (fixed-seed dither) and needs no
network or ImageMagick; its module docstring explains the layer geometry. The
generator configs live at the bottom of `pubspec.yaml`. Only
`assets/branding/logo.png` ships in the Flutter asset bundle (the in-app mark,
`lib/core/widgets/app_logo.dart`). The launcher label is
`android/app/src/main/res/values/strings.xml` (`@string/app_name`), intentionally
untranslated.

## Release builds

Two supported paths — see `docs/release/building-releases.md` for the full details:

```bash
flutter build appbundle                # Play Store upload; Play serves per-device installs
flutter build apk --split-per-abi      # per-ABI APKs for sideload / on-device testing
```

Release builds are restricted to the real-device ABIs (`arm64-v8a`, `armeabi-v7a`)
via variant packaging excludes in `android/app/build.gradle.kts` — each ABI carries
~60–76 MiB of ONNX Runtime + ffmpeg native code, and `x86_64` is emulator-only.
**Debug builds keep all ABIs**, so emulators are unaffected; `flutter run --release`
works on physical (arm) devices but not on x86_64 emulators.

## Testing

Three layers, fastest first:

| Layer | Command | Runs on |
|---|---|---|
| Unit + widget | `flutter test --exclude-tags golden` | host (Dart VM) |
| Golden | `flutter test --tags golden` | host — baselines are maintainer-generated, **excluded from CI** |
| End-to-end (integration) | `tools\run_e2e.ps1` | a real device / emulator |

### End-to-end (integration) tests

`integration_test/app_test.dart` drives the **real app on a device**, the way a user would:
it launches from `main`'s widget tree, walks the real router back stack, and exercises real
on-device file IO (persistence). This is what unit/widget tests can't cover.

```powershell
# Boots the sm_test emulator (creating it if needed), runs the suite, tears it down.
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run_e2e.ps1
#   -KeepEmulator   leave the emulator running for a faster next run
```

Or manually against any attached device:

```bash
flutter test integration_test -d <device-id>   # `flutter devices` to list ids
```

**Renderer note:** debug builds disable Impeller (see `android/app/src/debug/AndroidManifest.xml`)
so the app uses the Skia/OpenGLES renderer. The Android emulator's software Vulkan (SwiftShader)
is unstable under Impeller and crashes the emulator's GPU process, which makes headless E2E runs
impossible. **Release builds keep Impeller** for premium visual quality — only debug/test falls
back to Skia.

## Quality gates

```bash
python tools/optimize_res.py --check --strict
dart format --set-exit-if-changed .
flutter analyze
flutter test --exclude-tags golden
```

CI runs all four on every PR (see `.github/workflows/`). Match them locally before pushing.
The `optimize_res.py --check` gate runs first in CI because it needs no toolchain and catches
the one regression that is otherwise silent: branding regenerated without step 3.
The E2E suite needs an emulator/device and is run via `tools\run_e2e.ps1` (not yet in CI —
tracked for a future GitHub Actions Android-emulator job).
