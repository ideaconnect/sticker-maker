import 'package:flutter/foundation.dart';

import 'alpha_mask.dart';

/// A request to segment the foreground subject out of one image.
///
/// The image is passed by [imagePath] (a file on disk) so engines can pick the
/// most efficient path — ML Kit reads an `InputImage.fromFilePath`, the bundled
/// model decodes and resizes itself — without the caller forcing a decode.
@immutable
class SegmentationRequest {
  const SegmentationRequest({required this.imagePath, this.width, this.height});

  /// Absolute path to the source image.
  final String imagePath;

  /// Source dimensions, if already known (a hint; engines may ignore).
  final int? width;
  final int? height;
}

/// The result of a successful segmentation: an [AlphaMask] plus which engine
/// produced it (for diagnostics, telemetry-free logging and UX copy).
@immutable
class SegmentationResult {
  const SegmentationResult({required this.mask, required this.engineId});

  final AlphaMask mask;
  final String engineId;
}

/// Thrown when an engine that reported itself available still fails to segment
/// (model download interrupted, decode error, unsupported image, …). The
/// registry catches this to fall through to the next engine.
class SegmentationException implements Exception {
  const SegmentationException(this.message, {this.engineId});

  final String message;
  final String? engineId;

  @override
  String toString() => 'SegmentationException(${engineId ?? '?'}: $message)';
}

/// Produces an 8-bit alpha mask of the foreground subject of an image, entirely
/// on-device. Implementations are hot-swappable behind this interface:
///
///  * `MlKitSegmentationEngine` — Google ML Kit Subject Segmentation (Android).
///  * `VisionSegmentationEngine` — Apple Vision foreground mask (iOS 17+).
///  * `BundledSegmentationEngine` — a bundled Apache-2.0 model (ISNet / U²-Net),
///    the universal fallback for devices without the system engine.
///
/// The [SegmentationRegistry] picks the highest-priority [isAvailable] engine.
abstract interface class SegmentationEngine {
  /// Stable identifier, e.g. `mlkit`, `vision`, `bundled`. Persisted with
  /// results; keep it constant across releases.
  String get id;

  /// Short human-readable name for diagnostics / debug UI.
  String get label;

  /// Whether this engine can run *right now* on this device: the platform
  /// supports it, any required model is present (or downloadable), etc.
  /// Must not throw — return `false` on any uncertainty.
  Future<bool> isAvailable();

  /// Segment the subject in [request]. Throws [SegmentationException] on
  /// failure so the registry can fall through to the next engine.
  Future<SegmentationResult> segment(SegmentationRequest request);
}
