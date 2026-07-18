"""Convert the U²-Netp PyTorch checkpoint to the ONNX the app bundles.

Reproducible, offline pipeline that turns `u2netp.pth` (this dir) into
`assets/models/u2netp.onnx` — the weights `BundledSegmentationEngine` (#28)
loads via `flutter_onnxruntime`.

    pip install torch onnx onnxruntime onnxscript
    python model_conversion/convert_u2netp.py

The legacy TorchScript exporter at opset 17 is used deliberately: it is
deterministic and produces only ops ONNX Runtime Mobile supports
(Conv/Resize/Sigmoid/…). See model_conversion/README.md for provenance & SHA.
"""

import os
import sys
import warnings

warnings.filterwarnings("ignore")

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import torch  # noqa: E402
import torch.nn as nn  # noqa: E402
from u2net_arch import U2NETP  # noqa: E402  (official Apache-2.0 architecture)

PTH = os.path.join(HERE, "u2netp.pth")
OUT = os.path.join(ROOT, "assets", "models", "u2netp.onnx")
INPUT_SIZE = 320


class _MainOutputOnly(nn.Module):
    """U²-Net returns 7 side outputs; the app only needs d0 (the fused map).

    Exporting a single [1,1,H,W] output keeps `session.outputNames.first`
    unambiguous and the graph small.
    """

    def __init__(self, net):
        super().__init__()
        self.net = net

    def forward(self, x):
        return self.net(x)[0]


def main():
    print(f"loading {PTH} ({os.path.getsize(PTH)} bytes)")
    net = U2NETP(3, 1)
    net.load_state_dict(torch.load(PTH, map_location="cpu"))
    net.eval()

    model = _MainOutputOnly(net).eval()
    dummy = torch.randn(1, 3, INPUT_SIZE, INPUT_SIZE)
    with torch.no_grad():
        torch.onnx.export(
            model,
            dummy,
            OUT,
            input_names=["input"],
            output_names=["output"],
            opset_version=17,
            do_constant_folding=True,
            dynamo=False,
        )
    print(f"exported -> {OUT} ({os.path.getsize(OUT)} bytes)")
    _verify()


def _verify():
    import hashlib

    import numpy as np
    import onnx
    import onnxruntime as ort

    model = onnx.load(OUT)
    onnx.checker.check_model(model)
    sess = ort.InferenceSession(OUT, providers=["CPUExecutionProvider"])
    i, o = sess.get_inputs()[0], sess.get_outputs()[0]
    print("input :", i.name, i.shape, i.type)
    print("output:", o.name, o.shape, o.type)
    x = np.random.rand(1, 3, INPUT_SIZE, INPUT_SIZE).astype(np.float32)
    y = sess.run(None, {i.name: x})[0]
    assert list(y.shape) == [1, 1, INPUT_SIZE, INPUT_SIZE], y.shape
    assert 0.0 <= float(y.min()) and float(y.max()) <= 1.0001, (y.min(), y.max())
    sha = hashlib.sha256(open(OUT, "rb").read()).hexdigest()
    opset = [(im.domain or "ai.onnx", im.version) for im in model.opset_import]
    print(f"opset : {opset}")
    print(f"sha256: {sha}")
    print("OK: NCHW [1,3,320,320] -> [1,1,320,320] sigmoid, ORT-Mobile ops only")


if __name__ == "__main__":
    main()
