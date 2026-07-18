# Animated transparent stickers — established facts & implementation plan

> Status: **approved research, ready to implement** · Date: 2026-07-18
> Supersedes the "wait for native encoders" stance of ADR 0002 with a concrete, verified route.
> This document is structured so each `### Issue:` block can be lifted verbatim into a GitHub issue.

## 0. Why this document

The app must deliver transparent **animated** stickers to Telegram and WhatsApp, and a working
transparent animated GIF export. This was researched against primary sources (official Telegram/WhatsApp
docs and repos, Matroska/WebM specs, libwebp API, pub.dev, Maven Central — including binary inspection
of candidate artifacts) with every load-bearing claim adversarially re-verified. Everything below marked
**[CONFIRMED]** traces to a primary source.

## 1. Established facts (the ground truth)

### 1.1 Telegram

- Telegram has exactly three sticker types: static (PNG/WEBP), **animated (.TGS = gzipped Lottie
  vector)**, and **video (.WEBM VP9)**. [CONFIRMED — core.telegram.org/stickers, /api/stickers]
- **TGS is infeasible for a photo/raster app**: pure vector Lottie, raster images explicitly on the
  prohibited-features list, ≤64 KB gzipped. Not our path. [CONFIRMED]
- **Video stickers are the target**: `.webm`, **VP9 codec (VP8 is rejected)**, one side **exactly
  512 px** (other ≤512), **≤3 s**, **≤30 FPS**, **≤256 KB**, **no audio stream**, uploaded **as a
  document** (`video/webm`). Looping is recommended, not validated. [CONFIRMED]
- **Transparency is supported** (verbatim in the MTProto docs) and carried at the **container level**:
  the alpha plane is a second VP9 stream stored per-frame in Matroska **BlockAdditional** elements
  (BlockAddID = 1), signalled by **AlphaMode = 1** on the video track. Server-side validation errors:
  `STICKER_VIDEO_NOWEBM`, `STICKER_VIDEO_BIG`, `STICKER_VIDEO_NODOC`, `STICKER_GIF_DIMENSIONS`. Alpha
  itself is NOT validated (opaque WebM is accepted). [CONFIRMED — Matroska/WebM specs, Telegram API]
- **FFmpeg's `-c:v libvpx-vp9 -pix_fmt yuva420p` produces exactly this**; `libvpx-vp9` is the only
  alpha-capable VP9 encoder — hardware/MediaCodec encoders cannot emit alpha. De-facto community
  pipeline: `ffmpeg -i in -r 30 -t 2.99 -an -c:v libvpx-vp9 -pix_fmt yuva420p
  -vf scale=512:512:force_original_aspect_ratio=decrease -b:v 400K out.webm`, lowering bitrate until
  ≤256 KB. [CONFIRMED]
- **GIF into Telegram chat ALWAYS loses transparency**: "GIFs are actually MPEG4 (h264) videos without
  sound; if the user tries to upload an actual GIF file, it will be automatically converted" (official
  docs). H.264 yuv420p has no alpha. No share-intent trick avoids it. [CONFIRMED]

### 1.2 WhatsApp

- Animated stickers are **animated WebP**, exactly **512×512**, **≤500 KB** (static: ≤100 KB), every
  frame duration **≥8 ms**, total duration **≤10 000 ms** (validator constants
  `ANIMATED_STICKER_FRAME_DURATION_MIN = 8`, `ANIMATED_STICKER_TOTAL_DURATION_MAX = 10*1000` in the
  official sample's `StickerPackValidator.java`). [CONFIRMED — github.com/WhatsApp/stickers]
- **First frame must be the complete image** ("WhatsApp ends the animation on the first frame after
  looping"); no loop-count validation. Packs are all-static or all-animated, 3–30 stickers, static
  96×96 tray ≤50 KB. WhatsApp validates with Fresco's `WebPImage` (frame count >1, frame durations,
  total duration, byte size, dimensions). [CONFIRMED]
- Delivery is the **identical ContentProvider + `ENABLE_STICKER_PACK` intent** we already ship — the
  only addition is `animated_sticker_pack` (bool in contents.json, int column in the metadata cursor),
  **both already implemented in our exporter and provider**. [CONFIRMED]
- **Android has no animated-WebP encoder API** (`Bitmap.compress` is single-frame; platform only
  decodes animated WebP) and **no pub.dev package encodes animated WebP** (checked `image`,
  `swipelab_webp`, etc.). The canonical encoder is **libwebp's `WebPAnimEncoder`** (`webp/mux.h`,
  BSD-3-Clause, full alpha, ms timestamps, loop count). [CONFIRMED]

