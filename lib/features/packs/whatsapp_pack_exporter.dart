import 'dart:convert';
import 'dart:io';

import '../../core/models/sticker_project.dart';
import '../export/animated_export_service.dart';
import '../export/animation_encoder.dart';
import '../export/sticker_encoder.dart';
import '../export/sticker_renderer.dart';
import 'sticker_pack.dart';

/// The result of exporting a [StickerPack] to WhatsApp's on-disk layout: a
/// directory containing `contents.json`, a `tray.png`, and one `<i>.webp` per
/// sticker. The native ContentProvider (#46) serves these to WhatsApp via
/// `content://` URIs; the `ENABLE_STICKER_PACK` intent then installs the pack.
class WhatsAppPackExport {
  const WhatsAppPackExport({required this.directory, required this.contents});

  final Directory directory;

  /// The parsed `contents.json` (WhatsApp's sticker-pack manifest schema).
  final Map<String, dynamic> contents;

  File get contentsFile => File('${directory.path}/contents.json');
  File get trayFile => File('${directory.path}/tray.png');
}

/// Renders a [StickerPack] into the asset layout WhatsApp expects. Pure IO +
/// rendering (no platform channels), so it's fully unit-testable; the native
/// hand-off to WhatsApp lives in the ContentProvider (#46).
class WhatsAppPackExporter {
  WhatsAppPackExporter({Directory? baseDir, AnimatedExportService? animated})
    : _baseOverride = baseDir,
      _animatedOverride = animated;

  final Directory? _baseOverride;
  final AnimatedExportService? _animatedOverride;
  AnimatedExportService? _animatedLazy;

  /// Constructed on first animated use so static-only paths never touch the
  /// FFmpeg plugin (keeps host tests plugin-free).
  AnimatedExportService get _animated =>
      _animatedOverride ?? (_animatedLazy ??= AnimatedExportService());

  /// WhatsApp sticker edge (px).
  static const int stickerEdge = 512;

  /// WhatsApp tray-icon edge (px).
  static const int trayEdge = 96;

  /// Exports [pack] under `<base>/wa_export/<packId>/`, rendering each sticker's
  /// project ([projects] maps projectId → project) to a compliant WebP and a
  /// tray icon, and writing `contents.json`. Stickers whose project is missing
  /// are skipped. Throws [StateError] if nothing renders.
  Future<WhatsAppPackExport> export(
    StickerPack pack,
    Map<String, StickerProject> projects,
  ) async {
    final base = _baseOverride ?? Directory.systemTemp;
    final dir = Directory('${base.path}/wa_export/${pack.id}');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    await dir.create(recursive: true);

    final stickerEntries = <Map<String, dynamic>>[];
    StickerProject? firstProject;
    var index = 0;
    for (final sticker in pack.stickers) {
      final project = projects[sticker.projectId];
      if (project == null) continue;
      firstProject ??= project;
      // WhatsApp requires stickers to be *exactly* [stickerEdge]×[stickerEdge]
      // (the encoder default), never budget-downscaled. Animated packs encode
      // every sticker as an animated WebP within the 500 KB cap (#70); static
      // packs use lossless single-frame WebP (≤100 KB for simple stickers).
      final webp = pack.animated
          ? await _animated.encode(project, AnimationSpec.whatsappWebp)
          : await StickerEncoder.webp(project.currentFrame);
      final fileName = '$index.webp';
      await File('${dir.path}/$fileName').writeAsBytes(webp.bytes);
      stickerEntries.add({'image_file': fileName, 'emojis': sticker.emojis});
      index++;
    }

    if (firstProject == null) {
      throw StateError('pack "${pack.id}" has no renderable stickers');
    }

    // Tray icon: the first sticker, rendered small (96²) as PNG.
    final tray = await StickerRenderer.renderPng(
      firstProject.currentFrame,
      size: trayEdge,
    );
    await File('${dir.path}/tray.png').writeAsBytes(tray);

    final contents = <String, dynamic>{
      'android_play_store_link': '',
      'ios_app_store_link': '',
      'sticker_packs': [
        {
          'identifier': pack.id,
          'name': pack.name,
          'publisher': pack.publisher,
          'tray_image_file': 'tray.png',
          'image_data_version': '1',
          'avoid_cache': false,
          'animated_sticker_pack': pack.animated,
          'publisher_email': '',
          'publisher_website': '',
          'privacy_policy_website': '',
          'license_agreement_website': '',
          'stickers': stickerEntries,
        },
      ],
    };
    await File(
      '${dir.path}/contents.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(contents));

    return WhatsAppPackExport(directory: dir, contents: contents);
  }
}
