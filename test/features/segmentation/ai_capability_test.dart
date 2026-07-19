import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/platform/platform_services.dart';
import 'package:sticker_maker/features/segmentation/ai_capability.dart';

const _gib = 1024 * 1024 * 1024;

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

  ProviderContainer containerWithChannel() {
    final container = ProviderContainer(
      overrides: [
        platformServicesProvider.overrideWithValue(
          PlatformServices(channel: channel),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('isLowRamDevice denies the SAM tier even with plenty of RAM', () async {
    mock(
      (call) => {'totalMem': 8 * _gib, 'availMem': 4 * _gib, 'lowRam': true},
    );
    final cap = await containerWithChannel().read(aiCapabilityProvider.future);
    expect(cap.samAllowed, isFalse);
    expect(cap.reason, isNotNull);
  });

  test('under 3 GiB total RAM denies the SAM tier', () async {
    mock(
      (call) => {'totalMem': 2 * _gib, 'availMem': 1 * _gib, 'lowRam': false},
    );
    final cap = await containerWithChannel().read(aiCapabilityProvider.future);
    expect(cap.samAllowed, isFalse);
    expect(cap.reason, contains('GiB'));
  });

  test('a healthy device is allowed', () async {
    mock(
      (call) => {'totalMem': 4 * _gib, 'availMem': 2 * _gib, 'lowRam': false},
    );
    final cap = await containerWithChannel().read(aiCapabilityProvider.future);
    expect(cap.samAllowed, isTrue);
    expect(cap.reason, isNull);
  });

  test('a throwing channel (old APK) defaults to allowed — no device that '
      'works today regresses', () async {
    mock((call) => throw PlatformException(code: 'memory_info_failed'));
    final cap = await containerWithChannel().read(aiCapabilityProvider.future);
    expect(cap.samAllowed, isTrue);
  });

  test('a missing handler (non-Android / tests) defaults to allowed', () async {
    // No mock installed: MethodChannel throws MissingPluginException.
    final cap = await containerWithChannel().read(aiCapabilityProvider.future);
    expect(cap.samAllowed, isTrue);
  });

  test('a malformed platform reply defaults to allowed', () async {
    mock((call) => {'totalMem': 'lots', 'lowRam': 'nope'});
    final cap = await containerWithChannel().read(aiCapabilityProvider.future);
    expect(cap.samAllowed, isTrue);
  });

  test('the probe is memoized — one channel call per app run', () async {
    mock(
      (call) => {'totalMem': 4 * _gib, 'availMem': 2 * _gib, 'lowRam': false},
    );
    final container = containerWithChannel();
    await container.read(aiCapabilityProvider.future);
    await container.read(aiCapabilityProvider.future);
    expect(calls, hasLength(1));
  });
}
