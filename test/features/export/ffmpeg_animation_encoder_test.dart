import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/features/export/animation_encoder.dart';
import 'package:sticker_maker/features/export/ffmpeg_animation_encoder.dart';

RgbaFrame _frame({int durationMs = 100, int edge = 4}) => RgbaFrame(
  bytes: Uint8List(edge * edge * 4),
  width: edge,
  height: edge,
  durationMs: durationMs,
);

/// A runner that records commands and "encodes" by writing [payload] to the
/// output path (the last token of the command).
FfmpegRunner _writingRunner(
  List<String> commands, {
  List<int> payload = const [1, 2, 3],
  bool success = true,
  String output = '',
}) => (command) async {
  commands.add(command);
  final outPath = command.split(' ').last;
  File(outPath).writeAsBytesSync(payload);
  return FfmpegRunResult(success: success, output: output);
};

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sm_ffenc_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('command construction', () {
    test('WebM VP9: yuva420p alpha, bitrate knob, no audio', () {
      final commands = <String>[];
      final enc = FfmpegWebmVp9Encoder(
        runner: _writingRunner(commands),
        scratchDir: tmp,
      );
      final cmd = enc.buildCommand(
        tmp,
        '${tmp.path}/out.webm',
        [_frame(durationMs: 33)],
        quality: 320,
        loop: true,
      );
      expect(cmd, contains('-c:v libvpx-vp9'));
      expect(cmd, contains('-pix_fmt yuva420p'), reason: 'alpha is mandatory');
      expect(cmd, contains('-b:v 320K'));
      expect(cmd, contains('-an'));
      // 33 ms/frame → 30.3 fps, clamped to Telegram's 30-fps cap.
      expect(cmd, contains('-framerate 30.000'));
      expect(cmd, contains('%d.png'));
    });

    test('animated WebP: libwebp_anim, quality knob, infinite loop', () {
      final enc = FfmpegAnimWebpEncoder(
        runner: _writingRunner([]),
        scratchDir: tmp,
      );
      final cmd = enc.buildCommand(
        tmp,
        '${tmp.path}/out.webp',
        [_frame()],
        quality: 70,
        loop: true,
      );
      expect(cmd, contains('-c:v libwebp_anim'));
      expect(cmd, contains('-q:v 70'));
      expect(cmd, contains('-loop 0'), reason: '0 = infinite loop in webp');
      expect(cmd, contains('-framerate 10.000'));
    });

    test('framerate is clamped to 30 for very short frame durations', () {
      final enc = FfmpegWebmVp9Encoder(
        runner: _writingRunner([]),
        scratchDir: tmp,
      );
      final cmd = enc.buildCommand(
        tmp,
        '${tmp.path}/o.webm',
        [_frame(durationMs: 8)], // 125 fps uncapped
        quality: 100,
        loop: true,
      );
      expect(cmd, contains('-framerate 30.000'));
    });
  });

  group('encode()', () {
    test('writes the frame sequence, runs ffmpeg, returns the bytes', () async {
      final commands = <String>[];
      final enc = FfmpegWebmVp9Encoder(
        runner: _writingRunner(commands, payload: [9, 9, 9, 9]),
        scratchDir: tmp,
      );
      final bytes = await enc.encode(
        [_frame(), _frame(), _frame()],
        quality: 200,
        loop: true,
      );
      expect(bytes, [9, 9, 9, 9]);
      expect(commands, hasLength(1));
      // The scratch frame dir is cleaned up afterwards.
      expect(
        tmp.listSync().whereType<Directory>(),
        isEmpty,
        reason: 'scratch dir removed after encode',
      );
    });

    test('a failed session surfaces as a StateError with the log tail', () {
      final enc = FfmpegAnimWebpEncoder(
        runner: (c) async =>
            const FfmpegRunResult(success: false, output: 'boom: no encoder'),
        scratchDir: tmp,
      );
      expect(
        enc.encode([_frame()], quality: 70, loop: true),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('boom'),
          ),
        ),
      );
    });
  });

  group('prepare()', () {
    test(
      'writes the PNG sequence once; each encode re-runs only ffmpeg',
      () async {
        final commands = <String>[];
        final enc = FfmpegAnimWebpEncoder(
          runner: _writingRunner(commands),
          scratchDir: tmp,
        );

        final session = await enc.prepare([_frame(), _frame(), _frame()]);
        final scratch = tmp.listSync().whereType<Directory>().single;
        expect(
          scratch.listSync().whereType<File>().where(
            (f) => f.path.endsWith('.png'),
          ),
          hasLength(3),
          reason: 'the %d.png sequence is written at prepare time',
        );
        expect(commands, isEmpty, reason: 'no ffmpeg run until encode');

        await session.encode(quality: 80, loop: true);
        await session.encode(quality: 50, loop: true);
        expect(commands, hasLength(2));
        expect(commands[0], contains('-q:v 80'));
        expect(commands[1], contains('-q:v 50'));
        // Both rungs read the SAME prepared sequence (compare by dir name —
        // the command mixes separators on Windows).
        final scratchName = scratch.path.replaceAll('\\', '/').split('/').last;
        expect(commands[0], contains(scratchName));
        expect(commands[1], contains(scratchName));

        await session.dispose();
        expect(scratch.existsSync(), isFalse, reason: 'dispose cleans up');
        // dispose is idempotent.
        await session.dispose();
      },
    );

    test('the budget search reuses one scratch dir across all rungs', () async {
      final commands = <String>[];
      // The 5-byte payload never fits the 3-byte cap → every rung runs.
      final enc = FfmpegWebmVp9Encoder(
        runner: _writingRunner(commands, payload: [1, 2, 3, 4, 5]),
        scratchDir: tmp,
      );
      const spec = AnimationSpec(format: 'webm', maxBytes: 3);

      final result = await encodeWithinBudget(
        enc,
        [_frame(), _frame()],
        spec,
        qualities: const [300, 200, 100],
      );

      expect(result.withinBudget, isFalse);
      expect(commands, hasLength(3), reason: 'one ffmpeg pass per rung');
      final dirs = commands
          .map((c) => RegExp(r'-i (.+?)[/\\]%d\.png').firstMatch(c)!.group(1))
          .toSet();
      expect(
        dirs,
        hasLength(1),
        reason: 'the PNG sequence is written once and shared by every rung',
      );
      expect(
        tmp.listSync().whereType<Directory>(),
        isEmpty,
        reason: 'scratch dir removed after the search',
      );
    });
  });

  group('isAvailable', () {
    test('true when -encoders lists the codec (cached)', () async {
      var calls = 0;
      final enc = FfmpegWebmVp9Encoder(
        runner: (c) async {
          calls++;
          return const FfmpegRunResult(
            success: true,
            output: 'V..... libvpx-vp9  libvpx VP9 encoder',
          );
        },
        scratchDir: tmp,
      );
      expect(await enc.isAvailable(), isTrue);
      expect(await enc.isAvailable(), isTrue);
      expect(calls, 1, reason: 'the probe result is cached');
    });

    test('false when the codec is missing or the runner throws', () async {
      final missing = FfmpegAnimWebpEncoder(
        runner: (c) async =>
            const FfmpegRunResult(success: true, output: 'libvpx-vp9 only'),
        scratchDir: tmp,
      );
      expect(await missing.isAvailable(), isFalse);

      final broken = FfmpegWebmVp9Encoder(
        runner: (c) async => throw Exception('MissingPluginException'),
        scratchDir: tmp,
      );
      expect(await broken.isAvailable(), isFalse);
    });
  });

  group('encodeWithinBudget', () {
    // FakeAnimationEncoder returns frameCount*quality bytes: 2 frames → 2q.
    test('descends the ladder until the cap is met', () async {
      final fake = FakeAnimationEncoder();
      const spec = AnimationSpec(format: 'webp', maxBytes: 250);
      final result = await encodeWithinBudget(
        fake,
        [_frame(), _frame()],
        spec,
        qualities: const [200, 150, 100], // 400, 300, 200 bytes
      );
      expect(result.withinBudget, isTrue);
      expect(result.quality, 100);
      expect(result.bytes.length, 200);
    });

    test('prepares the frames once while N rungs run', () async {
      final fake = FakeAnimationEncoder();
      const spec = AnimationSpec(format: 'webp', maxBytes: 250);
      final result = await encodeWithinBudget(
        fake,
        [_frame(), _frame()],
        spec,
        qualities: const [200, 150, 100], // 400, 300, 200 bytes → 3 rungs
      );
      expect(result.withinBudget, isTrue);
      expect(
        fake.prepareCalls,
        1,
        reason: 'one prepare for the whole budget search',
      );
      expect(
        fake.sessionEncodeCalls,
        3,
        reason: 'only the codec pass re-runs per rung',
      );
      expect(
        fake.disposeCalls,
        1,
        reason: 'the session is released after the search',
      );
    });

    test(
      'returns best effort flagged out-of-budget when nothing fits',
      () async {
        final fake = FakeAnimationEncoder();
        const spec = AnimationSpec(format: 'webm', maxBytes: 10);
        final result = await encodeWithinBudget(
          fake,
          [_frame(), _frame()],
          spec,
          qualities: const [100, 50],
        );
        expect(result.withinBudget, isFalse);
        expect(result.quality, 50);
        expect(result.bytes.length, 100);
      },
    );

    test('ladder presets are ordered best-first', () {
      final tg = telegramBitrateLadderFor(1);
      expect(tg.first, greaterThan(tg.last));
      expect(
        whatsappQualityLadder.first,
        greaterThan(whatsappQualityLadder.last),
      );
    });

    test('telegram bitrate ladder spends the budget by duration', () {
      // 1 s clip: ~90% of 256 KB as bits/s ≈ 1886 kbps.
      expect(telegramBitrateLadderFor(1).first, closeTo(1886, 5));
      // 3 s clip: a third of that.
      expect(telegramBitrateLadderFor(3).first, closeTo(629, 5));
      // Very short clips clamp at 4000 kbps; very long at the 200 floor.
      expect(telegramBitrateLadderFor(0.2).first, 4000);
      expect(telegramBitrateLadderFor(10).first, greaterThanOrEqualTo(188));
      // Every rung stays positive and descending.
      final ladder = telegramBitrateLadderFor(2);
      for (var i = 1; i < ladder.length; i++) {
        expect(ladder[i], lessThan(ladder[i - 1]));
        expect(ladder[i], greaterThan(0));
      }
    });
  });
}
