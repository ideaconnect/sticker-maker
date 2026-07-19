import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/features/segmentation/engines/object/ort_graph.dart';

void main() {
  group('coerceFloat32', () {
    test('returns the SAME Float32List instance on the fast path', () {
      // Android's flutter_onnxruntime already returns Float32List — the fast
      // path must reuse it, not copy hundreds of thousands of boxed doubles.
      final flat = Float32List.fromList([1.5, -2.0, 3.25]);
      expect(identical(coerceFloat32(flat), flat), isTrue);
    });

    test('falls back to a boxed copy for plain dynamic lists', () {
      final out = coerceFloat32(<dynamic>[1, 2.5, -3]);
      expect(out, isA<Float32List>());
      expect(out, orderedEquals(<double>[1.0, 2.5, -3.0]));
    });
  });
}
