# ADR 0002 — Animated WebP & WebM (VP9) encoding strategy

**Status:** Accepted (spike #41). Implementation split: pure-Dart seam now (#42a), native FFI + device
verification as a human-in-the-loop follow-up (#42b).

**Context.** Sticker Maker is a **paid, closed-source** Android-first Flutter app. It already renders
frames to transparent PNG (`dart:ui`) and animated GIF (`package:image`). It needs two more animated
formats, encoded **on-device** from already-rendered 512² transparent RGBA frames:

- **Animated WebP** for WhatsApp packs — 512×512, ≤ 500 KB, ≤ 10 s, min frame 8 ms.
- **WebM VP9** for Telegram video stickers — 512 px, ≤ 3 s, ≤ 256 KB, ≤ 30 fps, no audio, **transparent**.

Hard constraint: **no GPL/LGPL liability** for a paid closed-source app.

## Decision

| Format | Ship | Library | License | ~Added (arm64) |
|---|---|---|---|---|
| **Animated WebP** | `WebPAnimEncoder` (libwebpmux) via **dart:ffi** | libwebp + libwebpmux + libsharpyuv | **BSD-3 + PATENTS** | ~0.5–0.9 MB |
| **WebM VP9 (+alpha)** | libvpx VP9 encoder + libwebm/mkvmuxer via **dart:ffi** | libvpx + libwebm | **BSD-3 + PATENTS** | ~2–4 MB |

**Everything is BSD-3 + a royalty-free PATENTS grant — zero copyleft.** The only compliance action is
reproducing the BSD-3 + PATENTS notices (and any fallback's MIT notice) in the in-app OSS-licenses
screen. Total added binary ~3–5 MB per ABI — negligible next to the ~15–16 MB ONNX Runtime `.so`
already shipped. Ship arm64-v8a to users + x86_64 for the emulator via the existing ABI split.

### Why not the "obvious" options

- **ffmpeg / ffmpeg-kit** — **rejected.** Retired Jan 2025, binaries pulled, repo archived citing
  codec-patent uncertainty (toxic for a paid app); LGPL-v3 at best / GPL-v3 with typical encoders;
  13–40 MB per ABI; not 16 KB-page-ready. libvpx+libwebm give the same VP9+alpha output under BSD at a
  fraction of the size.
- **Any LGPL codec bundled in the APK** — **rejected.** Under an App Bundle + Play App Signing, Play
  re-signs per-ABI, so LGPL §6b (dynamic-link-to-system-copy) is unavailable and §6a (ship in
  relinkable form) plus the mandatory reverse-engineering-for-debug permission are impractical and
  legally gray for a paid EULA app.
- **MediaCodec VP9 + MediaMuxer as the *primary* Telegram path** — **rejected for shipping.** Android
  MediaCodec has no YUVA/alpha color format and MediaMuxer's WebM writer doesn't emit the Matroska
  alpha side-channel, so it flattens a cut-out sticker to an **opaque black box** — a visible defect
  for a transparent-sticker app. Kept only as an *opaque, feature-detected fallback* (and a first
  de-risking spike for the frame-feed/timestamp/budget pipeline).
- **flutter_image_compress / package:image / webp pub / webp_animation_flutter** — none encode
  *animated* WebP. **Transcoding GIF→WebP/WebM** — throws away alpha + full color; encode from RGBA.

### Transparent WebM, the hard part

libvpx has no `yuva420p` mode, so we replicate what ffmpeg does internally, in BSD code:
1. RGBA → I420, encode the **color** image as a normal VP9 stream;
2. encode the **alpha plane** as a separate alpha-only (Y-only) VP9 stream;
3. mux with mkvmuxer: set the video track **`AlphaMode=1`** and attach each frame's alpha via
   `AddFrameWithAdditional(..., BlockAddID=1)`. No audio track. `g_timebase` for exact fps; 2-pass RC
   (`rc_target_bitrate`) for a deterministic byte size. **Force VP9** (Telegram rejects VP8).

## Architecture (mirrors the SegmentationEngine seam)

~90 % is pure Dart around one native seam — **host-testable with a fake**, exactly like
`SegmentationEngine`/`FakeSegmenter`:

```
AnimationSpec        // maxBytes, maxEdge, maxFps, maxSeconds, loop, minFrameMs
abstract AnimationEncoder    // id, format('webp'|'webm'), isAvailable(), encode(frames, quality)
  ├─ LibWebpAnimationEncoder // dart:ffi → WebPAnimEncoder (device)
  ├─ Vp9WebmEncoder          // dart:ffi → libvpx+libwebm (device); MediaCodec opaque fallback
  └─ FakeAnimationEncoder    // tests
animationEncoderProvider.family(target)   // 'whatsapp'→webp, 'telegram'→webm; isAvailable() gated
```

- **Data path** reuses the GIF path verbatim: `StickerRenderer.renderImage(frame,size)` →
  `toByteData(rawRgba)` → `Uint8List` per frame.
- **Budget/caps** are pure Dart on top of one native encode, reusing `StickerEncoder.fitToBudget`:
  clamp per-frame ≥ 8 ms (WebP); cap ≤ 30 fps / ≤ 3 s by dropping frames (VP9); bisect quality /
  target-bitrate to hit ≤ 500 KB / ≤ 256 KB; reduce frame count / edge as last resort.
- **Build** adds `externalNativeBuild { cmake }` building libwebp+libwebpmux and libvpx+libwebm per
  ABI, NDK r27+ (16 KB pages), encode-only (drop decoders/VP8/high-bit-depth). Encode runs off the UI
  isolate.

## Host-testable vs device-only

- **Host (Dart, no `.so`):** the interface, registry/`isAvailable` fall-through + target routing,
  `fitToBudget` bisection, per-frame duration clamp, fps/duration caps, frame-count reduction,
  quality/bitrate selection — all against `FakeAnimationEncoder`. (RGBA extraction is already covered
  by the GIF path.)
- **Device-only (integration/thin instrumented):** the libwebp FFI encode; the libvpx+libwebm
  VP9-with-alpha encode + mux; MediaCodec availability; and end-to-end acceptance in **WhatsApp** and
  **Telegram** (incl. Telegram rendering it *transparent*).

## Risks to verify on-device (before shipping #42b)

1. **Telegram alpha end-to-end (HIGHEST):** our `AlphaMode=1` + per-frame `BlockAddID=1` two-stream VP9
   WebM actually renders transparent in Telegram's player and passes its uploader — the bespoke alpha
   mux glue is the single biggest unknown. Test a transparent sticker before committing.
2. **16 KB page-size** (Android 15+ upload gate): build libvpx/libwebp with NDK r27+ and confirm the
   `.so`s are aligned.
3. **Sizes:** measure the actual per-ABI `.so` bytes (libvpx figure is build-flag-dependent).
4. **WhatsApp WebP:** transparent animated WebP imports at 512², alpha preserved, frames ≥ 8 ms,
   ≤ 10 s, and the quality search reliably lands < 500 KB across 3–30 frames.
5. **libvpx 2-pass** deterministically hits ≤ 256 KB at 512/≤ 3 s/30 fps; container confirmed VP9.
6. **FFI/isolate memory:** ~30 MB of RGBA (512²×4×30) crosses the boundary without leaks/jank; free
   `WebPPicture`/vpx buffers deterministically.

## Follow-up split

- **#42a (safe, now):** the pure-Dart `AnimationEncoder` seam + `AnimationSpec` + `FakeAnimationEncoder`
  + registry + budget/cap helpers + host tests, and gate the export screen's WebP target on
  `isAvailable()` (graceful "coming soon" until the native encoder ships).
- **#42b (human-in-the-loop):** the NDK/CMake native builds, the dart:ffi bindings, the VP9-alpha mux,
  and on-device validation against WhatsApp + Telegram. This is a large native effort with legal/binary
  and device-acceptance gates that must not be committed blind.
