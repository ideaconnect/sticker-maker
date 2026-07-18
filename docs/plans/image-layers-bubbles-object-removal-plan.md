# Plan: Multi-image polish · Comic bubbles v2 · AI object removal

Status: approved plan → GitHub milestones M9–M11
Date: 2026-07-19
Inputs: 3 codebase audits + model/license research (adversarially verified), this doc is their synthesis.

## 0. Where we actually are (audit findings)

The user asked for three "new" features. Two of them already exist in the codebase
in functional form; the plan below targets what is genuinely missing.

### Image layers — ALREADY WORKS, needs polish
Adding extra photos is wired end-to-end: Layers panel → "Add" → Take photo /
Choose photo / Paste image → `EditorController.addImageLayer` (no count limit).
Model, gestures, undo/redo, frames, cutout/erase/adjust (all per-selected-layer,
not hardwired), and `StickerRenderer` are generic over N image layers.

Real gaps (audit):
- Every `ImageLayer` row shows the same generic icon and the name "Photo" —
  indistinguishable with 2+ photos. No thumbnails, no auto-numbering.
- New layers land dead-center at identity transform, fully occluding the
  previous photo; hit-testing uses a fixed 440×440 square (ignores aspect), so
  tap-selecting the layer underneath is nearly impossible.
- Memory: `_MaskedImage` hand-decodes full-res (up to 2048²) `ui.Image` pairs
  per widget instance, bypassing ImageCache; multiplied by frame thumbnails.
  Real OOM risk on low-RAM devices.
- No asset GC: `img_*`/`mask_*` files are never deleted (layer remove, project
  delete, superseded erase masks). Frames share `assetPath`/`maskPath` after
  duplication → GC needs reference counting across frames (and the assets dir
  is global across projects).
- Misc: global "Cut out" badge (should be per-layer), stale doc comments
  (`layer.dart:74` claims relative paths; they are absolute), no multi-image
  widget tests.

### Comic bubbles — ALREADY SHIP, needs v2
`BubbleLayer` (speech/thought/shout, fill/stroke/text colors, tail offset,
Bangers) + `BubblePainter` vector rendering + export parity + templates + add
flow all exist. Ranked gaps (audit):
1. Tail is a `dx`-only slider (dy locked at 0.86); no on-canvas drag handle;
   tails can never point up; shout ignores the tail entirely (slider is a
   visible no-op for it).
2. WYSIWYG bug: long text CLIPS in preview but SPILLS outside the bubble in
   export (`TextPainter.layout` constrains width only). No auto-fit.
3. Shapes: thought is a plain ellipse (weakest look); no caption box, whisper
   (dashed), or cloud-scalloped thought.
