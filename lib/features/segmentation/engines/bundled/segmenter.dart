import 'dart:typed_data';

/// The single native inference seam behind the bundled engine: takes a packed
/// NCHW float tensor, returns the model's flat float output. Injecting a fake
/// keeps ~90% of the engine (pre/post-processing) host-unit-testable.
abstract interface class Segmenter {
  /// Runs one forward pass. [input] is the flattened tensor for [shape]
  /// (e.g. `[1,3,320,320]`); returns the flattened output map.
  Future<Float32List> infer(Float32List input, List<int> shape);

  Future<void> dispose();
}
