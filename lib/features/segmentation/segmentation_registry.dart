import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'engines/bundled/bundled_segmentation_engine.dart';
import 'engines/mlkit_segmentation_engine.dart';
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
  ///
  /// [preferredId] (the user's chosen engine) is tried first when available;
  /// the rest keep their configured priority as fallbacks.
  Future<SegmentationEngine?> resolve({String? preferredId}) async {
    for (final engine in _prioritized(preferredId)) {
      if (await engine.isAvailable()) return engine;
    }
    return null;
  }

  /// Segment [request] using the best available engine. If that engine throws a
  /// [SegmentationException], fall through to the next available one. Returns
  /// `null` only when no engine can produce a mask.
  ///
  /// When [preferredId] is set, the engine with that id runs first (if
  /// available); a failure or unavailability still falls through to the others,
  /// so the user's choice is a preference, never a dead end.
  Future<SegmentationResult?> segment(
    SegmentationRequest request, {
    String? preferredId,
  }) async {
    for (final engine in _prioritized(preferredId)) {
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

  /// [engines] with the one matching [preferredId] (if any) moved to the front;
  /// the remaining engines keep their configured order as fallbacks.
  List<SegmentationEngine> _prioritized(String? preferredId) {
    if (preferredId == null) return engines;
    final preferred = [
      for (final e in engines)
        if (e.id == preferredId) e,
    ];
    if (preferred.isEmpty) return engines;
    return [
      ...preferred,
      for (final e in engines)
        if (e.id != preferredId) e,
    ];
  }
}

/// The app's segmentation registry, highest-priority engine first:
///
///  1. The platform's system engine — ML Kit on Android (#26); Apple Vision on
///     iOS arrives in #58.
///  2. The bundled Apache-2.0 fallback model (#28) — appended once it lands, so
///     devices without Play services still cut out.
///
/// Until the fallback exists, a non-Android device (or an Android device with
/// no Play services) resolves to no engine and the Cut-out UX shows its
/// "unavailable" state.
final segmentationRegistryProvider = Provider<SegmentationRegistry>((ref) {
  return SegmentationRegistry([
    if (defaultTargetPlatform == TargetPlatform.android)
      MlKitSegmentationEngine(),
    // Bundled U²-Netp fallback (#28). isAvailable() is false until the `.onnx`
    // weights ship in assets/models/, so this stays inert until then.
    BundledSegmentationEngine(),
  ]);
});