### 1.3 GIF

- Our GIF export is now a correct transparent animated GIF (1-bit alpha palette; fixed in `89472af`).
  That is the ceiling of the format itself — GIF has no partial alpha.
- **Where transparency survives**: Discord, Slack, browsers, most gallery apps (Google Photos keeps the
  bytes but composites onto black in its viewer). **Where it dies**: Telegram and WhatsApp chats — both
  re-encode GIF→H.264 MP4 (no alpha), deterministically; Gboard-committed real GIF bytes are converted
  too. Sending "as file/document" preserves bytes but loses inline animated display. [CONFIRMED]
- Consequence: GIF stays a **general-purpose share target** (Discord/Slack/web); for Telegram/WhatsApp
  the app must route users to the real sticker pipelines (WebM / animated WebP), and the UI should say
  so instead of letting users discover flattened GIFs.

### 1.4 Encoder routes (evaluated for a closed-source paid app; GPL forbidden, LGPL-dynamic OK)

| Route | Verdict |
|---|---|
| **A. `ffmpeg_kit_flutter_new_video` (pub.dev fork of retired ffmpeg-kit)** | **CHOSEN.** Actively maintained (FFmpeg 8.1.2 rebuilt 2026-07-12, CVE-2026-8461 patched; verified publisher). Ships its own Maven Central binaries (`com.antonkarpenko:ffmpeg-kit-video`). **Binary-inspected**: configure line has NO `--enable-gpl` (pure **LGPL-3.0**), libvpx statically linked with the **VP9 encoder compiled in**, FFmpeg 8.1 libvpx-vp9 accepts `yuva420p`, libavformat contains the WebM muxer **with alpha BlockAdditions**. Also includes libwebp (`libwebp_anim` encoder — inferred from enabled libs, smoke-test on device). Cost: ~24 MB uncompressed arm64 install (~11–13 MB per-ABI download), .so files 16 KB-page-aligned. One dependency solves BOTH targets. |
| B. Own NDK build: libvpx + libwebm + libwebp via FFI | Follow-up optimization. All BSD-3-Clause, ~3 MB/ABI vs ~24 MB. Prior art: WebM project's own `webm-tools/alpha_encoder.cc` (~500 lines, BSD) encodes dual VP9 streams + `AddFrameWithAdditional()` + `SetAlphaMode(1)`; Chromium does the same in production. Real work (toolchains, CI, maintenance) — do it later if size or supply-chain concerns demand. |
| C. MediaCodec / media3 Transformer | **Dead end for alpha**: `MediaMuxer` has no per-sample side-data channel for BlockAdditions and media3's WebmMuxer lacks them too; hardware VP9 encoders can't emit alpha. VP9 *encode* is not even CDD-mandated (VP8 is). [CONFIRMED] |
| D. Pure Dart / existing plugins | Nothing exists (systematic pub.dev search). [CONFIRMED] |

**Decision: Route A now** (ships both targets with one LGPL dependency, verified contents), **Route B
as a tracked follow-up** for size/supply-chain hardening. FFmpeg is invoked with file-based frame
sequences (`%d.png` → output), so no FFI buffer plumbing is needed; our existing `AnimationEncoder`
seam stays, implemented by an FFmpeg-backed encoder.

License compliance for the paid app: LGPL-3.0 + dynamically-linked `.so` on Android is compliant;
ship the license text in the About screen's license registry (we already register font/OFL licenses)
and pin the exact dependency version, recording its Maven coordinates + SHA in the repo.

## 2. Architecture (what changes in the codebase)

