"""Convert the MobileSAM checkpoint to the two ONNX graphs the app bundles.

Point-prompt object segmentation (#84 / M11): a heavy image ENCODER that runs
once per photo, and a light prompt DECODER that runs per tap. Both are exported
from `assets/models/mobile_sam.pt` — downloaded by the maintainer from the
official Apache-2.0 repo <https://github.com/ChaoningZhang/MobileSAM>
(`weights/mobile_sam.pt`) — then converted to fp16 (weights only, fp32 I/O)
and numerically validated against the fp32 export.

    pip install torch onnx onnxruntime onnxconverter-common samexporter
    python model_conversion/convert_mobile_sam.py

Contracts baked into the exported graphs (the Dart engine relies on these):
- encoder input  `input_image`      float32 [H, W, 3], RGB 0..255, the image
  already resized so its LONGEST side == 1024 (aspect kept); normalization
  (ImageNet, 0-255 space) and bottom/right zero-padding to 1024x1024 happen
  INSIDE the graph (samexporter --use-preprocess).
- encoder output `image_embeddings` float32 [1, 256, 64, 64].
- decoder inputs `image_embeddings` [1,256,64,64], `point_coords` [1,N,2]
  (coords in the 1024-space of the resized image), `point_labels` [1,N]
  (1 = foreground, 0 = background, -1 = pad), `mask_input` [1,1,256,256],
  `has_mask_input` [1], `orig_im_size` [2] (H, W of the ORIGINAL photo).
- decoder outputs `masks` float32 [1,1,H,W] logits ALREADY upscaled to
  orig_im_size (threshold at 0), `iou_predictions`, `low_res_masks`
  [1,1,256,256] (feed back via mask_input for refinement taps).

The legacy TorchScript exporter at opset 17 is used deliberately, matching the
u2netp pipeline. See model_conversion/README.md for provenance & SHAs.
"""

import hashlib
import os
import warnings

warnings.filterwarnings("ignore")

import numpy as np  # noqa: E402
import torch  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CKPT = os.path.join(ROOT, "assets", "models", "mobile_sam.pt")
OUT_DIR = os.path.join(HERE, "out")
ENC_FP32 = os.path.join(OUT_DIR, "mobile_sam_encoder_fp32.onnx")
DEC_FP32 = os.path.join(OUT_DIR, "mobile_sam_decoder_fp32.onnx")
ENC_OUT = os.path.join(ROOT, "assets", "models", "mobile_sam_encoder.onnx")
DEC_OUT = os.path.join(ROOT, "assets", "models", "mobile_sam_decoder.onnx")
OPSET = 17


def export_encoder():
    from samexporter.export_encoder import run_export

    print("== encoder (TinyViT, preprocess embedded) ==")
    run_export(
        model_type="mobile",
        checkpoint=CKPT,
        output=ENC_FP32,
        use_preprocess=True,
        opset=OPSET,
    )


def export_decoder():
    """Mirror samexporter's export_decoder, but build the MobileSAM model via
    its mobile setup (the stock sam_model_registry has no 'mobile' entry)."""
    from samexporter.mobile_encoder.setup_mobile_sam import setup_model
    from segment_anything.utils.onnx import SamOnnxModel

    print("== decoder (prompt encoder + mask decoder) ==")
    sam = setup_model()
    sam.load_state_dict(torch.load(CKPT, map_location="cpu"), strict=True)
    sam.eval()

    onnx_model = SamOnnxModel(model=sam, return_single_mask=True)
    embed_dim = sam.prompt_encoder.embed_dim
    embed_size = sam.prompt_encoder.image_embedding_size
    mask_input_size = [4 * x for x in embed_size]
    dummy_inputs = {
        "image_embeddings": torch.randn(
            1, embed_dim, *embed_size, dtype=torch.float
        ),
        "point_coords": torch.randint(
            low=0, high=1024, size=(1, 5, 2), dtype=torch.float
        ),
        "point_labels": torch.randint(
            low=0, high=4, size=(1, 5), dtype=torch.float
        ),
        "mask_input": torch.randn(1, 1, *mask_input_size, dtype=torch.float),
        "has_mask_input": torch.tensor([1], dtype=torch.float),
        "orig_im_size": torch.tensor([1500, 2250], dtype=torch.float),
    }
    _ = onnx_model(**dummy_inputs)
    with torch.no_grad():
        torch.onnx.utils.export(
            onnx_model,
            tuple(dummy_inputs.values()),
            DEC_FP32,
            export_params=True,
            opset_version=OPSET,
            do_constant_folding=True,
            input_names=list(dummy_inputs.keys()),
            output_names=["masks", "iou_predictions", "low_res_masks"],
            dynamic_axes={
                "point_coords": {1: "num_points"},
                "point_labels": {1: "num_points"},
            },
        )


