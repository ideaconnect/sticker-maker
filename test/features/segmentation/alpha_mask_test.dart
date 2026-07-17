import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/features/segmentation/alpha_mask.dart';

void main() {
  group('AlphaMask', () {
    test('filled / empty factories', () {
      final full = AlphaMask.filled(3, 2, 255);
      expect(full.width, 3);
      expect(full.height, 2);
      expect(full.length, 6);
      expect(full.alpha.every((v) => v == 255), isTrue);

      final empty = AlphaMask.empty(3, 2);
      expect(empty.alpha.every((v) => v == 0), isTrue);
    });

    test('filled clamps the value to 0…255', () {
      expect(AlphaMask.filled(1, 1, 999).alpha.first, 255);
      expect(AlphaMask.filled(1, 1, -5).alpha.first, 0);
    });

    test('at() indexes row-major', () {
      final mask = AlphaMask(
        width: 2,
        height: 2,
        alpha: Uint8List.fromList([10, 20, 30, 40]),
      );
      expect(mask.at(0, 0), 10);
      expect(mask.at(1, 0), 20);
      expect(mask.at(0, 1), 30);
      expect(mask.at(1, 1), 40);
    });

    test('coverage() counts pixels at/above the cutoff', () {
      final mask = AlphaMask(
        width: 2,
        height: 2,
        alpha: Uint8List.fromList([0, 127, 128, 255]),
      );
      expect(mask.coverage(), 0.5); // 128 and 255 qualify
      expect(mask.coverage(1), 0.75); // 127, 128, 255 qualify
      expect(mask.coverage(256), 0.0);
    });

    test('value equality compares dimensions and bytes', () {
      final a = AlphaMask(
        width: 2,
        height: 1,
        alpha: Uint8List.fromList([1, 2]),
      );
      final b = AlphaMask(
        width: 2,
        height: 1,
        alpha: Uint8List.fromList([1, 2]),
      );
      final c = AlphaMask(
        width: 2,
        height: 1,
        alpha: Uint8List.fromList([1, 3]),
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('rejects an alpha length that does not match the dimensions', () {
      expect(
        () => AlphaMask(
          width: 2,
          height: 2,
          alpha: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
