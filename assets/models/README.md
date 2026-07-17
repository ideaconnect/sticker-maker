# Bundled segmentation model

The offline background-removal **fallback** engine (`BundledSegmentationEngine`, #28) loads its weights
from this directory. See `docs/M2_BUNDLED_SEGMENTATION_DECISION.md` for the full rationale.

## What to add

Drop the model here:

```
assets/models/u2netp.onnx
```

- **Model:** U²-Netp (`u2netp`) — the small general salient-object net from
  <https://github.com/xuebinqin/U-2-Net>.
- **License:** Apache-2.0 (code **and** weights). Use the standard `u2netp` salient-object checkpoint
  **only** — do NOT use `u2net_portrait` (non-commercial) or BRIA RMBG (CC BY-NC).
- **Format:** ONNX, fp32, input `[1,3,320,320]` NCHW, output `[1,1,320,320]` sigmoid. ~4.7 MB.

## Why it isn't committed here

The weights are a binary that must be fetched from a **verified source with its SHA and license
provenance checked** — that's a deliberate human-in-the-loop step, not an automated download. Until the
file is present, `BundledSegmentationEngine.isAvailable()` returns `false` and the segmentation registry
falls through gracefully (on Android, ML Kit remains the primary engine).

## After adding it

1. Confirm the export is **NCHW + RGB** via the input-tensor metadata (a wrong layout/channel order is a
   silent correctness bug).
2. Run the on-device checks in the decision doc (16 KB page-size compliance, latency, mask quality).
3. `git add` with Git LFS if the repo adopts it, or keep the binary out of git and fetch in CI.
