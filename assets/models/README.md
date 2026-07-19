# Bundled segmentation models

On-device model weights. The offline background-removal **fallback** engine
(`BundledSegmentationEngine`, #28) and the tap-to-remove object engine
(`MobileSamEngine`, #84/#85) load from this directory. See
`docs/M2_BUNDLED_SEGMENTATION_DECISION.md` and
`docs/plans/image-layers-bubbles-object-removal-plan.md`.

## Shipped files

```
assets/models/u2netp.onnx              ← background removal (pubspec lists exact files)
assets/models/mobile_sam_encoder.onnx  ← object removal: image encoder, fp16
assets/models/mobile_sam_decoder.onnx  ← object removal: prompt decoder, fp32
```

## MobileSAM (tap-to-remove, #84)

- **Model:** MobileSAM — <https://github.com/ChaoningZhang/MobileSAM>,
  **Apache-2.0** (code and weights; license text ships in-app via
  `assets/licenses/Apache-2.0-models.txt`). Converted from the official
  `mobile_sam.pt` checkpoint (git-ignored, 40.7 MB) by
  `model_conversion/convert_mobile_sam.py` — see that script's docstring for
  the exact graph I/O contracts the Dart engine relies on.
- **Encoder** (`mobile_sam_encoder.onnx`): TinyViT, opset 17, **fp16 weights /
  fp32 I/O**, ~13.7 MB. Input `input_image` float32 `[H, W, 3]` RGB 0–255,
  longest side pre-resized to 1024 (normalize + pad happen in-graph). Output
  `image_embeddings` `[1, 256, 64, 64]`. Runs once per photo; the embedding is
  cached (memory + disk).
- **Decoder** (`mobile_sam_decoder.onnx`): prompt encoder + mask decoder,
  opset 17, **fp32**, ~15.7 MB (the onnxconverter-common fp16 pass mis-types
  Cast nodes in this graph — fp32 is shipped instead). Runs per tap.
- **Validation:** fp16-encoder pipeline vs full-fp32 on the synthetic fixture:
  mask IoU **1.0000** (bit-identical 70 459-px mask).
- **sha256:**
  - encoder `a506a51ecf015587c9005640a13cce8793316cc99f3bb35cacc0ebed72ba7fa6`
  - decoder `6f0494c6a23edce3a1b707b691235c012ac61b5aa8e3334263462aa5415dfe91`

## U²-Netp (background removal)

- **Model:** U²-Netp (`u2netp`) — the small salient-object net from
  <https://github.com/xuebinqin/U-2-Net>, **Apache-2.0** (code and weights;
  license text ships in-app via `assets/licenses/Apache-2.0-models.txt`).
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
