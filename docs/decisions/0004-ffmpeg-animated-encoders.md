# ADR 0004 — Animated encoders: adopt ffmpeg_kit_flutter_new_video (supersedes part of ADR 0002)

**Status:** Accepted (2026-07-18). Supersedes ADR 0002's rejection of ffmpeg-kit; keeps ADR 0002's
own-NDK BSD build as the tracked hardening path (issue #72 / ANIM-7).

## Context

ADR 0002 chose "libvpx/libwebp via our own NDK + FFI build" and **rejected ffmpeg-kit** because it was
retired (Jan 2025, binaries pulled citing codec-patent uncertainty) and its typical builds are
LGPL/GPL. Since then two things changed:

1. **Product directive escalated**: transparent animated stickers for Telegram and WhatsApp are a
   *must-ship*, now — not a follow-up. The own-NDK route is a multi-week toolchain effort with CI
   maintenance; it was blocking the product's core promise.
2. **The ecosystem moved**: a maintained fork exists — `ffmpeg_kit_flutter_new_video` (pub.dev,
   verified publisher; Android binaries self-published to Maven Central as
   `com.antonkarpenko:ffmpeg-kit-video`). We **binary-inspected the AAR** (2026-07-18, v2.4.1 /
   FFmpeg n8.1.2): the configure line has **no `--enable-gpl`** (pure **LGPL-3.0**), **libvpx is
   statically linked with the VP9 encoder compiled in**, FFmpeg 8.1's libvpx-vp9 accepts `yuva420p`,
   and libavformat contains the WebM muxer **with alpha BlockAdditions**. `.so` files are
   16 KB-page-aligned. libwebp is included (`libwebp_anim` presence smoke-tested on device in #66).

Verified platform facts (full research: `docs/plans/animated-stickers-plan.md`):
- Telegram video stickers **require** WebM **VP9** (512 px side, ≤3 s, ≤30 fps, ≤256 KB, no audio);
  alpha is container-level (second VP9 stream in BlockAdditions, AlphaMode=1) and **only libvpx-vp9
  can encode it** — MediaCodec/hardware encoders and Android's muxers cannot.
- WhatsApp animated stickers **require animated WebP** (512², ≤500 KB, ≥8 ms frames, ≤10 s); Android
  has no platform encoder and no pub.dev package encodes it.

## Decision

Adopt **`ffmpeg_kit_flutter_new_video`, pinned exactly** (currently `2.4.1`), as the engine behind the
existing `AnimationEncoder` seam for both WebM VP9+alpha (Telegram) and animated WebP (WhatsApp).

- **Never** the default `ffmpeg_kit_flutter_new` package — that tier is GPL. Only the `_video` tier.
- Pin exact versions; upgrades are a deliberate reviewed change (re-verify the configure line has no
  `--enable-gpl` when bumping).
- Maven coordinates: `com.antonkarpenko:ffmpeg-kit-video` (pulled transitively by the plugin).

### License & patent posture (paid, closed-source app)

- **LGPL-3.0 + dynamic linking** (the FFmpeg `.so`s are separate shared objects in the APK) is
  compliant for a closed-source app: we ship the LGPL text in-app
  (`assets/licenses/LGPL-3.0-ffmpeg.txt`, registered in the license registry), attribute FFmpeg, and
  do not modify the library (if we ever do, those changes must be published).
- **Patent exposure** is materially narrower than generic FFmpeg use: our encode paths are VP9 (AOM/
  Google royalty-free grant), WebM, and WebP — not H.264/HEVC. Residual exposure from unused codecs
  compiled into the binary is accepted short-term and eliminated by the ANIM-7 exit path.

### Cost

~24 MB uncompressed arm64 install (~11–13 MB per-ABI download). Acceptable next to the existing ORT
runtime; reduced later by ANIM-7 (~3 MB/ABI) and per-ABI splits/App Bundle at release.

## Consequences

- ANIM-2/ANIM-3 implement the two encoders as FFmpegKit invocations over rendered PNG frame
  sequences — no FFI buffer plumbing; the `AnimationEncoder` seam and all its tests stay.
- ADR 0002's own-build route is **not dead**: it is the tracked hardening/optimization path (#72)
  that removes the third-party binary dependency and ~21 MB/ABI when priorities allow.
- If the fork is abandoned: we are pinned (builds stay reproducible) and the exit path is #72.