4. Font family/size: model + controller support them, no UI (locked Bangers 26).
5. Polish: all bubble edits coalesce into one undo step; shadow elevation fixed
   (doesn't scale to export); `updateBubbleLayer(text:)` can rename layer to '';
   selecting a bubble doesn't switch to the Text tool; zero golden coverage
   (the painter's doc comment claims a golden test that doesn't exist).

### AI object removal — genuinely new
Cutout audit: tap → mask flow slots cleanly into the existing stack:
`EditorCanvas._onTap` (new branch) → `MaskMapper.canvasToMask` (already maps
canvas → source-image px, handling transform + letterbox) → object mask →
`subtract(current, object)` (new ~10-line helper) → `MaskStore.save` →
`setImageMask` (one undo step; rendering/export unchanged). Do NOT re-run
`MaskProcessing.process` on the result (`keepLargestComponent` would eat
surviving blobs); serialize with the existing `_strokeLock`.

A point-prompt engine does NOT fit `SegmentationEngine` (promptless; registry
fall-through between prompted/promptless engines is semantically invalid) →
parallel `ObjectSegmentationEngine` interface, reusing `OrtSegmenter`-style
sessions, `ModelConfig`, `MaskTensor`, `AlphaMask`.

Model research (license-verified for a paid closed-source app):

| Pick | License | Assets | Notes |
|---|---|---|---|
| Tier 1: connected-component erase | none (pure Dart) | 0 MB | <50 ms; works when tapped object is a disjoint alpha blob (very common in sticker cutouts) |
| Tier 2: **MobileSAM** | Apache-2.0 (code+weights, CONFIRMED) | ~25 MB fp16 (13 enc + 12 dec) | encoder once per photo (~1–2.5 s mid-range CPU/XNNPACK, precompute eagerly + cache embedding), decoder per tap (~10–50 ms) |
| Fallback: EfficientSAM-Ti | Apache-2.0 (CONFIRMED) | ~41 MB | better masks, slower |
| Phase 2 (optional): **MI-GAN 512** inpainting | MIT (CONFIRMED) | ~14–28 MB | fills holes when removed object overlapped the subject; 1–3 s one-shot |
| DISQUALIFIED: EdgeSAM | S-Lab **non-commercial** | — | fastest, but legally unusable here |

Latency corrections from verification: MobileSAM encoder is 81–411 ms on
flagship NPU (not 40 ms); budget 1–2.5 s on Redmi-class CPU via XNNPACK. NNAPI
is deprecated + useless for ViT — do not build on it.

Model acquisition follows the u2netp precedent: maintainer downloads weights,
we convert (samexporter or official script, opset 17, fp16 via
onnxconverter-common), validate IoU vs fp32 on fixture photos, document in
`assets/models/README.md`. No auto-downloading unvetted models.

## 1. Milestones and issues

### M9 — Multi-image editing polish (`area:editor`)
- **[IMG-1] Layer thumbnails + auto-naming** — real previews (decoded with
  `cacheWidth`) in `_LayerRow`; name new layers "Photo 2", "Photo 3"…; per-layer
  cut badge replaces the global one; fix stale comments.
- **[IMG-2] Selection UX with overlapping photos** — aspect-correct hit boxes
  (cache decoded aspect per assetPath in `_sizeOf`), cascade-offset newly added
  layers, keep Layers panel as fallback selector.
- **[IMG-3] Image memory hardening** — decode at target size everywhere
  (`instantiateImageCodec(targetWidth:)` for `_MaskedImage`, `cacheWidth` for
  `Image.file`), shared decode cache; verify on device with 4+ photo layers ×
  frames.
- **[IMG-4] Project asset GC** — reference-counted cleanup of `img_*`/`mask_*`
  across frames + projects: sweep on project delete, delete-layer GC, prune
  superseded erase masks.
- **[IMG-5] Multi-image UX affordance + tests** — "Add image" reachable outside
  the Layers tool (product call), widget tests for the multi-photo flows
  (add/select/cutout/reorder with 2+ photos).

### M10 — Comic bubbles v2 (`area:editor`)
- **[BUB-1] Draggable tail** — on-canvas tail handle (drag tip in bubble-local
  coords, full dx+dy incl. above-bubble tails); shout gets a jagged tail (or
  hides the control); thought-dot chain follows the tail.
- **[BUB-2] Bubble text auto-fit (WYSIWYG fix)** — binary-search font-size fit
  shared by preview and export; golden tests for all shapes (the promised-but-
  missing golden).
- **[BUB-3] More bubble shapes** — cloud-scalloped thought (replace ellipse),
  rectangular caption box, whisper (dashed); shape picker becomes wrap/scroll;
  new templates.
- **[BUB-4] Bubble font & size controls** — reuse text panel's font chips +
  size slider (model/controller already support it).
- **[BUB-5] Bubble polish pass** — undo granularity per property group, scaled
  shadow, rename-to-empty guard, tap-a-bubble auto-switches to its panel.

### M11 — AI object removal (`area:ai`)
- **[OBJ-1] Tap-to-remove tier 1: connected-component erase (no ML)** —
  "Remove object" mode in the cutout panel; tap → `MaskMapper` → CC labeling
  (4-conn, two-pass) → subtract component + feather seam → undoable. Ships
  standalone value before any model lands.
- **[OBJ-2] MobileSAM acquisition + ONNX conversion** — export encoder+decoder
  (opset 17, fp16), IoU-validate vs fp32, license file + README, size budget
  (consider Play Asset Delivery).
- **[OBJ-3] ObjectSegmentationEngine + two-session runtime** — parallel
  interface; encoder-once-per-photo with disk-cached embedding (keyed by asset
  hash), eager background precompute; decoder per tap; pre/post off the UI
  isolate (`Isolate.run`).
- **[OBJ-4] Remove-object UX integration** — router heuristic (disjoint blob →
  CC tier; else SAM decoder); busy states; refinement taps (positive/negative)
  against the cached embedding.
- **[OBJ-5] Device validation & performance pass** — Redmi measurements
  (encoder/decoder latency, peak RAM, APK delta), ProGuard check, fixture-based
  integration tests.
- **[OBJ-6] (Backlog) MI-GAN inpainting** — fill occlusion holes: crop-around-
  mask → inpaint at 512 → paste back; `assetPath` rewrite + mask update in one
  undo step (never overwrite the original file).

## 2. Sequencing & risks

Order: M9 → M10 → M11 (user's listed order; also cheapest-to-riskiest).
OBJ-1 is independent of OBJ-2/3 and could ship any time.

Top risks:
1. Low-RAM devices: multi-image decode memory (IMG-3) and SAM encoder peak RAM
   (OBJ-5) — both must be device-verified on the Redmi before closing.
2. APK size: +25 MB models on a ~200 MB paid app — evaluate Play Asset
   Delivery in OBJ-2.
3. UI-isolate jank: existing pre/post already runs on the UI isolate; OBJ-3
   moves it to `Isolate.run` (all TypedData, transferable).
4. Asset GC correctness (IMG-4): frames legitimately share asset paths —
   naive delete corrupts sibling frames; needs reference counting.
