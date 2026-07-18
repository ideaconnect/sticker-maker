# Bundled segmentation model

The offline background-removal **fallback** engine (`BundledSegmentationEngine`, #28) loads its
weights from this directory. See `docs/M2_BUNDLED_SEGMENTATION_DECISION.md` for the full rationale.

## Shipped file

```
assets/models/u2netp.onnx   ← bundled (pubspec lists this exact file)
```

- **Model:** U²-Netp (`u2netp`) — the small salient-object net from
  <https://github.com/xuebinqin/U-2-Net>, **Apache-2.0** (code and weights).
- **Format:** ONNX opset 17, fp32, input `[1,3,320,320]` NCHW, output `[1,1,320,320]` sigmoid, ~4.4 MB.
- **sha256:** `698d9836dbe72f30ad947fe33ce676a88f7c5fb01d0ec6ed069f157b27b8c0ed`

Once this file is present, `BundledSegmentationEngine.isAvailable()` returns `true` and the engine
becomes a real cut-out option (see the "AI Model" picker in the Cut out tool).

## Where it comes from

The ONNX is produced from the PyTorch checkpoint by `model_conversion/convert_u2netp.py` — a
deterministic, offline conversion. The `.pth` sources are **not** bundled and are git-ignored (the
full checkpoint is 176 MB). To reproduce the `.onnx`, see `model_conversion/README.md`.

Only `u2netp` (the Apache-2.0 salient-object checkpoint) is used — **not** `u2net_portrait`
(non-commercial) or BRIA RMBG (CC BY-NC), which would be incompatible with a paid app.
