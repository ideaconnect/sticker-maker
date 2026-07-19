import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// One named tensor feed for an [OrtGraph] run.
typedef GraphFeed = ({Float32List data, List<int> shape});

/// Coerces a flattened ORT output to [Float32List]. Fast path: on Android,
/// `flutter_onnxruntime` already hands back a real [Float32List] — return it
/// as-is instead of copying every element through boxed `num`s (a megapixel
/// mask output is hundreds of thousands of boxed doubles on the UI isolate,
/// see docs/reviews/2026-07-19-review.md). The boxed copy remains as the
/// fallback for backends that return plain `List<dynamic>`.
@visibleForTesting
Float32List coerceFloat32(List<dynamic> flat) {
  if (flat is Float32List) return flat;
  return Float32List.fromList([for (final v in flat) (v as num).toDouble()]);
}

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
          picked[entry.key] = coerceFloat32(
            await entry.value.asFlattenedList(),
          );
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