Already in place (no work needed): `AnimationSpec` constants match the confirmed platform limits
exactly (WA 500 KB/10 s/8 ms min-frame; TG 256 KB/3 s/30 fps) · `AnimationPlanner` (fps/duration
capping) · `AnimationEncoder` seam + `FakeAnimationEncoder` · `ComplianceValidator` animated rules ·
`animated_sticker_pack` in exporter + ContentProvider · frame rendering (`StickerRenderer`) and the
straight-alpha raster path.

New pieces:

```
lib/features/export/
  ffmpeg_animation_encoder.dart   ← AnimationEncoder impl: frames→PNG temp dir→FFmpegKit session
  animated_export_service.dart    ← plan (AnimationPlanner) → render frames → encode → budget search
lib/features/packs/
  whatsapp_pack_exporter.dart     ← animated packs: per-sticker animated WebP instead of static WebP
  telegram_pack_exporter.dart     ← animated packs: .webm files + /newvideo guidance (exists, routes to webm)
```

Byte-budget strategy (per research):
- **Telegram ≤256 KB**: bitrate ladder search (e.g. 400K → 320K → 256K → 192K → 128K), then edge
  downscale (512→448→384) as last resort; `-t 2.99`, `-r ≤30`, `-an`.
- **WhatsApp ≤500 KB**: `libwebp_anim` quality ladder (q 75 → 60 → 45 → 30), then downscale; enforce
  ≥8 ms frames (AnimationPlanner already clamps) and ≤10 s.

## 3. Work plan — GitHub-issue-ready blocks

