# Building releases

How to produce distributable release builds, and why the configuration looks
the way it does.

## Background: native code dominates install size

Each Android ABI carries its own full copy of the app's native libraries —
ONNX Runtime (~19–23 MiB) plus the ffmpeg `libav*`/`libsw*` family from
`ffmpeg_kit_flutter_new_video` (~23–43 MiB), roughly 60–76 MiB per ABI. A
universal ("fat") release APK with arm64-v8a + armeabi-v7a + x86_64 weighed
243 MB, of which ~140 MiB was native code the installing device never loads
(see `docs/reviews/2026-07-19-review.md`, "243 MB fat release APK").

Because of that, `android/app/build.gradle.kts` restricts **release** builds
to the two real-device ABIs:

- `arm64-v8a` — effectively every phone from the last decade
- `armeabi-v7a` — remaining 32-bit devices (minSdk 26 still allows them)

`x86_64` is emulator-only and is deliberately **not** shipped in release.
**Debug builds keep all ABIs**, so `flutter run` / debug installs on x86_64
emulators keep working unchanged.

The exclusion is implemented with the AGP variant packaging API
(`androidComponents { onVariants(release) { packaging.jniLibs.excludes } }`),
**not** `ndk.abiFilters`: buildType-level `abiFilters` is silently clobbered
under the Flutter Gradle plugin — verified empirically, the universal release
APK still packaged `lib/x86_64` byte-for-byte with the filter set. If you
ever rework this, re-verify with the checklist below; a silently ineffective
filter looks exactly like a working one.

## Supported release paths

### 1. Play Store: app bundle (preferred)

```bash
flutter build appbundle --release
# → build/app/outputs/bundle/release/app-release.aab
```

Google Play generates per-device split installs from the bundle automatically,
so each user downloads only their own ABI (plus density/language splits).
This is the only artifact uploaded to the Play Console.

### 2. Sideload / on-device testing: per-ABI APKs

```bash
flutter build apk --release --split-per-abi
# → build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
# → build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
# → build/app/outputs/flutter-apk/app-x86_64-release.apk   (byproduct — do not distribute)
```

Install the APK matching the device (`adb shell getprop ro.product.cpu.abi`
tells you which; any physical phone from the last decade is `arm64-v8a`).

Split builds are exempt from the release x86_64 exclusion (the Gradle guard
checks the `split-per-abi` property the Flutter tool passes), so each split
APK — including x86_64 — stays a valid artifact. That is why an
`app-x86_64-release.apk` still appears: it exists only because Flutter's
default target platforms include `android-x64`. Never distribute it; to skip
building it entirely:

```bash
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
```

## What is intentionally NOT configured

- **No unconditional `splits {}` block in Gradle.** Hard-enabling APK splits
  in the build file breaks `flutter run --release` workflows (the tool
  expects a single APK unless it passed `--split-per-abi` itself). Splits are
  opt-in per invocation via the flag above.
- **No universal release APK as a distribution artifact.** If you genuinely
  need one (e.g. a QA build for mixed devices), `flutter build apk --release`
  still produces it — it just contains only the two arm ABIs now.
- **`flutter run --release` targets physical (arm) devices only.** Release
  builds contain no x86_64 native code, so use debug mode on emulators.

## Checklist before uploading

1. `dart format --set-exit-if-changed .`, `flutter analyze`, `flutter test`
   all green (AGENTS.md gates).
2. `flutter build appbundle --release` succeeds.
3. Spot-check an APK's native payload when touching native/build config:

   ```bash
   flutter build apk --release --split-per-abi
   unzip -l build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "lib/*"
   ```

   The arm64 APK must list only `lib/arm64-v8a/` entries — no `x86_64`,
   no `armeabi-v7a`.
