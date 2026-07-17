import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'alpha_mask.dart';

/// A single brush stroke over an [AlphaMask], in **mask pixel** coordinates.
/// [erase] pushes coverage toward 0 (reveals background / cuts away); otherwise
/// it pushes toward 255 (restores the photo). [soft] feathers the edge; a hard
/// brush sets pixels to the target outright.
class BrushStroke {
  const BrushStroke({
    required this.points,
    required this.radius,
    required this.erase,
    this.soft = true,
  });

  final List<Offset> points;
  final double radius;
  final bool erase;
  final bool soft;
}

/// Pure, dependency-free mask painting — the model half of the Erase/Restore
/// tool. Stamps overlapping dabs along the stroke path so drags leave a
/// continuous mark, independent of how fast the finger moved.
abstract final class MaskBrush {
  MaskBrush._();

  static AlphaMask paint(AlphaMask mask, BrushStroke stroke) {
    if (stroke.points.isEmpty || stroke.radius <= 0) return mask;

    final w = mask.width;
    final h = mask.height;
    final alpha = Uint8List.fromList(mask.alpha);
    final target = stroke.erase ? 0 : 255;
    final r = stroke.radius;
    final r2 = r * r;

    for (final p in _densify(stroke.points, math.max(0.5, r / 2))) {
      final minX = math.max(0, (p.dx - r).floor());
      final maxX = math.min(w - 1, (p.dx + r).ceil());
      final minY = math.max(0, (p.dy - r).floor());
      final maxY = math.min(h - 1, (p.dy + r).ceil());
      for (var y = minY; y <= maxY; y++) {
        final row = y * w;
        for (var x = minX; x <= maxX; x++) {
          final dx = x - p.dx;
          final dy = y - p.dy;
          final d2 = dx * dx + dy * dy;
          if (d2 > r2) continue;
          final i = row + x;
          if (!stroke.soft) {
            alpha[i] = target;
            continue;
          }
          // Smooth falloff: full strength at the centre, zero at the edge.
          final t = _smoothstep(1 - math.sqrt(d2) / r);
          final next = alpha[i] + (target - alpha[i]) * t;
          final rounded = next.round();
          // Move monotonically toward the target so overlapping dabs in one
          // stroke don't fight each other.
          alpha[i] = stroke.erase
              ? math.min(alpha[i], rounded)
              : math.max(alpha[i], rounded);
        }
      }
    }
    return AlphaMask(width: w, height: h, alpha: alpha);
  }

  /// Inserts intermediate points so consecutive dabs overlap by ~[step] px.
  static List<Offset> _densify(List<Offset> points, double step) {
    if (points.length == 1) return points;
    final out = <Offset>[];
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final dist = (b - a).distance;
      final n = math.max(1, (dist / step).ceil());
      for (var k = 0; k < n; k++) {
        out.add(Offset.lerp(a, b, k / n)!);
      }
    }
    out.add(points.last);
    return out;
  }

  static double _smoothstep(double x) {
    final t = x.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }
}
