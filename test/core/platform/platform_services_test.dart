import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/platform/platform_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PlatformServices.channelName);
  final calls = <MethodCall>[];

  void mock(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return handler(call);
        });
  }

  tearDown(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('openUri passes the uri and returns the platform result', () async {
    mock((call) => true);
    final ok = await PlatformServices(
      channel: channel,
    ).openUri(Uri.parse('tg://resolve?domain=stickers'));
    expect(ok, isTrue);
    expect(calls.single.method, 'openUri');
    expect(
      calls.single.arguments,
      containsPair('uri', 'tg://resolve?domain=stickers'),
    );
  });

  test('saveToDownloads sends name/mime/bytes and returns location', () async {
    mock((call) => 'Downloads/x.webm');
    final loc = await PlatformServices(
      channel: channel,
    ).saveToDownloads('x.webm', 'video/webm', Uint8List.fromList([1, 2]));
    expect(loc, 'Downloads/x.webm');
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['fileName'], 'x.webm');
    expect(args['mimeType'], 'video/webm');
    expect(args['bytes'], [1, 2]);
  });

  test(
    'shareToTelegram walks the client fallbacks until one accepts',
    () async {
      // First client missing (false), second accepts.
      mock(
        (call) =>
            (call.arguments as Map)['package'] == 'org.telegram.messenger.web',
      );
      final ok = await PlatformServices(
        channel: channel,
      ).shareToTelegram(['/tmp/a.webm'], 'video/webm');
      expect(ok, isTrue);
      expect(calls, hasLength(2), reason: 'stopped at the first success');
      expect(
        (calls.last.arguments as Map)['package'],
        'org.telegram.messenger.web',
      );
      expect((calls.first.arguments as Map)['paths'], ['/tmp/a.webm']);
    },
  );

  test('shareToTelegram is false when no client is installed', () async {
    mock((call) => false);
    final ok = await PlatformServices(
      channel: channel,
    ).shareToTelegram(['/tmp/a.webm'], 'video/webm');
    expect(ok, isFalse);
    expect(calls.length, PlatformServices.telegramPackages.length);
  });

  test('platform errors degrade to false / null', () async {
    mock((call) => throw PlatformException(code: 'save_failed'));
    final svc = PlatformServices(channel: channel);
    expect(await svc.openUri(Uri.parse('tg://x')), isFalse);
    expect(await svc.saveToDownloads('a', 'image/gif', Uint8List(1)), isNull);
  });
}
