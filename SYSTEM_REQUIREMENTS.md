# System requirements

App version 1.0.0+1 · facts audited 2026-07-19 from the build config and code (sources cited inline; full audit in `docs/reviews/2026-07-19-review.md`).

## At a glance

| | Minimum | Recommended |
|---|---|---|
| OS | Android 8.0 (API 26) | Android 10+ (API 29) |
| CPU/ABI | arm64-v8a, armeabi-v7a (x86_64 bundled, emulator-only) | arm64-v8a |
| RAM | 2 GB for core editing | **4 GB for AI object removal** |
| Free storage to install | ~300 MB (universal APK, see below) | 1 GB+ headroom for projects/caches |
| Google Play services | not required | present (enables the ML Kit cut-out engine) |
| Network | never required — all AI models are bundled, nothing is downloaded | — |
| WhatsApp / Telegram | only needed for those export targets | — |

iOS, web, and desktop are **not supported** — there is no iOS target in the repo; this is an Android-only app.

## Android version

- `minSdk = 26` (Android 8.0 Oreo), `targetSdk`/`compileSdk` 36 (`android/app/build.gradle.kts:20`).
- The only API-level branch in the app is the Download path (`MainActivity.kt:126`): Android 10+ saves via `MediaStore.Downloads`; Android 8–9 falls back to writing `Environment.getExternalStoragePublicDirectory(DIRECTORY_DOWNLOADS)` directly. ⚠ **Caveat:** the manifest declares no `WRITE_EXTERNAL_STORAGE` permission, which Android 8–9 require for that path — Download very likely fails on API 26–28 and has never been tested there. Everything else (editing, AI, messenger export) is API-level-independent above 26.

## CPU architectures & install size

- The release APK is **universal**: arm64-v8a + armeabi-v7a + x86_64, **243,361,190 bytes (~232 MiB)**. No `abiFilters`, no ABI splits, no AAB config exist yet (`android/app/build.gradle.kts`). Roughly 140 MiB of any given install is native code (ONNX Runtime ~19–23 MB/ABI, the ffmpeg `libav*` family ~23–43 MB/ABI) for ABIs that device never loads.
- Bundled ML models add 35.5 MB of assets: MobileSAM decoder 16.5 MB + encoder 14.4 MB, U²-Netp 4.6 MB (`assets/models/`). By design these ship in the APK; the app never downloads model weights.
- With AAB/per-ABI splits (planned, `docs/decisions/0004-ffmpeg-animated-encoders.md`), per-device install drops to roughly 75–95 MB.

## Memory (RAM)

- Core editing (layers, text, bubbles, erase, static export): modest; any minSdk-class device.
- Background removal (bundled U²-Netp): 320×320 inference, small footprint, runs everywhere.
- **AI object removal (MobileSAM)** is the heavy feature: the once-per-photo encoder pass transiently added **~100 MB RSS** measured on the arm64 test device (Redmi 25010PN30G, Android 16 — encoder cold 2.4 s, first tap ~390 ms, warm taps ~190 ms), on top of a full-resolution photo decode. On 2–3 GB and Android Go devices this pass risks a low-memory kill mid-edit.
- ⚠ **The app currently ships no RAM/capability probe** — every engine's `isAvailable()` only checks that assets are bundled, so AI features are offered on every device regardless of viability. Flagged as a high-severity gap in the 2026-07-19 review (recommended gate: `ActivityManager.isLowRamDevice`/`totalMem` probe hiding the SAM tier on <3 GB devices).

## Google Play services

Optional. The "Built-in AI" cut-out engine is ML Kit subject segmentation (`google_mlkit_subject_segmentation`), which needs Play services and downloads its model module on first use. On devices without Play services (Huawei, custom ROMs) the registry falls through automatically to the bundled U²-Netp engine — background removal still works, with different quality/latency. ⚠ No pre-flight Play-services check exists yet; such devices currently pay one failed ML Kit round-trip per cut-out before the fallback runs (flagged in the review).

## Messenger integrations

- **WhatsApp export** requires `com.whatsapp` or `com.whatsapp.w4b` installed (checked via package manager; both are in the manifest `<queries>`). Enforced pack rules (`lib/features/export/compliance_validator.dart`): 3–30 stickers, uniformly static or animated, 512×512 WebP, static ≤100 KB, animated ≤500 KB and ≤10 s, tray icon 96×96 PNG ≤50 KB, 1–3 emoji per sticker. No minimum-WhatsApp-version check is performed anywhere; sticker support requires a WhatsApp from ~2018 or newer.
- **Telegram export** prefers a direct hand-off to `org.telegram.messenger`, its web build, or Challegram, falling back to the system share sheet — so Telegram is not strictly required to be installed. Formats: static 512² PNG/WebP; video stickers WebM VP9 with alpha, ≤256 KB, ≤3 s.
- Animated encoding uses the bundled LGPL-3.0 `ffmpeg_kit_flutter_new_video` (libvpx-vp9 + libwebp_anim); availability is probed at runtime by listing encoders, so a broken native lib degrades to an error rather than a crash.

## Permissions & privacy

The release manifest declares **zero permissions**. Photos arrive through the system photo picker, sharing goes through a non-exported `FileProvider`, and WhatsApp reads packs through a ContentProvider protected by `com.whatsapp.sticker.READ`. All AI inference is on-device; the app makes no network calls.

## Storage growth at runtime

- Projects and their image/mask assets live under app documents; orphaned assets are garbage-collected on cold launch and project delete.
- Each photo used with AI object removal caches a ~4 MB embedding under app support (`sam_embeddings/`). ⚠ This cache is currently unbounded and never pruned — ~50 photos ≈ 200 MB of permanent app data (flagged in the review; fix planned: move under cache dir + cap).

## Verified hardware

The only physically tested device is a Redmi 25010PN30G (HyperOS, Android 16, arm64, 8 GB RAM): install, editor, cut-out (U²-Netp + ML Kit), AI object removal, and the WhatsApp pack hand-off are device-verified there. Everything below that class — 2–4 GB RAM, armeabi-v7a hardware, Android 8–9, Play-services-free ROMs — is **untested**; the gaps called out above (no RAM gate, no Play-services probe, the API 26–28 download path) are exactly where low-end behavior is unknown.
