import 'dart:collection';
import 'dart:typed_data';

import 'alpha_mask.dart';

/// Options controlling how a raw engine mask is cleaned up before it becomes a
/// layer's alpha. Sensible defaults tuned for photo cut-outs.
class MaskProcessingOptions {
  const MaskProcessingOptions({
    this.threshold,
    this.keepLargestComponent = true,
    this.featherRadius = 1,
  });

  /// If set, coverage below this snaps to 0 and at/above snaps to 255 before
  /// any other step (a hard matte). Leave null to keep the engine's soft edges.
  final int? threshold;

  /// Drop everything except the largest connected foreground blob — removes the
  /// stray specks ML Kit sometimes leaves in the background.
  final bool keepLargestComponent;

  /// Box-blur radius (in pixels) applied last to soften the cut edge. 0 = off.
  final int featherRadius;
}

/// Pure, dependency-free mask post-processing. Every function returns a new
/// [AlphaMask]; inputs are never mutated.
abstract final class MaskProcessing {
  MaskProcessing._();

  /// Run the full clean-up chain described by [options]:
  /// threshold → keep-largest-component → feather.
  static AlphaMask process(AlphaMask mask, MaskProcessingOptions options) {
    var out = mask;
    if (options.threshold != null) {
      out = threshold(out, options.threshold!);
    }
    if (options.keepLargestComponent) {
      out = keepLargestComponent(out);
    }
    if (options.featherRadius > 0) {
      out = feather(out, options.featherRadius);
    }
    return out;
  }

  /// Hard matte: coverage `>= cutoff` becomes [high], below becomes [low].
  static AlphaMask threshold(
    AlphaMask mask,
    int cutoff, {
    int low = 0,
    int high = 255,
  }) {
    final out = Uint8List(mask.length);
    for (var i = 0; i < mask.length; i++) {
      out[i] = mask.alpha[i] >= cutoff ? high : low;
    }
    return mask.copyWith(alpha: out);
  }

  /// Separable box blur of radius [radius] (window `2*radius+1`), soft edges for
  /// the cut. Averages coverage over the neighbourhood, clamping at the border.
  static AlphaMask feather(AlphaMask mask, int radius) {
    if (radius <= 0) return mask;
    final w = mask.width;
    final h = mask.height;

    // Horizontal pass into a temp buffer, then vertical pass into the output.
    final tmp = Uint8List(mask.length);
    final win = 2 * radius + 1;
    for (var y = 0; y < h; y++) {
      final row = y * w;
      for (var x = 0; x < w; x++) {
        var sum = 0;
        for (var k = -radius; k <= radius; k++) {
          final xx = (x + k).clamp(0, w - 1);
          sum += mask.alpha[row + xx];
        }
        tmp[row + x] = sum ~/ win;
      }
    }

    final out = Uint8List(mask.length);
    for (var x = 0; x < w; x++) {
      for (var y = 0; y < h; y++) {
        var sum = 0;
        for (var k = -radius; k <= radius; k++) {
          final yy = (y + k).clamp(0, h - 1);
          sum += tmp[yy * w + x];
        }
        out[y * w + x] = sum ~/ win;
      }
    }
    return mask.copyWith(alpha: out);
  }

