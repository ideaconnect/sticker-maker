import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/sticker_project.dart';
import '../../core/platform/platform_services.dart';
import 'sticker_pack.dart';
import 'telegram_pack_exporter.dart';

/// Drives the guided Telegram @Stickers flow (ADR 0003 / #48): renders the pack
/// to WebP files and hands them to the system share sheet so the user can send
/// them to @Stickers, then returns the export so the UI can show the suggested
/// pack short name and next steps. The share callback is injectable for tests.
class TelegramPackShare {
  TelegramPackShare({
    Future<void> Function(List<String> paths, String text)? shareFiles,
  }) : _shareFiles = shareFiles ?? _defaultShare;

  final Future<void> Function(List<String> paths, String text) _shareFiles;

  static Future<void> _defaultShare(List<String> paths, String text) async {
    // Video stickers are .webm documents; static are .webp images.
    final mime = paths.any((p) => p.endsWith('.webm'))
        ? 'video/webm'
        : 'image/webp';
    // Prefer Telegram's own chat picker (Saved Messages / @Stickers one tap
    // away); fall back to the system share sheet when Telegram is absent.
    if (await PlatformServices().shareToTelegram(paths, mime)) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [for (final p in paths) XFile(p, mimeType: mime)],
        text: text,
      ),
    );
  }

  static const guidance =
      'Send these to @Stickers on Telegram (as files), then follow its '
      'prompts to tag emojis and /publish.';

  Future<TelegramPackExport> share(
    StickerPack pack,
    Map<String, StickerProject> projects, {
    Directory? baseDir,
  }) async {
    final base = baseDir ?? await getTemporaryDirectory();
    final export = await TelegramPackExporter(
      baseDir: base,
    ).export(pack, projects);
    await _shareFiles([for (final f in export.files) f.path], guidance);
    return export;
  }
}

final telegramPackShareProvider = Provider<TelegramPackShare>(
  (ref) => TelegramPackShare(),
);
