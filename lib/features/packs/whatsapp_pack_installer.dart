import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/models/sticker_project.dart';
import 'sticker_pack.dart';
import 'whatsapp_pack_exporter.dart';

/// Bridges a [StickerPack] to WhatsApp (#46): renders it into the app's files
/// directory — where the native `StickerContentProvider` serves it — then fires
/// the `ENABLE_STICKER_PACK` intent via the platform channel.
class WhatsAppPackInstaller {
  WhatsAppPackInstaller({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'sticker_maker/whatsapp';

  final MethodChannel _channel;

  Future<bool> isWhatsAppInstalled() async =>
      await _channel.invokeMethod<bool>('isWhatsAppInstalled') ?? false;

  /// Exports [pack] (rendering [projects] keyed by projectId) into
  /// `getApplicationSupportDirectory()/wa_export/<packId>/` — which resolves to
  /// `context.filesDir/wa_export`, the location the ContentProvider reads — then
  /// asks WhatsApp to add it. [baseDir] overrides the export root in tests.
  Future<void> addToWhatsApp(
    StickerPack pack,
    Map<String, StickerProject> projects, {
    Directory? baseDir,
  }) async {
    final base = baseDir ?? await getApplicationSupportDirectory();
    await WhatsAppPackExporter(baseDir: base).export(pack, projects);
    await _channel.invokeMethod<void>('addStickerPack', {
      'identifier': pack.id,
      'name': pack.name,
    });
  }
}

final whatsAppPackInstallerProvider = Provider<WhatsAppPackInstaller>(
  (ref) => WhatsAppPackInstaller(),
);