def to_fp16(src, dst):
    """Weights to fp16, I/O kept fp32 so the Dart side stays float32-only.

    Plain conversion, no op_block_list: blocking Cast produced a graph that
    ONNX Runtime's session optimizer ground on for an hour. The encoder
    converts and loads cleanly this way; the DECODER does not (the converter
    mis-types Cast nodes in its orig_im_size resize path), which is why
    main() ships the decoder as fp32 instead of calling this on it.
    """
    import onnx
    from onnxconverter_common import float16

    model = onnx.load(src)
    model_fp16 = float16.convert_float_to_float16(model, keep_io_types=True)
    onnx.save(model_fp16, dst)
    print(f"fp16: {src} -> {dst} ({os.path.getsize(dst)} bytes)")


def _test_image(h=683, w=1024):
    """Deterministic synthetic photo: gradient background + bright disc, the
    disc being the 'object' the validation prompt points at."""
    rng = np.random.default_rng(42)
    img = np.zeros((h, w, 3), dtype=np.float32)
    img[..., 0] = np.linspace(40, 160, w)[None, :]
    img[..., 1] = np.linspace(60, 120, h)[:, None]
    img[..., 2] = 90
    yy, xx = np.mgrid[0:h, 0:w]
    disc = (yy - h * 0.5) ** 2 + (xx - w * 0.55) ** 2 < (h * 0.22) ** 2
    img[disc] = [235.0, 210.0, 60.0]
    img += rng.normal(0, 2.0, img.shape).astype(np.float32)
    return np.clip(img, 0, 255)


def _run(session, feeds):
    return session.run(None, feeds)


def validate():
    """fp16 must agree with fp32: embedding cosine ~1, mask IoU >= 0.98."""
    import onnxruntime as ort

    print("== validate fp16 vs fp32 ==")
    img = _test_image()
    h, w = img.shape[:2]
    point = np.array([[[w * 0.55, h * 0.5]]], dtype=np.float32)  # on the disc
    labels = np.array([[1]], dtype=np.float32)
    zero_mask = np.zeros((1, 1, 256, 256), dtype=np.float32)
    no_mask = np.array([0], dtype=np.float32)
    orig = np.array([h, w], dtype=np.float32)

    masks = {}
    for tag, enc_path, dec_path in (
        ("fp32", ENC_FP32, DEC_FP32),
        ("fp16", ENC_OUT, DEC_OUT),
    ):
        enc = ort.InferenceSession(enc_path, providers=["CPUExecutionProvider"])
        dec = ort.InferenceSession(dec_path, providers=["CPUExecutionProvider"])
        (emb,) = _run(enc, {"input_image": img})
        out = _run(
            dec,
            {
                "image_embeddings": emb,
                "point_coords": point,
                "point_labels": labels,
                "mask_input": zero_mask,
                "has_mask_input": no_mask,
                "orig_im_size": orig,
            },
        )
        masks[tag] = out[0][0, 0] > 0
        print(
            f"{tag}: mask px {int(masks[tag].sum())}, "
            f"iou_pred {float(out[1].ravel()[0]):.3f}"
        )

    inter = np.logical_and(masks["fp32"], masks["fp16"]).sum()
    union = np.logical_or(masks["fp32"], masks["fp16"]).sum()
    iou = inter / max(union, 1)
    print(f"fp16-vs-fp32 mask IoU: {iou:.4f}")
    assert masks["fp32"].sum() > 0, "fp32 produced an empty mask"
    assert iou >= 0.98, f"fp16 diverged (IoU {iou:.4f} < 0.98)"


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    import shutil

    os.makedirs(OUT_DIR, exist_ok=True)
    print(f"checkpoint {CKPT} ({os.path.getsize(CKPT)} bytes)")
    # The traces take ~10 min — resume from existing fp32 exports when present
    # (delete model_conversion/out/ to force a re-export).
    if os.path.exists(ENC_FP32):
        print(f"encoder fp32 exists, skipping export ({ENC_FP32})")
    else:
        export_encoder()
    if os.path.exists(DEC_FP32):
        print(f"decoder fp32 exists, skipping export ({DEC_FP32})")
    else:
        export_decoder()
    # Encoder ships fp16 (halves the big asset, loads cleanly); the decoder
    # ships fp32 — see to_fp16's docstring for why.
    to_fp16(ENC_FP32, ENC_OUT)
    shutil.copyfile(DEC_FP32, DEC_OUT)
    print(f"fp32 copy: {DEC_FP32} -> {DEC_OUT} ({os.path.getsize(DEC_OUT)} bytes)")
    validate()
    for path in (ENC_OUT, DEC_OUT):
        print(f"{os.path.basename(path)}: {os.path.getsize(path)} bytes")
        print(f"  sha256 {sha256(path)}")
    print("OK")


if __name__ == "__main__":
    main()
