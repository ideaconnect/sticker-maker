import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// One named tensor feed for an [OrtGraph] run.
typedef GraphFeed = ({Float32List data, List<int> shape});

/// A named-input / named-output ONNX graph — the injectable native seam for
/// the MobileSAM engine (#85), mirroring the single-input `Segmenter` seam of
/// the bundled engine. Injecting a fake keeps the whole pre/post pipeline
/// host-unit-testable.
abstract interface class OrtGraph {
  /// Runs the graph and returns ONLY the outputs named in [outputs], each as
  /// a flattened float list. Every other output is disposed unread — crossing
  /// the platform channel with megapixel float lists is the expensive part,
  /// so callers ask for the small tensors (e.g. SAM's 256² `low_res_masks`,
  /// never its full-size `masks`).
  Future<Map<String, Float32List>> run(
    Map<String, GraphFeed> feeds,
    List<String> outputs,
  );

  Future<void> dispose();
}

/// [OrtGraph] backed by ONNX Runtime Mobile via `flutter_onnxruntime`.
/// Device-only; host tests inject a fake.
class OrtGraphSession implements OrtGraph {
  OrtGraphSession._(this._session);

  final OrtSession _session;

  /// Creates a session from a bundled asset key
  /// (e.g. `assets/models/mobile_sam_decoder.onnx`).
  static Future<OrtGraphSession> fromAsset(String assetKey) async =>
      OrtGraphSession._(await OnnxRuntime().createSessionFromAsset(assetKey));

  @override
  Future<Map<String, Float32List>> run(
    Map<String, GraphFeed> feeds,
    List<String> outputs,
  ) async {
    final values = <String, OrtValue>{};
    try {
      for (final entry in feeds.entries) {
        values[entry.key] = await OrtValue.fromList(
          entry.value.data,
          entry.value.shape,
        );
      }
      final results = await _session.run(values);
      final picked = <String, Float32List>{};
      for (final entry in results.entries) {
        if (outputs.contains(entry.key)) {
          final flat = await entry.value.asFlattenedList();
          picked[entry.key] = Float32List.fromList([
            for (final v in flat) (v as num).toDouble(),
          ]);
        }
        await entry.value.dispose();
      }
      for (final name in outputs) {
        if (!picked.containsKey(name)) {
          throw StateError('missing output "$name"');
        }
      }
      return picked;
    } finally {
      for (final value in values.values) {
        await value.dispose();
      }
    }
  }

  @override
  Future<void> dispose() => _session.close();
}
