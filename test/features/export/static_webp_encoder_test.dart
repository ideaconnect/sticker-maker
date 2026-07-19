import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/features/export/ffmpeg_animation_encoder.dart';
import 'package:sticker_maker/features/export/static_webp_encoder.dart';

import 'webp_fixtures.dart';

/// Realistic `-encoders` probe output: both WebP encoders present.
const _encodersWithLibwebp =
    ' V....D libwebp              libwebp WebP image (codec webp)\n'
    ' V....D libwebp_anim         libwebp WebP image (codec webp)\n';

/// Only the animated encoder — a plain `contains('libwebp')` probe would
/// false-positive on this (both the name prefix and the description match).
const _encodersAnimOnly =
    ' V....D libwebp_anim         libwebp WebP image (codec webp)\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sm_swebp_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('FfmpegStaticWebpEncoder', () {
    test('command: single-image libwebp encode, lossy, quality knob', () {
      final enc = FfmpegStaticWebpEncoder(
        runner: (c) async => const FfmpegRunResult(success: true, output: ''),
        scratchDir: tmp,
      );
      final cmd = enc.buildCommand('/a/in.png', '/a/out.webp', quality: 80);
      expect(cmd, contains('-i /a/in.png'));
      expect(cmd, contains('-c:v libwebp '));
      expect(cmd, isNot(contains('libwebp_anim')));
      expect(cmd, contains('-lossless 0'), reason: 'lossy is the whole point');
      expect(cmd, contains('-q:v 80'));
      expect(cmd, endsWith('/a/out.webp'));
    });

    test(
      'encodePng writes the input, runs ffmpeg, returns the bytes',
      () async {
        final commands = <String>[];
        final enc = FfmpegStaticWebpEncoder(
          runner: (command) async {
            commands.add(command);
            final outPath = command.split(' ').last;
            File(outPath).writeAsBytesSync(const [9, 9, 9, 9]);
            return const FfmpegRunResult(success: true, output: '');
          },
          scratchDir: tmp,
        );
        final bytes = await enc.encodePng(
          Uint8List.fromList(const [1, 2, 3]),
          quality: 70,
        );
        expect(bytes, [9, 9, 9, 9]);
        expect(commands.single, contains('-q:v 70'));
        expect(
          tmp.listSync().whereType<Directory>(),
          isEmpty,
          reason: 'scratch dir removed after encode',
        );
      },
    );

    test('a failed session surfaces as a StateError with the log tail', () {
      final enc = FfmpegStaticWebpEncoder(
        runner: (c) async =>
            const FfmpegRunResult(success: false, output: 'boom: no libwebp'),
        scratchDir: tmp,
      );
      expect(
        enc.encodePng(Uint8List(4), quality: 70),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('boom'),
          ),
        ),
      );
    });

    group('isAvailable', () {
      test('true when -encoders lists libwebp (cached)', () async {
        var calls = 0;
        final enc = FfmpegStaticWebpEncoder(
          runner: (c) async {
            calls++;
            return const FfmpegRunResult(
              success: true,
              output: _encodersWithLibwebp,
            );
          },
          scratchDir: tmp,
        );
        expect(await enc.isAvailable(), isTrue);
        expect(await enc.isAvailable(), isTrue);
        expect(calls, 1, reason: 'the probe result is cached');
      });

      test('false when only libwebp_anim is present', () async {
        final enc = FfmpegStaticWebpEncoder(
          runner: (c) async =>
              const FfmpegRunResult(success: true, output: _encodersAnimOnly),
          scratchDir: tmp,
        );
        expect(await enc.isAvailable(), isFalse);
      });

      test('false when the runner throws', () async {
        final enc = FfmpegStaticWebpEncoder(
          runner: (c) async => throw Exception('MissingPluginException'),
          scratchDir: tmp,
        );
        expect(await enc.isAvailable(), isFalse);
      });
    });
  });

  group('StaticWebpBudgetEncoder', () {
    const trivialFrame = Frame(
      id: 'f',
      layers: [TextLayer(id: 't', name: 'W', text: 'W', fontFamily: 'Rubik')],
    );

    test('lossless fast path: a simple sticker never touches lossy', () async {
      final fake = FakeStaticWebpEncoder();
      final sticker = await StaticWebpBudgetEncoder(
        lossy: fake,
      ).encode(trivialFrame);
      expect(sticker.size, 512);
      expect(sticker.format, 'webp');
      expect(
        sticker.byteLength,
        lessThanOrEqualTo(StaticWebpBudgetEncoder.whatsappMaxBytes),
      );
      expect(fake.calls, isEmpty, reason: 'lossless already fits');
    });

    test('photo noise: lossless overshoots, the ladder walks best-first at a '
        'fixed 512 px (never downscales)', () async {
      final noisy = writeNoisyPng(tmp);
      // Oversized until quality 60 — forces a real descent.
      final fake = FakeStaticWebpEncoder(
        bytesFor: (q) => Uint8List(q >= 70 ? 200 * 1024 : 60 * 1024),
      );
      final sticker = await StaticWebpBudgetEncoder(
        lossy: fake,
      ).encode(noisyFrame('n', noisy.path), stickerName: 'n');
      expect(fake.calls, [90, 80, 70, 60]);
      expect(
        sticker.size,
        512,
        reason:
            'WhatsApp requires exactly 512×512 — quality is the only '
            'budget knob',
      );
      expect(sticker.byteLength, 60 * 1024);
      // The lossy encoder received the full-resolution 512² render.
      final png = img.decodePng(fake.lastPngBytes!)!;
      expect([png.width, png.height], [512, 512]);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'throws a StateError naming the sticker when even quality 30 overshoots',
      () async {
        final noisy = writeNoisyPng(tmp);
        final fake = FakeStaticWebpEncoder(
          bytesFor: (q) => Uint8List(500 * 1024),
        );
        await expectLater(
          StaticWebpBudgetEncoder(
            lossy: fake,
          ).encode(noisyFrame('n', noisy.path), stickerName: 'Beach Photo'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Beach Photo'),
            ),
          ),
        );
        expect(fake.calls, StaticWebpBudgetEncoder.qualityLadder);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'throws when lossless overshoots and lossy is unavailable',
      () async {
        final noisy = writeNoisyPng(tmp);
        final fake = FakeStaticWebpEncoder(available: false);
        await expectLater(
          StaticWebpBudgetEncoder(
            lossy: fake,
          ).encode(noisyFrame('n', noisy.path), stickerName: 'n'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('unavailable'),
            ),
          ),
        );
        expect(fake.calls, isEmpty);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
