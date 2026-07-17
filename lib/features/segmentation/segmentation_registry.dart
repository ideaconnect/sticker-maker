import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'segmentation_engine.dart';

/// Ordered set of [SegmentationEngine]s, highest priority first. Resolves the
/// best engine that is actually usable on this device and runs segmentation
/// through it, transparently falling through to the next engine if one that
/// claimed availability then fails.
///
/// Engines are injected, so the set is hot-swappable — production wires the
/// system engine ahead of the bundled fallback; tests pass fakes in any order.
class SegmentationRegistry {
  const SegmentationRegistry(this.engines);

  /// Priority order: e.g. `[MlKitEngine(), BundledEngine()]`.
  final List<SegmentationEngine> engines;

  /// The highest-priority engine reporting [SegmentationEngine.isAvailable],
  /// or `null` when none can run (offline install with no fallback, etc.).
  Future<SegmentationEngine?> resolve() async {
    for (final engine in engines) {
      if (await engine.isAvailable()) return engine;
    }
    return null;
  }

  /// Segment [request] using the best available engine. If that engine throws a
  /// [SegmentationException], fall through to the next available one. Returns
  /// `null` only when no engine can produce a mask.
  Future<SegmentationResult?> segment(SegmentationRequest request) async {
    for (final engine in engines) {
      if (!await engine.isAvailable()) continue;
      try {
        return await engine.segment(request);
      } on SegmentationException catch (e) {
        debugPrint('segmentation: ${engine.id} failed, falling through: $e');
        continue;
      }
    }
    return null;
  }
}

/// The app's segmentation registry. Engines are appended as they land:
/// ML Kit (#26, Android) and the bundled fallback (#28) — for now the set is
/// empty, so [SegmentationRegistry.resolve] returns null and the Cut-out UX
/// shows its "unavailable" state.
final segmentationRegistryProvider = Provider<SegmentationRegistry>(
  (ref) => const SegmentationRegistry([]),
);
