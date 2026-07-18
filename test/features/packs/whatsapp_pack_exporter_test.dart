import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/features/packs/sticker_pack.dart';
import 'package:sticker_maker/features/packs/whatsapp_pack_exporter.dart';

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
}
