/// Which messenger a sticker / pack is being exported to.
enum StickerTarget { whatsapp, telegram }

enum IssueSeverity { error, warning }

/// A single human-readable compliance problem, with a fix-it hint.
class ComplianceIssue {
  const ComplianceIssue(this.message, {this.severity = IssueSeverity.error});

  final String message;
  final IssueSeverity severity;

  bool get isError => severity == IssueSeverity.error;

  @override
  String toString() => '${severity.name}: $message';
}

/// One sticker to check against a target's format rules.
class StickerCandidate {
  const StickerCandidate({
    required this.byteLength,
    required this.width,
    required this.height,
    required this.format,
    this.animated = false,
    this.durationSeconds = 0,
    this.emojis = const [],
  });

  final int byteLength;
  final int width;
  final int height;

  /// `png` | `webp` | `webm` | `gif`.
  final String format;
  final bool animated;
  final double durationSeconds;
  final List<String> emojis;
}

/// Central per-target compliance validation. Pure and message-driven — run
/// before any pack/share action; every rule maps to the §4 format table and is
/// unit-tested. Returns an empty list when compliant.
abstract final class ComplianceValidator {
  ComplianceValidator._();

  // ---- format-table constants (§4) ----
  static const int _edge = 512;
  static const int _waStaticMax = 100 * 1024;
  static const int _waAnimatedMax = 500 * 1024;
  static const double _waAnimatedSecondsMax = 10;
  static const int _waPackMin = 3;
  static const int _waPackMax = 30;
  static const int _tgVideoMax = 256 * 1024;
  static const double _tgVideoSecondsMax = 3;
  static const int _trayEdge = 96;
  static const int _trayMax = 50 * 1024;

  static String _kb(int bytes) => '${(bytes / 1024).round()} KB';

  static bool isCompliant(StickerCandidate s, StickerTarget target) =>
      validateSticker(s, target).every((i) => !i.isError);

  static List<ComplianceIssue> validateSticker(
    StickerCandidate s,
    StickerTarget target,
  ) {
    final issues = <ComplianceIssue>[];
    // Both targets: 512×512.
    if (s.width != _edge || s.height != _edge) {
      issues.add(
        ComplianceIssue(
          'Stickers must be $_edge×$_edge px (this is ${s.width}×${s.height}).',
        ),
      );
    }
    switch (target) {
      case StickerTarget.whatsapp:
        _whatsapp(s, issues);
      case StickerTarget.telegram:
        _telegram(s, issues);
    }
    return issues;
  }

  static void _whatsapp(StickerCandidate s, List<ComplianceIssue> issues) {
    if (s.format != 'webp') {
      issues.add(
        const ComplianceIssue(
          'WhatsApp needs WebP — export as WebP to add it to a pack.',
        ),
      );
    }
    if (s.animated) {
      if (s.byteLength > _waAnimatedMax) {
        issues.add(
          ComplianceIssue(
            'Animation is ${_kb(s.byteLength)} — WhatsApp allows '
            '${_kb(_waAnimatedMax)}. Reduce frames or quality.',
          ),
        );
      }
      if (s.durationSeconds > _waAnimatedSecondsMax) {
        issues.add(
          ComplianceIssue(
            'Animation is ${s.durationSeconds.toStringAsFixed(1)} s — WhatsApp '
            'allows ${_waAnimatedSecondsMax.toStringAsFixed(0)} s. Trim frames '
            'or speed it up.',
          ),
        );
      }
    } else if (s.byteLength > _waStaticMax) {
      issues.add(
        ComplianceIssue(
          'Sticker is ${_kb(s.byteLength)} — WhatsApp allows '
          '${_kb(_waStaticMax)}. Simplify the image.',
        ),
      );
    }
    // WhatsApp requires 1–3 emoji tags per sticker.
    if (s.emojis.isEmpty) {
      issues.add(
        const ComplianceIssue('Add 1–3 emojis so WhatsApp can suggest it.'),
      );
    } else if (s.emojis.length > 3) {
      issues.add(
        ComplianceIssue(
          'Too many emojis (${s.emojis.length}) — WhatsApp allows up to 3.',
        ),
      );
    }
  }

  static void _telegram(StickerCandidate s, List<ComplianceIssue> issues) {
    if (s.animated) {
      if (s.format != 'webm') {
        issues.add(
          const ComplianceIssue('Telegram video stickers must be WebM (VP9).'),
        );
      }
      if (s.byteLength > _tgVideoMax) {
        issues.add(
          ComplianceIssue(
            'Video is ${_kb(s.byteLength)} — Telegram allows '
            '${_kb(_tgVideoMax)}. Reduce quality or duration.',
          ),
        );
      }
      if (s.durationSeconds > _tgVideoSecondsMax) {
        issues.add(
          ComplianceIssue(
            'Video is ${s.durationSeconds.toStringAsFixed(1)} s — Telegram '
            'allows ${_tgVideoSecondsMax.toStringAsFixed(0)} s.',
          ),
        );
      }
    } else if (s.format != 'png' && s.format != 'webp') {
      issues.add(
        const ComplianceIssue('Telegram static stickers must be PNG or WebP.'),
      );
    }
  }

  /// Pack-level rules: WhatsApp requires 3–30 stickers, all static or all
  /// animated (no mixing).
  static List<ComplianceIssue> validatePack({
    required int stickerCount,
    required bool hasStatic,
    required bool hasAnimated,
    StickerTarget target = StickerTarget.whatsapp,
  }) {
    final issues = <ComplianceIssue>[];
    if (target == StickerTarget.whatsapp) {
      if (stickerCount < _waPackMin) {
        issues.add(
          ComplianceIssue(
            'A WhatsApp pack needs at least $_waPackMin stickers '
            '(has $stickerCount). Add ${_waPackMin - stickerCount} more.',
          ),
        );
      } else if (stickerCount > _waPackMax) {
        issues.add(
          ComplianceIssue(
            'A WhatsApp pack allows at most $_waPackMax stickers '
            '(has $stickerCount).',
          ),
        );
      }
      if (hasStatic && hasAnimated) {
        issues.add(
          const ComplianceIssue(
            'A pack must be all static or all animated — not mixed.',
          ),
        );
      }
    }
    return issues;
  }

  /// WhatsApp tray icon: 96×96 PNG, ≤ 50 KB.
  static List<ComplianceIssue> validateTrayIcon({
    required int byteLength,
    required int width,
    required int height,
    required String format,
  }) {
    final issues = <ComplianceIssue>[];
    if (width != _trayEdge || height != _trayEdge) {
      issues.add(
        ComplianceIssue(
          'Tray icon must be $_trayEdge×$_trayEdge px (this is $width×$height).',
        ),
      );
    }
    if (format != 'png') {
      issues.add(const ComplianceIssue('Tray icon must be a PNG.'));
    }
    if (byteLength > _trayMax) {
      issues.add(
        ComplianceIssue(
          'Tray icon is ${_kb(byteLength)} — the limit is ${_kb(_trayMax)}.',
        ),
      );
    }
    return issues;
  }
}
