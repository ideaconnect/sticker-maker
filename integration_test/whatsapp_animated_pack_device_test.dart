// ANIM-5 (#70) on-device verification: a fully ANIMATED WhatsApp pack —
// 3 stickers, each a real 2-frame project encoded to animated WebP by the
// bundled FFmpeg on this device — exported through StickerContentProvider and
// handed to WhatsApp via ENABLE_STICKER_PACK. Holds 45 s so WhatsApp's
// "Add to WhatsApp?" dialog can be screenshotted before the post-run uninstall.
//
//   flutter test integration_test/whatsapp_animated_pack_device_test.dart -d <device>

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/features/packs/sticker_pack.dart';
import 'package:sticker_maker/features/packs/whatsapp_pack_installer.dart';

StickerProject _animProj(String id, String word) => StickerProject(
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
            text: '$word${'!' * (i + 1)}',
            fontFamily: 'Bangers',
            fontSize: 40.0 + 14 * i,
          ),
        ],
      ),
  ],
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'exports an ANIMATED pack and hands it to WhatsApp',
    (tester) async {
      final projects = [
        _animProj('an_0', 'WOOF'),
        _animProj('an_1', 'MEOW'),
        _animProj('an_2', 'YAY'),
      ];
      final byId = {for (final p in projects) p.id: p};
      const pack = StickerPack(
        id: 'sm_anim_pack',
        name: 'SM Animated Test',
        animated: true,
        stickers: [
          PackSticker(id: 's0', projectId: 'an_0', emojis: ['🐶']),
          PackSticker(id: 's1', projectId: 'an_1', emojis: ['🐱']),
          PackSticker(id: 's2', projectId: 'an_2', emojis: ['🎉']),
        ],
      );

      final installer = WhatsAppPackInstaller();
      expect(
        await installer.isWhatsAppInstalled(),
        isTrue,
        reason: 'WhatsApp must be installed for this device test',
      );

      // Renders each sticker as an animated WebP (real FFmpeg encode on-device),
      // writes contents.json with animated_sticker_pack=true, fires the intent.
      await installer.addToWhatsApp(pack, byId);
      // ignore: avoid_print
      print('ANIM_PACK_INTENT_FIRED');

      // Hold so WhatsApp's dialog is on screen for a screenshot.
      await Future<void>.delayed(const Duration(seconds: 45));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
