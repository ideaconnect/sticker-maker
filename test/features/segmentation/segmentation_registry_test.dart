import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/features/segmentation/alpha_mask.dart';
import 'package:sticker_maker/features/segmentation/segmentation_engine.dart';
import 'package:sticker_maker/features/segmentation/segmentation_registry.dart';

/// A configurable stand-in engine for exercising the registry's discovery and
/// fall-through logic without any platform dependencies.
class FakeEngine implements SegmentationEngine {
  FakeEngine(this.id, {this.available = true, this.throwsOnSegment = false});

  @override
  final String id;
  final bool available;
  final bool throwsOnSegment;

  int segmentCalls = 0;

  @override
  String get label => 'Fake($id)';

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<SegmentationResult> segment(SegmentationRequest request) async {
    segmentCalls++;
    if (throwsOnSegment) {
      throw SegmentationException('boom', engineId: id);
    }
    return SegmentationResult(mask: AlphaMask.filled(2, 2, 255), engineId: id);
  }
}

const _request = SegmentationRequest(imagePath: '/tmp/x.png');

void main() {
  group('SegmentationRegistry.resolve', () {
    test('returns the highest-priority available engine', () async {
      final registry = SegmentationRegistry([
        FakeEngine('a', available: false),
        FakeEngine('b'),
        FakeEngine('c'),
      ]);
      final engine = await registry.resolve();
      expect(engine?.id, 'b');
    });

    test('returns null when nothing is available', () async {
      final registry = SegmentationRegistry([
        FakeEngine('a', available: false),
        FakeEngine('b', available: false),
      ]);
      expect(await registry.resolve(), isNull);
    });

    test('priority order is honoured (hot-swappable)', () async {
      final a = FakeEngine('a');
      final b = FakeEngine('b');
      expect((await SegmentationRegistry([a, b]).resolve())?.id, 'a');
      expect((await SegmentationRegistry([b, a]).resolve())?.id, 'b');
    });
  });

  group('SegmentationRegistry.segment', () {
    test('uses the first available engine', () async {
      final registry = SegmentationRegistry([
        FakeEngine('a', available: false),
        FakeEngine('b'),
      ]);
      final result = await registry.segment(_request);
      expect(result?.engineId, 'b');
    });

    test('falls through to the next engine when one throws', () async {
      final flaky = FakeEngine('flaky', throwsOnSegment: true);
      final backup = FakeEngine('backup');
      final registry = SegmentationRegistry([flaky, backup]);

      final result = await registry.segment(_request);

      expect(flaky.segmentCalls, 1, reason: 'the flaky engine was tried');
      expect(backup.segmentCalls, 1, reason: 'then the backup ran');
      expect(result?.engineId, 'backup');
    });

    test('returns null when every engine is unavailable', () async {
      final registry = SegmentationRegistry([
        FakeEngine('a', available: false),
      ]);
      expect(await registry.segment(_request), isNull);
    });

    test('returns null when the only available engine fails', () async {
      final registry = SegmentationRegistry([
        FakeEngine('only', throwsOnSegment: true),
      ]);
      expect(await registry.segment(_request), isNull);
    });
  });
}
