import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'segmenter.dart';

/// [Segmenter] backed by ONNX Runtime Mobile via `flutter_onnxruntime`. Loads
/// the bundled `.onnx` from assets and runs CPU/XNNPACK inference.
///
/// Device-only: this class needs the native ORT runtime and the bundled model
/// weights, so it is exercised on a device/emulator, not in host unit tests
/// (those inject a fake [Segmenter]). See docs/M2_BUNDLED_SEGMENTATION_DECISION.md.
class OrtSegmenter implements Segmenter {
  OrtSegmenter._(this._session, this._inputName, this._outputName);

  final OrtSession _session;
  final String _inputName;
  final String _outputName;

  /// Creates a session from a bundled asset key (e.g. `assets/models/u2netp.onnx`).
  static Future<OrtSegmenter> fromAsset(String assetKey) async {
    final session = await OnnxRuntime().createSessionFromAsset(assetKey);
    return OrtSegmenter._(
      session,
      session.inputNames.first,
      // U²-Net's fused main output (d0) is the first output.
      session.outputNames.first,
    );
  }

  @override
  Future<Float32List> infer(Float32List input, List<int> shape) async {
    final inputValue = await OrtValue.fromList(input, shape);
    try {
      final outputs = await _session.run({_inputName: inputValue});
      final out = outputs[_outputName];
      if (out == null) {
        throw StateError('missing output "$_outputName"');
      }
      final flat = await out.asFlattenedList();
      await out.dispose();
      return Float32List.fromList([
        for (final v in flat) (v as num).toDouble(),
      ]);
    } finally {
      await inputValue.dispose();
    }
  }

  @override
  Future<void> dispose() => _session.close();
}
