import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/features/export/compliance_validator.dart';

/// A fully-compliant WhatsApp static sticker, overridable per-test.
StickerCandidate wa({
  int byteLength = 40 * 1024,
  int width = 512,
  int height = 512,
  String format = 'webp',
  bool animated = false,
  double durationSeconds = 0,
  List<String> emojis = const ['🐶'],
}) => StickerCandidate(
  byteLength: byteLength,
  width: width,
  height: height,
  format: format,
  animated: animated,
  durationSeconds: durationSeconds,
  emojis: emojis,
);

List<String> _messages(List<ComplianceIssue> issues) =>
    issues.map((i) => i.message).toList();

void main() {
  group('WhatsApp sticker rules', () {
    test('a compliant WebP sticker has no issues', () {
      expect(
        ComplianceValidator.validateSticker(wa(), StickerTarget.whatsapp),
        isEmpty,
      );
      expect(
        ComplianceValidator.isCompliant(wa(), StickerTarget.whatsapp),
        isTrue,
      );
    });

    test('non-512 dimensions fail', () {
      final issues = ComplianceValidator.validateSticker(
        wa(width: 400),
        StickerTarget.whatsapp,
      );
      expect(_messages(issues).join(), contains('512×512'));
    });

    test('a non-WebP format fails', () {
      final issues = ComplianceValidator.validateSticker(
        wa(format: 'png'),
        StickerTarget.whatsapp,
      );
      expect(_messages(issues).join(), contains('WebP'));
    });

    test('a static sticker over 100 KB fails', () {
      final issues = ComplianceValidator.validateSticker(
        wa(byteLength: 120 * 1024),
        StickerTarget.whatsapp,
      );
      expect(_messages(issues).join(), contains('100 KB'));
    });

    test('an animated sticker over 500 KB fails', () {
      final issues = ComplianceValidator.validateSticker(
        wa(animated: true, byteLength: 600 * 1024, durationSeconds: 3),
        StickerTarget.whatsapp,
      );
      expect(_messages(issues).join(), contains('500 KB'));
    });

    test('an animation over 10 s fails', () {
      final issues = ComplianceValidator.validateSticker(
        wa(animated: true, durationSeconds: 12),
        StickerTarget.whatsapp,
      );
      expect(_messages(issues).join(), contains('10 s'));
    });

    test('zero emojis fails', () {
      final issues = ComplianceValidator.validateSticker(
        wa(emojis: const []),
        StickerTarget.whatsapp,
      );
      expect(_messages(issues).join().toLowerCase(), contains('emoji'));
    });

    test('more than 3 emojis fails', () {
      final issues = ComplianceValidator.validateSticker(
        wa(emojis: const ['🐶', '🐱', '🐭', '🐹']),
        StickerTarget.whatsapp,
      );
      expect(_messages(issues).join(), contains('up to 3'));
    });
  });

  group('Telegram sticker rules', () {
    test('a static PNG at 512 is compliant', () {
      expect(
        ComplianceValidator.validateSticker(
          wa(format: 'png', emojis: const []),
          StickerTarget.telegram,
        ),
        isEmpty,
        reason: 'Telegram allows PNG and does not require emojis',
      );
    });

    test('a compliant WebM video sticker has no issues', () {
      const s = StickerCandidate(
        byteLength: 200 * 1024,
        width: 512,
        height: 512,
        format: 'webm',
        animated: true,
        durationSeconds: 2.5,
      );
      expect(
        ComplianceValidator.validateSticker(s, StickerTarget.telegram),
        isEmpty,
      );
    });

    test('a video over 3 s or 256 KB fails', () {
      const s = StickerCandidate(
        byteLength: 300 * 1024,
        width: 512,
        height: 512,
        format: 'webm',
        animated: true,
        durationSeconds: 4,
      );
      final msg = _messages(
        ComplianceValidator.validateSticker(s, StickerTarget.telegram),
      ).join();
      expect(msg, contains('256 KB'));
      expect(msg, contains('3 s'));
    });

    test('a non-WebM animated sticker fails', () {
      const s = StickerCandidate(
        byteLength: 100 * 1024,
        width: 512,
        height: 512,
        format: 'gif',
        animated: true,
        durationSeconds: 2,
      );
      expect(
        _messages(
          ComplianceValidator.validateSticker(s, StickerTarget.telegram),
        ).join(),
        contains('WebM'),
      );
    });
  });

  group('pack rules (WhatsApp)', () {
    test('3–30 same-kind stickers pass', () {
      expect(
        ComplianceValidator.validatePack(
          stickerCount: 5,
          hasStatic: true,
          hasAnimated: false,
        ),
        isEmpty,
      );
    });

    test('fewer than 3 fails', () {
      expect(
        _messages(
          ComplianceValidator.validatePack(
            stickerCount: 2,
            hasStatic: true,
            hasAnimated: false,
          ),
        ).join(),
        contains('at least 3'),
      );
    });

    test('more than 30 fails', () {
      expect(
        _messages(
          ComplianceValidator.validatePack(
            stickerCount: 31,
            hasStatic: true,
            hasAnimated: false,
          ),
        ).join(),
        contains('at most 30'),
      );
    });

    test('mixing static and animated fails', () {
      expect(
        _messages(
          ComplianceValidator.validatePack(
            stickerCount: 5,
            hasStatic: true,
            hasAnimated: true,
          ),
        ).join(),
        contains('all static or all animated'),
      );
    });
  });

  group('tray icon rules', () {
    test('96x96 PNG under 50 KB passes', () {
      expect(
        ComplianceValidator.validateTrayIcon(
          byteLength: 20 * 1024,
          width: 96,
          height: 96,
          format: 'png',
        ),
        isEmpty,
      );
    });

    test('wrong size / format / bytes each fail', () {
      final issues = ComplianceValidator.validateTrayIcon(
        byteLength: 60 * 1024,
        width: 128,
        height: 128,
        format: 'webp',
      );
      final msg = _messages(issues).join();
      expect(msg, contains('96×96'));
      expect(msg, contains('PNG'));
      expect(msg, contains('50 KB'));
    });
  });
}
