import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/features/export/animated_export_service.dart';
import 'package:sticker_maker/features/export/animation_encoder.dart';
import 'package:sticker_maker/features/packs/sticker_pack.dart';
import 'package:sticker_maker/features/packs/telegram_pack_exporter.dart';

StickerProject _proj(String id) => StickerProject(
  id: id,
  name: id,
  frames: [
    Frame(
      id: '${id}_f',
      layers: [
        TextLayer(id: '${id}_t', name: 'S', text: 'S', fontFamily: 'Rubik'),
      ],
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sm_tg_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test(
    'renders one 512² WebP per sticker with emoji tags + short name',
    () async {
      const pack = StickerPack(
        id: 'my_pack',
        name: 'Happy Dogs!',
        stickers: [
          PackSticker(id: 's0', projectId: 'p0', emojis: ['🐶']),
          PackSticker(id: 's1', projectId: 'p1', emojis: ['🐱', '😹']),
        ],
      );
      final projects = {'p0': _proj('p0'), 'p1': _proj('p1')};

      final export = await TelegramPackExporter(
        baseDir: tmp,
      ).export(pack, projects);

      expect(export.files.length, 2);
      expect(export.emojis[1], ['🐱', '😹']);
      expect(export.shortNameSuggestion, 'happy_dogs');
      expect(export.animated, isFalse);
      // Static pack → /newpack command deep link.
      expect(export.startCommand.queryParameters['text'], '/newpack');

      for (final file in export.files) {
        expect(file.existsSync(), isTrue);
        final bytes = file.readAsBytesSync();
        expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WEBP');
        final decoded = img.decodeWebP(bytes)!;
        expect([decoded.width, decoded.height], [512, 512]);
      }
    },
  );

  test('an animated pack uses the /newvideo command', () async {
    const pack = StickerPack(
      id: 'vid',
      name: 'Vid',
      animated: true,
      stickers: [
        PackSticker(id: 's', projectId: 'p', emojis: ['🎬']),
      ],
    );
    final export = await TelegramPackExporter(
      baseDir: tmp,
      // Animated packs render through the animated service — fake it here
      // (the real one needs the FFmpeg plugin, absent on the host).
      animated: AnimatedExportService(
        webmEncoder: FakeAnimationEncoder(id: 'webm', format: 'webm'),
        webpEncoder: FakeAnimationEncoder(id: 'webp'),
        rasterizer: (frame, durationMs) async => RgbaFrame(
          bytes: Uint8List(16),
          width: 2,
          height: 2,
          durationMs: durationMs,
        ),
      ),
    ).export(pack, {'p': _proj('p')});
    expect(export.animated, isTrue);
    expect(export.startCommand.queryParameters['text'], '/newvideo');
  });

  test('skips missing projects and throws when nothing renders', () async {
    expect(
      TelegramPackExporter(
        baseDir: tmp,
      ).export(const StickerPack(id: 'e', name: 'E'), const {}),
      throwsStateError,
    );
  });

  test('an animated pack renders .webm video stickers', () async {
    const pack = StickerPack(
      id: 'vid2',
      name: 'Vid Two',
      animated: true,
      stickers: [
        PackSticker(id: 's', projectId: 'p', emojis: ['🎬']),
      ],
    );
    final project = StickerProject(
      id: 'p',
      name: 'p',
      frames: [
        for (var i = 0; i < 2; i++)
          Frame(
            id: 'f$i',
            layers: [
              TextLayer(id: 't$i', name: 'S', text: 'S$i', fontFamily: 'Rubik'),
            ],
          ),
      ],
    );
    final service = AnimatedExportService(
      webmEncoder: FakeAnimationEncoder(id: 'webm', format: 'webm'),
      webpEncoder: FakeAnimationEncoder(id: 'webp'),
      rasterizer: (frame, durationMs) async => RgbaFrame(
        bytes: Uint8List(16),
        width: 2,
        height: 2,
        durationMs: durationMs,
      ),
    );

    final export = await TelegramPackExporter(
      baseDir: tmp,
      animated: service,
    ).export(pack, {'p': project});

    expect(export.files.single.path, endsWith('0.webm'));
    expect(export.files.single.lengthSync(), greaterThan(0));
    expect(export.animated, isTrue);
    expect(export.startCommand.queryParameters['text'], '/newvideo');
  });
}
