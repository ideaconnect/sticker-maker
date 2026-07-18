import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
        TextLayer(id: '${id}_t', name: 'W', text: 'W', fontFamily: 'Rubik'),
      ],
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(WhatsAppPackInstaller.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory tmp;
  final calls = <MethodCall>[];

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sm_wai_');
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'isWhatsAppInstalled') return true;
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('isWhatsAppInstalled proxies the platform channel', () async {
    final installer = WhatsAppPackInstaller(channel: channel);
    expect(await installer.isWhatsAppInstalled(), isTrue);
    expect(calls.single.method, 'isWhatsAppInstalled');
  });

  test('addToWhatsApp exports the pack, then invokes addStickerPack', () async {
    final installer = WhatsAppPackInstaller(channel: channel);
    const pack = StickerPack(
      id: 'p',
      name: 'Doggos',
      stickers: [
        PackSticker(id: 's', projectId: 'a', emojis: ['🐶']),
      ],
    );

    await installer.addToWhatsApp(pack, {'a': _proj('a')}, baseDir: tmp);

    // Exported into the provider's directory.
    expect(File('${tmp.path}/wa_export/p/contents.json').existsSync(), isTrue);
    expect(File('${tmp.path}/wa_export/p/tray.png').existsSync(), isTrue);
    expect(File('${tmp.path}/wa_export/p/0.webp').existsSync(), isTrue);

    // Then the add intent is fired with the pack id + name.
    final add = calls.firstWhere((c) => c.method == 'addStickerPack');
    final args = (add.arguments as Map).cast<String, dynamic>();
    expect(args['identifier'], 'p');
    expect(args['name'], 'Doggos');
  });
}
