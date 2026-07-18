# Model conversion — U²-Netp → ONNX

This workspace turns the U²-Netp PyTorch checkpoint into the ONNX the app ships
as its offline background-removal fallback (`BundledSegmentationEngine`, #28).
It is **build tooling, not part of the app** — nothing here is bundled.

## Why U²-Netp (not U²-Net full)

Both checkpoints were evaluated. **U²-Netp** (the "portable" small variant) is the
right model for a mobile app:

| Model      | Params | Checkpoint | ONNX bundled | Mask quality            | Verdict |
|------------|--------|------------|--------------|-------------------------|---------|
| U²-Netp    | 1.1 M  | 4.7 MB     | **4.4 MB**   | Excellent for the job   | **Ship** |
| U²-Net full| 44 M   | 176 MB     | ~168 MB      | Marginally sharper      | Too heavy |

U²-Net full would inflate the APK ~40×, need far more RAM, and run several times
slower on-device — for a background cut-out that is then feathered and hand-refined
in the Erase tool, the quality delta doesn't justify any of that. The bundled
engine's `ModelConfig` (input `[1,3,320,320]`, ImageNet mean/std) matches U²-Netp.

## Provenance

- **Architecture:** `u2net_arch.py` — verbatim from
  <https://github.com/xuebinqin/U-2-Net> (`model/u2net.py`), **Apache-2.0**.
- **Weights:** `u2netp.pth` — the standard `u2netp` salient-object checkpoint,
  **Apache-2.0**. Do **not** substitute `u2net_portrait` (non-commercial) or
  BRIA RMBG (CC BY-NC) — this is a paid app.
- **Output:** `assets/models/u2netp.onnx`
  - opset **17**, fp32, input `input` `[1,3,320,320]` NCHW, output `output`
    `[1,1,320,320]` sigmoid.
  - ops: Add, Concat, Constant, Conv, MaxPool, Relu, Resize, Shape, Sigmoid,
    Slice — all supported by ONNX Runtime Mobile.
  - **sha256** `698d9836dbe72f30ad947fe33ce676a88f7c5fb01d0ec6ed069f157b27b8c0ed`

## Reproduce

The `.pth` checkpoints are git-ignored (too large). Re-fetch them into this
directory, then:

```
pip install torch onnx onnxruntime onnxscript
python model_conversion/convert_u2netp.py
```

The script exports d0 (the fused main map) as a single output, verifies the
shape/sigmoid range under onnxruntime, and prints the sha256 above.
