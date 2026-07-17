# M2 · Bundled fallback segmentation — decision (#27)

> Spike outcome for issue #27. The bundled model is the **offline fallback** used when Google Play
> services (and therefore ML Kit Subject Segmentation, the primary Android engine — #26) is
> unavailable, and as a cross-platform consistency baseline. All inference is on-device.

## Decision

| | Choice |
|---|---|
| **Model** | **U²-Netp** (`u2netp`) — the small general salient-object net from [xuebinqin/U-2-Net](https://github.com/xuebinqin/U-2-Net) (~1.13 M params) |
| **License** | **Apache-2.0 on both code and weights** — the cleanest in the field for a paid app |
| **Format** | ONNX, **fp32**, input `[1,3,320,320]` NCHW, output `[1,1,320,320]` sigmoid |
| **Size** | model ~4.7 MB + ORT native lib ~15–16 MB (arm64-v8a) ≈ **~20 MB** bundled |
| **Runtime** | **ONNX Runtime Mobile** (CPU/XNNPACK) via **`flutter_onnxruntime`** (masicai) ≥ 1.8.2 |
| **Bundle strategy** | **Bundle-as-asset** (well under the 30 MB preferred / 150 MB on-demand thresholds); ABI split (arm64-v8a shipped, x86_64 for the emulator) |
| **Toolchain risk** | **medium** (see "must-verify-on-device" below) |

### Why these

- U²-Netp is essentially the *only* model that is simultaneously **general-subject** (the hero case is
  "my dog at the park", so human-only models — MediaPipe/PP-HumanSeg/MODNet/ormbg — are out),
  **permissively licensed on the weights**, and **small enough to bundle**. High-quality general
  models are either non-commercial (BRIA RMBG — CC BY-NC) or too big (BiRefNet/BEN2/InSPyReNet).
- Its general salient-object training (DUTS-TR) matches ML Kit's general behaviour, so cut-outs stay
  consistent across Play / non-Play devices.
- `flutter_onnxruntime` pulls the **official Microsoft AAR from Maven Central** via platform channels
  — no vendored `.so`, no download scripts, and **no Kotlin/KGP or compileSdk lock imposed on the
  app**. That directly de-risks the toolchain pain this project has already hit (receive_sharing_intent
  compileSdk-37, pasteboard KGP). MIT-licensed.

### License traps explicitly avoided

- **BRIA RMBG-1.4 / 2.0** — CC BY-NC 4.0 (non-commercial). The single biggest trap; do **not** ship.
- **`u2net_portrait`** — trained on APDrawing (non-commercial), and human-portrait-only anyway.
- **IS-Net / DIS** (the sharpest general model) — **blocked**: weights carry no stated license and
  derive from the DIS5K dataset (academic/non-commercial). Do not ship until cleared in writing.

## Pipeline recipe (implementation-ready)

The pre/post recipe is **per-model** (U²-Net and IS-Net differ; a silent swap produces garbage), so it
lives in a `ModelConfig` object, never hard-coded.

**Pre-process** (photo → input tensor):
decode → **squash** resize to 320×320 (aspect-distorting, *not* letterbox — U²-Net trained on squashed
inputs; the distortion cancels on the way back) → extract **RGB** → `/255` → per-channel ImageNet
normalize `mean [0.485,0.456,0.406] std [0.229,0.224,0.225]` → pack **channel-planar NCHW** `[1,3,320,320]`
`Float32List` (R-plane, G-plane, B-plane).

**Post-process** (output → alpha mask): take main output `d0` (already sigmoid ~[0,1]) → **min-max
normalize** with a **low-range guard** (if `max-min < ~0.05`, treat as uniform to avoid stretching sensor
noise into a garbage mask) → upscale the **continuous** map to original W×H (linear/cubic) → quantize to
`uint8`. Emit the **continuous** 8-bit alpha (foreground = 255). Leave the hard threshold / feather /
largest-connected-component to the shared downstream post-processor (`MaskProcessing`, #25) — hardening
inside the engine would destroy the soft edges the feather step needs.

## Architecture (mirrors the ML Kit engine so it's a drop-in)

```
ModelConfig            // inputSize, mean, std, scale, layout=NCHW — carries the recipe
abstract Segmenter     // the single native seam: Future<Float32List> infer(Float32List nchw, shape)
  ├─ OrtSegmenter      // flutter_onnxruntime impl (device)
  └─ FakeSegmenter     // tests
BundledSegmentationEngine implements SegmentationEngine   // decode→pack→infer→unpack, pure Dart around the seam
```

**~90 % is pure Dart, host-unit-testable** with no device and no `.so`: decode (`package:image`),
squash resize, RGB extract, normalize+pack (`packTensor` — golden-vector test against a known 2×2
patch catches wrong mean/std, BGR, or planar-vs-interleaved cheaply), and the whole post chain
(`unpackMask`). Only `Segmenter.infer()` needs the plugin/device.

## Must verify on a device before shipping (why risk = medium)

1. **16 KB page-size compliance** — a Google Play **upload blocker** (deadline passed 2026-05-31).
   Confirm the bundled ORT `libonnxruntime.so` is 16 KB-aligned and passes Play's pre-launch check.
   This is a property of the plugin's prebuilt binary, not fixable in Gradle.
2. **Clean release build** of the compileSdk-36 / JDK-17 / Flutter-3.44 app with the plugin added
   (plugin declares compileSdk 35 / AGP 8.7 / Kotlin 2.1) — verify no conflict.
3. **Latency** of `u2netp@320²` on a min-spec device (~80–250 ms steady on SD 6xx/7xx; the ~30 ms
   figure is desktop). Run the first inference as an off-critical-path warm-up.
4. **Quality** on the hero case (dark/furry pet, busy park) — confirm downstream feather + largest
   component recovers acceptable edges; if not, fall back to the runner-up.
5. **Confirm** the exact `u2netp.onnx` export is NCHW + RGB via input-tensor metadata before wiring.
6. **No UI jank** — the plugin is bound to the platform main thread; verify inference offloads
   natively (fix is native-side threading, not an app-side isolate).
7. **x86_64 emulator** returns a correct end-to-end mask.

## Runner-up / escape hatches

- **Quality escape hatch:** full **U²-Net / `silueta`** (~43 MB, Apache-2.0, same recipe) if `u2netp`
  under-segments fur. Stays in the 30–150 MB band → still bundleable, or a future on-demand "HD" tier.
- **Size lever:** `tflite_flutter` + a LiteRT U²-Netp (~3–5 MB `.so`) *if* ORT `.so` size or 16 KB
  alignment becomes binding — but note the U²-Net→TFLite (NHWC) conversion/op risk.

## Next steps → #28

1. Add `flutter_onnxruntime` ≥ 1.8.2 + ProGuard keep `-keep class ai.onnxruntime.** { *; }`.
2. Fetch the standard `u2netp.onnx` (Apache-2.0, ~4.7 MB fp32) — **not** `u2net_portrait` — **verify
   its SHA + license provenance**, bundle under `assets/models/`.
3. ABI split (arm64-v8a + x86_64) so the ORT `.so` isn't multiplied across unused ABIs.
4. Implement `ModelConfig` + `Segmenter` + `BundledSegmentationEngine` with pure-Dart pre/post.
5. Host tests: `packTensor` golden-vector + `unpackMask`; a device-captured `Float32List` → golden-PNG
   post regression.
6. On-device: measure `.so` size, cold/warm latency, run Play's 16 KB check, validate mask IoU on
   3–4 fixtures.
7. Wire selection: ML Kit primary (Play present) → `u2netp` ORT fallback otherwise; warm up off the
   critical path.

> The model-binary fetch (step 2) and all device verification are a **human-in-the-loop** step — the
> `.onnx` weights must be obtained from a verified source with SHA/license checked, not pulled blindly.
