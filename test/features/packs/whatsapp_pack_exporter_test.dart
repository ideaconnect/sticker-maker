import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/features/export/animated_export_service.dart';
import 'package:sticker_maker/features/export/animation_encoder.dart';
import 'package:sticker_maker/features/export/static_webp_encoder.dart';
import 'package:sticker_maker/features/packs/sticker_pack.dart';
import 'package:sticker_maker/features/packs/whatsapp_pack_exporter.dart';

import '../export/webp_fixtures.dart';

StickerProject _proj(String id) => StickerProject(
  id: id,
  name: id,
  frames: [
    Frame(
      id: '${id}_f',
      layers: [
        TextLayer(id: '${id}_t', name: 'W', text: 'W', fontFamily: 'Rubik'),
      ],
    ),
  ],
);

StickerProject _animProj(String id) => StickerProject(
  id: id,
  name: id,
  frames: [
    for (var i = 0; i < 2; i++)
      Frame(
        id: '${id}_f$i',
        layers: [
          TextLayer(
            id: '${id}_t$i',
            name: 'W',
            text: 'W$i',
            fontFamily: 'Rubik',
          ),
        ],
      ),
  ],
);

/// A pure animated-export service: fake encoders + a fake rasterizer, so the
/// FFmpeg plugin and dart:ui are never touched on the host.
AnimatedExportService _fakeAnimatedService() => AnimatedExportService(
  webmEncoder: FakeAnimationEncoder(id: 'webm', format: 'webm'),
  webpEncoder: FakeAnimationEncoder(id: 'webp'),
  rasterizer: (frame, durationMs) async => RgbaFrame(
    bytes: Uint8List(16),
    width: 2,
    height: 2,
    durationMs: durationMs,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sm_wa_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('exports a WhatsApp-ready pack directory', () async {
    const pack = StickerPack(
      id: 'pack1',
      name: 'Doggos',
      stickers: [
        PackSticker(id: 's0', projectId: 'p0', emojis: ['🐶']),
        PackSticker(id: 's1', projectId: 'p1', emojis: ['🐱', '😹']),
        PackSticker(id: 's2', projectId: 'p2', emojis: ['🎉']),
      ],
    );
    final projects = {'p0': _proj('p0'), 'p1': _proj('p1'), 'p2': _proj('p2')};

    final export = await WhatsAppPackExporter(
      baseDir: tmp,
    ).export(pack, projects);

    // Directory + manifest + tray all present.
    expect(export.directory.existsSync(), isTrue);
    expect(export.contentsFile.existsSync(), isTrue);
    expect(export.trayFile.existsSync(), isTrue);

    // Tray is a 96×96 PNG within WhatsApp's 50 KB cap.
    final tray = export.trayFile.readAsBytesSync();
    expect(tray.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    expect(tray.length, lessThanOrEqualTo(50 * 1024));
    final trayImg = img.decodePng(tray)!;
    expect([trayImg.width, trayImg.height], [96, 96]);

    // contents.json schema.
    final wa =
        (export.contents['sticker_packs'] as List).single
            as Map<String, dynamic>;
    expect(wa['identifier'], 'pack1');
    expect(wa['name'], 'Doggos');
    expect(wa['publisher'], 'Sticker Maker');
    expect(wa['animated_sticker_pack'], isFalse);
    expect(wa['tray_image_file'], 'tray.png');

    final stickers = wa['stickers'] as List;
    expect(stickers.length, 3);
    expect((stickers[0] as Map)['image_file'], '0.webp');
    expect((stickers[1] as Map)['emojis'], ['🐱', '😹']);

    // Each sticker is a valid, exactly-512² WebP within the 100 KB static cap.
    for (var i = 0; i < 3; i++) {
      final bytes = File('${export.directory.path}/$i.webp').readAsBytesSync();
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WEBP');
      expect(bytes.length, lessThanOrEqualTo(100 * 1024));
      final decoded = img.decodeWebP(bytes)!;
      expect([decoded.width, decoded.height], [512, 512]);
    }
  });

  test('skips stickers whose project is missing', () async {
    const pack = StickerPack(
      id: 'p',
      name: 'P',
      stickers: [
        PackSticker(id: 'a', projectId: 'exists', emojis: ['🐶']),
        PackSticker(id: 'b', projectId: 'gone', emojis: ['🐱']),
      ],
    );
    final export = await WhatsAppPackExporter(
      baseDir: tmp,
    ).export(pack, {'exists': _proj('exists')});
    final stickers =
        ((export.contents['sticker_packs'] as List).single
                as Map<String, dynamic>)['stickers']
            as List;
    expect(stickers.length, 1);
  });

  test('throws when no sticker can render', () {
    expect(
      WhatsAppPackExporter(
        baseDir: tmp,
      ).export(const StickerPack(id: 'e', name: 'Empty'), const {}),
      throwsStateError,
    );
  });

  test('a photo-noise sticker engages the lossy ladder and still ships an '
      'exactly-512² WebP within 100 KB', () async {
    final noisy = writeNoisyPng(tmp);
    final fake = FakeStaticWebpEncoder(bytesFor: (q) => smallValidWebp512());
    const pack = StickerPack(
      id: 'photo',
      name: 'Photos',
      stickers: [
        PackSticker(id: 's0', projectId: 'noise', emojis: ['📷']),
        PackSticker(id: 's1', projectId: 'p1', emojis: ['🐶']),
        PackSticker(id: 's2', projectId: 'p2', emojis: ['🎉']),
      ],
    );
    final projects = {
      'noise': noisyProject('noise', noisy.path),
      'p1': _proj('p1'),
      'p2': _proj('p2'),
    };

    final export = await WhatsAppPackExporter(
      baseDir: tmp,
      staticEncoder: StaticWebpBudgetEncoder(lossy: fake),
    ).export(pack, projects);

    expect(
      fake.calls,
      isNotEmpty,
      reason: 'lossless VP8L overshoots 100 KB on noise → ladder engages',
    );
    // Every written sticker — including the photo one — is a valid WebP,
    // exactly 512², within WhatsApp's static cap.
    for (var i = 0; i < 3; i++) {
      final bytes = File('${export.directory.path}/$i.webp').readAsBytesSync();
      expect(bytes.length, lessThanOrEqualTo(100 * 1024));
      final decoded = img.decodeWebP(bytes)!;
      expect([decoded.width, decoded.height], [512, 512]);
    }
    expect(export.contentsFile.existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'an unfittable sticker aborts the export and never writes contents.json',
    () async {
      final noisy = writeNoisyPng(tmp);
      // Lossy output that never fits the 100 KB cap, at any quality.
      final fake = FakeStaticWebpEncoder(
        bytesFor: (q) => Uint8List(200 * 1024),
      );
      const pack = StickerPack(
        id: 'big',
        name: 'Big',
        stickers: [
          PackSticker(id: 's0', projectId: 'noise', emojis: ['📷']),
        ],
      );

      await expectLater(
        WhatsAppPackExporter(
          baseDir: tmp,
          staticEncoder: StaticWebpBudgetEncoder(lossy: fake),
        ).export(pack, {'noise': noisyProject('noise', noisy.path)}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('noise'),
          ),
        ),
      );

      // The half-built directory must never gain a manifest — without
      // contents.json the ContentProvider serves no pack at all.
      expect(
        File('${tmp.path}/wa_export/big/contents.json').existsSync(),
        isFalse,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('the final compliance gate blocks a sticker without emoji tags before '
      'contents.json is written', () async {
    const pack = StickerPack(
      id: 'gate',
      name: 'Gate',
      stickers: [
        PackSticker(id: 's0', projectId: 'p0'), // no emojis
      ],
    );

    await expectLater(
      WhatsAppPackExporter(baseDir: tmp).export(pack, {'p0': _proj('p0')}),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', contains('p0')),
      ),
    );
    expect(
      File('${tmp.path}/wa_export/gate/contents.json').existsSync(),
      isFalse,
    );
  });

  test(
    'an animated pack encodes every sticker through the animated path',
    () async {
      const pack = StickerPack(
        id: 'anim1',
        name: 'Movers',
        animated: true,
        stickers: [
          PackSticker(id: 's0', projectId: 'a0', emojis: ['🎬']),
          PackSticker(id: 's1', projectId: 'a1', emojis: ['✨']),
        ],
      );
      final projects = {'a0': _animProj('a0'), 'a1': _animProj('a1')};

      final export = await WhatsAppPackExporter(
        baseDir: tmp,
        animated: _fakeAnimatedService(),
      ).export(pack, projects);

      // Both stickers written via the animated encoder (fake bytes, non-empty).
      for (var i = 0; i < 2; i++) {
        final f = File('${export.directory.path}/$i.webp');
        expect(f.existsSync(), isTrue);
        expect(f.lengthSync(), greaterThan(0));
      }
      final packJson =
          (export.contents['sticker_packs'] as List).first
              as Map<String, dynamic>;
      expect(packJson['animated_sticker_pack'], isTrue);
    },
  );
}
