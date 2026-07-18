// On-device verification of the WhatsApp pack hand-off (#46).
//
// Exports a 3-sticker pack into the app's files dir (where StickerContentProvider
// serves it) and fires the ENABLE_STICKER_PACK intent, then holds so WhatsApp's
// "Add to WhatsApp?" dialog can be screenshotted before the post-run uninstall
// wipes the export. Needs WhatsApp installed; run:
//   flutter test integration_test/whatsapp_add_device_test.dart -d <device>

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/features/packs/sticker_pack.dart';
import 'package:sticker_maker/features/packs/whatsapp_pack_installer.dart';

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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'exports a pack and hands it to WhatsApp',
    (tester) async {
      final projects = [for (var i = 0; i < 3; i++) _proj('wa_$i')];
      final byId = {for (final p in projects) p.id: p};
      final pack = StickerPack(
        id: 'sm_device_pack',
        name: 'Sticker Maker Test',
        stickers: [
          for (var i = 0; i < 3; i++)
            PackSticker(id: 's$i', projectId: 'wa_$i', emojis: const ['🐶']),
        ],
      );

      final installer = WhatsAppPackInstaller();
      expect(
        await installer.isWhatsAppInstalled(),
        isTrue,
        reason: 'WhatsApp must be installed for this device test',
      );

      // Renders → filesDir/wa_export/<id>/ and fires ENABLE_STICKER_PACK.
      await installer.addToWhatsApp(pack, byId);

      // Hold so the WhatsApp dialog is on screen for a screenshot.
      await Future<void>.delayed(const Duration(seconds: 45));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
