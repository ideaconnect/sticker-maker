import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sticker_maker/features/segmentation/engines/object/mobile_sam_engine.dart';
import 'package:sticker_maker/features/segmentation/engines/object/ort_graph.dart';

/// Records feeds and returns canned outputs — the host-testable stand-in for
/// the two ONNX sessions.
class _FakeGraph implements OrtGraph {
  _FakeGraph(this.outputsFor);

  final Map<String, Float32List> Function(Map<String, GraphFeed> feeds)
  outputsFor;
  final List<Map<String, GraphFeed>> calls = [];
  bool disposed = false;

  @override
  Future<Map<String, Float32List>> run(
    Map<String, GraphFeed> feeds,
    List<String> outputs,
  ) async {
    calls.add(feeds);
    return outputsFor(feeds);
  }

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  late Directory tmp;
  late File photo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sam_engine_');
    // 200×100 source → resize scale 5.12 → 1024×512 resized frame.
    photo = File('${tmp.path}/photo.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 200, height: 100)));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  _FakeGraph encoder() =>
      _FakeGraph((_) => {'image_embeddings': Float32List(256 * 64 * 64)});

  /// Decoder whose logits are positive in the top half of the VALID grid
  /// region (valid = resized/4 = 256×128 for the 200×100 photo; top half =
  /// v < 64), i.e. the top half of the source photo.
  _FakeGraph decoder() => _FakeGraph((_) {
    final logits = Float32List(256 * 256)..fillRange(0, 256 * 256, -10);
    for (var v = 0; v < 64; v++) {
      for (var u = 0; u < 256; u++) {
        logits[v * 256 + u] = 10;
      }
    }
    return {'low_res_masks': logits};
  });

  MobileSamEngine engine(
    _FakeGraph enc,
    _FakeGraph dec,
    List<String> created,
  ) => MobileSamEngine(
    cacheDir: tmp,
    graphFactory: (asset) async {
      created.add(asset);
      return asset.contains('encoder') ? enc : dec;
    },
  );

  test('segmentAt maps low-res logits back to source resolution', () async {
    final created = <String>[];
    final sam = engine(encoder(), decoder(), created);

    final mask = await sam.segmentAt(photo.path, [
      const PromptPoint(Offset(100, 50)),
    ]);

    expect(mask, isNotNull);
    expect(mask!.width, 200);
    expect(mask.height, 100);
    expect(mask.at(100, 20), 255, reason: 'top half is the object');
    expect(mask.at(100, 80), 0, reason: 'bottom half is not');
  });

  test('prompt coords scale into the 1024 frame with a pad point', () async {
    final created = <String>[];
    final dec = decoder();
    final sam = engine(encoder(), dec, created);

    await sam.segmentAt(photo.path, [const PromptPoint(Offset(100, 50))]);

    final feeds = dec.calls.single;
    expect(feeds['point_coords']!.shape, [1, 2, 2]); // tap + pad point
    final coords = feeds['point_coords']!.data;
    expect(coords[0], closeTo(512, 1)); // 100 × (1024/200)
    expect(coords[1], closeTo(256, 1)); // 50 × (512/100)
    final labels = feeds['point_labels']!.data;
    expect(labels[0], 1); // foreground tap
    expect(labels[1], -1); // pad
    expect(feeds['has_mask_input']!.data.single, 0);
  });

  test('the encoder runs once per photo: memory + disk caches (#85)', () async {
    final created = <String>[];
    final enc = encoder();
    final sam = engine(enc, decoder(), created);

    await sam.segmentAt(photo.path, [const PromptPoint(Offset(10, 10))]);
    await sam.segmentAt(photo.path, [const PromptPoint(Offset(90, 40))]);

    expect(
      created.where((a) => a.contains('encoder')),
      hasLength(1),
      reason: 'second tap reuses the in-memory embedding',
    );
    expect(enc.disposed, isTrue, reason: 'encoder session freed after use');

    // A brand-new engine instance (same cache dir) hits the DISK cache.
    final created2 = <String>[];
    final sam2 = engine(encoder(), decoder(), created2);
    final mask = await sam2.segmentAt(photo.path, [
      const PromptPoint(Offset(10, 10)),
    ]);
    expect(mask, isNotNull);
    expect(created2.where((a) => a.contains('encoder')), isEmpty);
  });

  test('empty prompts return null without touching the graphs', () async {
    final created = <String>[];
    final sam = engine(encoder(), decoder(), created);
    expect(await sam.segmentAt(photo.path, const []), isNull);
    expect(created, isEmpty);
  });

  test('concurrent precompute + segmentAt share ONE encoder pass', () async {
    final created = <String>[];
    final enc = encoder();
    final sam = engine(enc, decoder(), created);

    // Arm-the-mode warm-up and a fast first tap, in flight together — the
    // race that used to run two TinyViT sessions (and two full-res decodes)
    // concurrently, doubling the peak-RAM spike.
    final warmUp = sam.precompute(photo.path);
    final mask = await sam.segmentAt(photo.path, [
      const PromptPoint(Offset(100, 50)),
    ]);
    await warmUp;

    expect(mask, isNotNull);
    expect(
      created.where((a) => a.contains('encoder')),
      hasLength(1),
      reason: 'in-flight dedup: one encoder session shared by both callers',
    );
    expect(enc.calls, hasLength(1), reason: 'and it ran exactly once');
  });

  test('a truncated disk-cache entry is rejected, deleted, and the embedding '
      'recomputed', () async {
    final sam = engine(encoder(), decoder(), <String>[]);
    await sam.precompute(photo.path);

    final bin = Directory(
      '${tmp.path}/sam_embeddings',
    ).listSync().whereType<File>().singleWhere((f) => f.path.endsWith('.bin'));
    final valid = bin.readAsBytesSync();
    // Chop the file mid-embedding — the shape a mid-write process kill left
    // behind. (Length stays 4-byte aligned so the old header/view parse
    // would have "succeeded" and served garbage forever.)
    bin.writeAsBytesSync(valid.sublist(0, 1016));

    final created2 = <String>[];
    final sam2 = engine(encoder(), decoder(), created2);
    final mask = await sam2.segmentAt(photo.path, [
      const PromptPoint(Offset(100, 50)),
    ]);

    expect(mask, isNotNull);
    expect(
      created2.where((a) => a.contains('encoder')),
      hasLength(1),
      reason: 'the corrupt entry must not shadow recomputation',
    );
    expect(
      bin.lengthSync(),
      valid.length,
      reason: 'the truncated file was deleted and replaced by a valid one',
    );
  });

  test('the disk cache is pruned to the newest 8 entries', () async {
    final sam = engine(encoder(), decoder(), <String>[]);
    final photos = <File>[];
    for (var i = 0; i < 10; i++) {
      final p = File('${tmp.path}/photo_$i.png')
        ..writeAsBytesSync(img.encodePng(img.Image(width: 40, height: 20)));
      photos.add(p);
      await sam.precompute(p.path);
    }

    final bins = Directory('${tmp.path}/sam_embeddings')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.bin'))
        .toList();
    expect(bins, hasLength(MobileSamEngine.maxDiskCacheEntries));

    // The most recently saved photo's entry must be among the survivors.
    final stat = photos.last.statSync();
    final key =
        '${stat.size}_${stat.modified.millisecondsSinceEpoch}_'
        '${photos.last.path.hashCode.toRadixString(16)}';
    expect(bins.map((f) => f.uri.pathSegments.last), contains('$key.bin'));
  });

  test('no .tmp file remains after a successful save', () async {
    final sam = engine(encoder(), decoder(), <String>[]);
    await sam.precompute(photo.path);

    final entries = Directory('${tmp.path}/sam_embeddings').listSync();
    expect(
      entries.whereType<File>().where((f) => f.path.endsWith('.bin')),
      hasLength(1),
    );
    expect(entries.where((f) => f.path.endsWith('.tmp')), isEmpty);
  });
}
