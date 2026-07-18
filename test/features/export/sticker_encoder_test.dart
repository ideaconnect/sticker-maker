import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/features/export/sticker_encoder.dart';

/// Fake encoder whose byte size scales with the square size (size² bytes), so
/// the budget search is deterministic without real rendering.
Future<Uint8List> _fake(int size) async => Uint8List(size * size);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fitToBudget', () {
    test('returns the largest size that fits the budget', () async {
      final r = await StickerEncoder.fitToBudget(
        _fake,
        maxBytes: 384 * 384, // 512² too big, 448² too big, 384² fits
        sizes: const [512, 448, 384, 256],
      );
      expect(r.size, 384);
      expect(r.bytes.length, 384 * 384);
    });

    test('returns the first size when everything fits', () async {
      final r = await StickerEncoder.fitToBudget(
        _fake,
        maxBytes: 1 << 30,
        sizes: const [512, 256],
      );
      expect(r.size, 512);
    });

    test('returns the smallest size when nothing fits', () async {
      final r = await StickerEncoder.fitToBudget(
        _fake,
        maxBytes: 1, // impossible
        sizes: const [512, 256, 128],
      );
      expect(r.size, 128);
    });
  });

  group('png', () {
    const frame = Frame(
      id: 'f',
      layers: [
        TextLayer(id: 't', name: 'W', text: 'WOOF', fontFamily: 'Rubik'),
      ],
    );

    test('encodes a real transparent PNG at the requested size', () async {
      final sticker = await StickerEncoder.png(frame, size: 128);
      expect(sticker.format, 'png');
      expect(sticker.size, 128);
      expect(sticker.byteLength, greaterThan(0));
      // PNG magic number.
      expect(sticker.bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });

    test('pngWithinBudget downscales to meet a tiny cap', () async {
      final big = await StickerEncoder.png(frame);
      final capped = await StickerEncoder.pngWithinBudget(
        frame,
        maxBytes: 1, // forces the smallest candidate
      );
      expect(capped.size, StickerEncoder.defaultSizes.last);
      expect(capped.byteLength, lessThanOrEqualTo(big.byteLength));
    });
  });

  group('gif', () {
    test('encodes an animated, multi-frame, looping GIF', () async {
      const frames = [
        Frame(
          id: 'f0',
          layers: [
            TextLayer(id: 'a', name: 'A', text: 'A', fontFamily: 'Rubik'),
          ],
        ),
        Frame(
          id: 'f1',
          layers: [
            TextLayer(id: 'b', name: 'B', text: 'B', fontFamily: 'Rubik'),
          ],
        ),
      ];
      final sticker = await StickerEncoder.gif(frames, size: 32);

      expect(sticker.format, 'gif');
      expect(String.fromCharCodes(sticker.bytes.sublist(0, 3)), 'GIF');
      final decoded = img.decodeGif(sticker.bytes);
      expect(decoded, isNotNull);
      expect(decoded!.numFrames, 2);
    });
  });
}