  /// Keep only the largest 4-connected component of foreground pixels
  /// (coverage `>= cutoff`); zero everything else. Original coverage values are
  /// preserved inside the kept component, so soft edges survive.
  static AlphaMask keepLargestComponent(AlphaMask mask, {int cutoff = 128}) {
    final w = mask.width;
    final h = mask.height;
    final n = mask.length;
    final labels = Int32List(n); // 0 = unlabelled/background
    var currentLabel = 0;
    var bestLabel = 0;
    var bestSize = 0;

    final queue = Queue<int>();
    for (var start = 0; start < n; start++) {
      if (mask.alpha[start] < cutoff || labels[start] != 0) continue;
      currentLabel++;
      var size = 0;
      labels[start] = currentLabel;
      queue.add(start);
      while (queue.isNotEmpty) {
        final p = queue.removeFirst();
        size++;
        final px = p % w;
        final py = p ~/ w;
        // 4-connected neighbours.
        if (px > 0) _visit(p - 1, cutoff, mask, labels, currentLabel, queue);
        if (px < w - 1) {
          _visit(p + 1, cutoff, mask, labels, currentLabel, queue);
        }
        if (py > 0) _visit(p - w, cutoff, mask, labels, currentLabel, queue);
        if (py < h - 1) {
          _visit(p + w, cutoff, mask, labels, currentLabel, queue);
        }
      }
      if (size > bestSize) {
        bestSize = size;
        bestLabel = currentLabel;
      }
    }

    // Nothing crossed the threshold → return an empty mask rather than the noise.
    if (bestLabel == 0) return AlphaMask.empty(w, h);

    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      if (labels[i] == bestLabel) out[i] = mask.alpha[i];
    }
    return mask.copyWith(alpha: out);
  }

  static void _visit(
    int p,
    int cutoff,
    AlphaMask mask,
    Int32List labels,
    int label,
    Queue<int> queue,
  ) {
    if (labels[p] != 0 || mask.alpha[p] < cutoff) return;
    labels[p] = label;
    queue.add(p);
  }

  /// `current − object`: alpha becomes `min(current, 255 − object)`, so a soft
  /// object edge subtracts softly. NEVER run [process] on the result — its
  /// keep-largest-component step would eat surviving blobs (#83).
  static AlphaMask subtract(AlphaMask current, AlphaMask object) {
    assert(
      current.width == object.width && current.height == object.height,
      'mask sizes must match',
    );
    final out = Uint8List(current.length);
    for (var i = 0; i < current.length; i++) {
      final keep = 255 - object.alpha[i];
      final a = current.alpha[i];
      out[i] = a < keep ? a : keep;
    }
    return current.copyWith(alpha: out);
  }

  /// Tier-1 tap-to-remove (#83): the 4-connected opaque component (coverage
  /// `>= cutoff`) under ([x],[y]) is subtracted from [mask] with a 1-px
  /// feathered seam. Outcomes:
  /// - `miss`   — the tap hit transparency (or out of bounds); mask untouched.
  /// - `subject`— the tapped blob is the LARGEST component: that's the
  ///   sticker's subject, refuse to nuke it; mask untouched.
  /// - `removed`— `mask` carries the result.
  static ({RemoveTapOutcome outcome, AlphaMask? mask}) removeObjectAt(
    AlphaMask mask,
    int x,
    int y, {
    int cutoff = 16,
  }) {
    final w = mask.width;
    final h = mask.height;
    if (x < 0 || y < 0 || x >= w || y >= h) {
      return (outcome: RemoveTapOutcome.miss, mask: null);
    }
    if (mask.alpha[y * w + x] < cutoff) {
      return (outcome: RemoveTapOutcome.miss, mask: null);
    }

    // Label every component, tracking sizes.
    final labels = Int32List(mask.length);
    final sizes = <int>[0]; // index = label
    var current = 0;
    final queue = Queue<int>();
    for (var start = 0; start < mask.length; start++) {
      if (mask.alpha[start] < cutoff || labels[start] != 0) continue;
      current++;
      sizes.add(0);
      labels[start] = current;
      queue.add(start);
      while (queue.isNotEmpty) {
        final p = queue.removeFirst();
        sizes[current]++;
        final px = p % w;
        final py = p ~/ w;
        if (px > 0) _visit(p - 1, cutoff, mask, labels, current, queue);
        if (px < w - 1) _visit(p + 1, cutoff, mask, labels, current, queue);
        if (py > 0) _visit(p - w, cutoff, mask, labels, current, queue);
        if (py < h - 1) _visit(p + w, cutoff, mask, labels, current, queue);
      }
    }

    final tapped = labels[y * w + x];
    final tappedSize = sizes[tapped];
    for (var l = 1; l <= current; l++) {
      if (l != tapped && sizes[l] > tappedSize) {
        // A bigger blob exists elsewhere → the tapped one is clutter: remove.
        final object = Uint8List(mask.length);
        for (var i = 0; i < mask.length; i++) {
          if (labels[i] == tapped) object[i] = 255;
        }
        final softened = feather(mask.copyWith(alpha: object), 1);
        return (
          outcome: RemoveTapOutcome.removed,
          mask: subtract(mask, softened),
        );
      }
    }
    return (outcome: RemoveTapOutcome.subject, mask: null);
  }
}

/// What a tier-1 remove-object tap did (#83).
enum RemoveTapOutcome { removed, subject, miss }
