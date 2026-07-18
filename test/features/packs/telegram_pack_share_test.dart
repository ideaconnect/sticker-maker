import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/features/packs/sticker_pack.dart';
import 'package:sticker_maker/features/packs/telegram_pack_share.dart';

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
  setUp(() => tmp = Directory.systemTemp.createTempSync('sm_tgs_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('exports the pack, then hands its files to the share sheet', () async {
    var sharedText = '';
    final sharedPaths = <String>[];
    final service = TelegramPackShare(
      shareFiles: (paths, text) async {
        sharedPaths.addAll(paths);
        sharedText = text;
      },
    );

    const pack = StickerPack(
      id: 'p',
      name: 'Doggos',
      stickers: [
        PackSticker(id: 's0', projectId: 'a', emojis: ['🐶']),
        PackSticker(id: 's1', projectId: 'b', emojis: ['🐱']),
      ],
    );

    final export = await service.share(pack, {
      'a': _proj('a'),
      'b': _proj('b'),
    }, baseDir: tmp);

    // Both rendered files were handed off, with the @Stickers guidance.
    expect(sharedPaths.length, 2);
    expect(sharedPaths.first, endsWith('0.webp'));
    expect(sharedText, TelegramPackShare.guidance);
    // The export is returned so the UI can surface the suggested short name.
    expect(export.shortNameSuggestion, 'doggos');
  });
}
