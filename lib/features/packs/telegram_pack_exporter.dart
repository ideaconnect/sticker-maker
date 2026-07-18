import 'dart:io';

import '../../core/models/sticker_project.dart';
import '../export/animated_export_service.dart';
import '../export/animation_encoder.dart';
import '../export/sticker_encoder.dart';
import 'sticker_pack.dart';
import 'telegram_links.dart';

/// The rendered artifacts for the guided Telegram @Stickers flow (ADR 0003 / #48):
/// one 512² WebP per sticker (in pack order) that the user sends to @Stickers,
/// plus a suggested pack short name and the `/newpack` vs `/newvideo` command.
class TelegramPackExport {
  const TelegramPackExport({
    required this.files,
    required this.emojis,
    required this.shortNameSuggestion,
    required this.animated,
  });

  /// One rendered sticker file per entry, in pack order.
  final List<File> files;

  /// The emoji tags for each sticker (parallel to [files]) — the user pastes
  /// these when @Stickers asks.
  final List<List<String>> emojis;

  /// A valid Telegram set short-name suggestion derived from the pack name.
  final String shortNameSuggestion;

  /// Whether this is a video pack (uses `/newvideo`); static uses `/newpack`.
  final bool animated;

  /// The @Stickers command to start this pack (deep-linked, prefilled).
  Uri get startCommand => TelegramLinks.newPackCommand(animated: animated);
}

/// Renders a [StickerPack] to shareable files for Telegram's @Stickers bot.
/// Pure IO + rendering (no platform channels) so it's unit-testable; the share
/// + deep-link hand-off is the UI layer's job.
///
/// Static stickers are 512² WebP (Telegram accepts WebP/PNG). Animated packs
/// render **WebM VP9 + alpha video stickers** (#70 / ADR 0004) — the format
/// @Stickers' `/newvideo` flow requires.
class TelegramPackExporter {
  TelegramPackExporter({Directory? baseDir, AnimatedExportService? animated})
    : _baseOverride = baseDir,
      _animatedOverride = animated;

  final Directory? _baseOverride;
  final AnimatedExportService? _animatedOverride;
  AnimatedExportService? _animatedLazy;

  /// Constructed on first animated use so static-only paths never touch the
  /// FFmpeg plugin (keeps host tests plugin-free).
  AnimatedExportService get _animated =>
      _animatedOverride ?? (_animatedLazy ??= AnimatedExportService());

  /// Telegram sticker edge (px).
  static const int stickerEdge = 512;

  Future<TelegramPackExport> export(
    StickerPack pack,
    Map<String, StickerProject> projects,
  ) async {
    final base = _baseOverride ?? Directory.systemTemp;
    final dir = Directory('${base.path}/tg_export/${pack.id}');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    await dir.create(recursive: true);

    final files = <File>[];
    final emojis = <List<String>>[];
    var index = 0;
    for (final sticker in pack.stickers) {
      final project = projects[sticker.projectId];
      if (project == null) continue;
      final encoded = pack.animated
          ? await _animated.encode(project, AnimationSpec.telegramWebm)
          : await StickerEncoder.webp(project.currentFrame);
      final file = File('${dir.path}/$index.${encoded.format}')
        ..writeAsBytesSync(encoded.bytes);
      files.add(file);
      emojis.add(sticker.emojis);
      index++;
    }

    if (files.isEmpty) {
      throw StateError('pack "${pack.id}" has no renderable stickers');
    }

    return TelegramPackExport(
      files: files,
      emojis: emojis,
      shortNameSuggestion: TelegramLinks.suggestShortName(pack.name),
      animated: pack.animated,
    );
  }
}