### Issue: [ANIM-1] Adopt ffmpeg_kit_flutter_new_video as the animated-encoder engine
- Add `ffmpeg_kit_flutter_new_video` (NOT the default GPL tier) pinned to an exact version; record
  Maven coordinates + version + rationale in `docs/decisions/0004-ffmpeg-animated-encoders.md` (new ADR
  amending 0002 with this plan's findings).
- Register the LGPL-3.0 license text in the About screen license registry.
- Smoke-test on device: run `ffmpeg -encoders` via FFmpegKit and assert `libvpx-vp9` and
  `libwebp_anim` are present; assert a trivial yuva420p webm encode succeeds. (This closes the one
  UNCERTAIN research item: libwebp_anim presence in the fork's binaries.)
- Acceptance: debug + release builds pass; `flutter analyze` clean; app size delta documented.

### Issue: [ANIM-2] FfmpegAnimationEncoder — WebM VP9 + alpha (Telegram)
- Implement `AnimationEncoder` (`id: ffmpeg-webm`, `format: webm`): write planned RGBA frames as PNGs
  to a temp dir, invoke `-framerate <fps> -i %d.png -c:v libvpx-vp9 -pix_fmt yuva420p -b:v <bitrate>
  -r <fps> -t 2.99 -an -vf scale=512:512:force_original_aspect_ratio=decrease out.webm`.
- Bitrate-ladder byte-budget search to ≤256 KB (spec: `AnimationSpec.telegramWebm`).
- `isAvailable()` = FFmpegKit present + libvpx-vp9 encoder listed (cached probe).
- Unit tests: command construction, ladder search with fake session runner. Device test: encode 3
  frames → assert `.webm` bytes, ≤256 KB, and (via `ffprobe` session) VP9 + alpha_mode side data.
- Acceptance: a real animated project exports a compliant .webm on device.

### Issue: [ANIM-3] FfmpegAnimationEncoder — animated WebP (WhatsApp)
- Same frame-sequence input, `-c:v libwebp_anim -lossless 0 -q:v <q> -loop 0 out.webp`; quality ladder
  to ≤500 KB (spec: `AnimationSpec.whatsappWebp`); enforce exact 512×512.
- Validate output with `package:image` decode: frameCount >1, all frame durations ≥8 ms, total ≤10 s
  (mirror WhatsApp's Fresco checks so we fail before WhatsApp does).
- Unit + device tests as ANIM-2.
- Acceptance: animated WebP decodes with correct frames/durations and passes our ComplianceValidator.

### Issue: [ANIM-4] Animated export pipeline + Export screen wiring
- `AnimatedExportService`: project → `AnimationPlanner.plan` → render frames (straight-alpha) →
  encoder → `EncodedSticker`. Progress reporting (frame render + encode phases) for the UI spinner.
- Export screen: Telegram target + animated mode → `.webm` (share as document, mime `video/webm`,
  updated @Stickers `/newvideo` guidance); WhatsApp target + animated → animated `.webp`; GIF target
  unchanged.
- Copy: when target is Telegram/WhatsApp and user picks GIF, surface "GIF loses transparency in
  Telegram/WhatsApp chats — use the sticker pipeline instead" (from §1.3).
- Acceptance: widget tests for target/format routing; existing 287-test suite stays green.

### Issue: [ANIM-5] Animated packs end-to-end (WhatsApp + Telegram)
- `WhatsAppPackExporter`: when `pack.animated`, encode each sticker as animated WebP (ANIM-3) instead
  of static; keep tray static 96×96 PNG; contents.json already carries `animated_sticker_pack`.
- `TelegramPackExporter`: when animated, export `.webm` files (ANIM-2) and keep the `/newvideo` deep
  link (already implemented).
- Enforce all-static-or-all-animated at pack level (validator exists — wire into pack add flows).
- Device verification: WhatsApp "Add to your stickers" dialog with an ANIMATED pack; Telegram @Stickers
  accepts an exported .webm via /newvideo (manual step, guided).
- Acceptance: on-device WhatsApp animated pack import succeeds; .webm accepted by @Stickers.

### Issue: [ANIM-6] GIF positioning + docs
- Keep GIF as general share target; document (in-app hint + docs) where transparency survives
  (Discord/Slack/web/galleries) and that messengers flatten it.
- Add compliance note to ComplianceValidator copy for the GIF target.
- Acceptance: copy reviewed, tests updated.

### Issue: [ANIM-7] (Follow-up, optional) Replace FFmpeg with own BSD NDK build
- Cross-compile libvpx + libwebm + libwebp (all BSD-3); C shim per `webm-tools/alpha_encoder.cc`
  prior art; FFI bindings behind the same `AnimationEncoder` seam; drop ~21 MB/ABI.
- Only after ANIM-1..5 ship and if size/supply-chain review demands it.

Dependency order: ANIM-1 → (ANIM-2 ∥ ANIM-3) → ANIM-4 → ANIM-5; ANIM-6 anytime; ANIM-7 later.

## 4. Risks & mitigations

| Risk | Mitigation |
|---|---|
| `libwebp_anim` missing from the fork's binaries (the one UNCERTAIN item) | ANIM-1 smoke test first; fallback: encode WebM first (Telegram unblocked), add webp-android (MIT JNI) or own libwebp FFI for WhatsApp |
| Fork abandonment / supply chain | Pin exact version + record SHA; ANIM-7 exit path documented |
| APK size +~12 MB per-ABI download | Per-ABI splits / App Bundle (already planned for release); document delta in ANIM-1 |
| 256 KB Telegram cap hard to hit for busy photos | Bitrate ladder + downscale + duration cap already in plan; surface actual size in UI (exists) |
| HyperOS device-install friction for verification | Resolved 2026-07-18 (see memory); keep fixture recipe from device-testing tips |

## 5. Source appendix (primary sources)

- core.telegram.org/stickers · core.telegram.org/api/stickers · core.telegram.org/api/gifs ·
  core.telegram.org/method/stickers.createStickerSet (error codes) · Bot API 5.7/6.6 changelogs
- github.com/WhatsApp/stickers — Android README, FAQ, `StickerPackValidator.java`
- Matroska codec spec (V_VP9 BlockAdditions/AlphaMode) · wiki.webmproject.org/alpha-channel
- FFmpeg docs (libvpx-vp9 yuva420p; libwebp_anim) · webm-tools `alpha_encoder.cc` (BSD prior art)
- pub.dev: `ffmpeg_kit_flutter_new_video` (verified publisher; Maven `com.antonkarpenko:ffmpeg-kit-video`,
  binary-inspected 2026-07-18) · libwebp `webp/mux.h` (WebPAnimEncoder, BSD-3) ·
  github.com/UdaraWanasinghe/webp-android (MIT JNI alternative)
- Full research transcripts: workflow `wf_54697bf4-664` (4 researchers + 4 adversarial verifiers, all
  claims CONFIRMED except the one flagged UNCERTAIN above).
