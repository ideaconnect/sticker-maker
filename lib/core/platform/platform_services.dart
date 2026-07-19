import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Device RAM facts from Android's ActivityManager: total/available bytes and
/// the system's own low-RAM classification (`isLowRamDevice`).
typedef MemoryInfo = ({int totalMem, int availMem, bool lowRam});

/// Small Android platform helpers behind `sticker_maker/platform`:
/// deep-link launching (Telegram's tg:// links) and saving exported stickers
/// into the shared Downloads collection (MediaStore). [channel] is injectable
/// so tests mock the method channel.
class PlatformServices {
  PlatformServices({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'sticker_maker/platform';

  final MethodChannel _channel;

  /// Opens [uri] via an ACTION_VIEW intent (e.g. `tg://resolve?...`).
  /// Returns false when nothing on the device can handle it.
  Future<bool> openUri(Uri uri) async {
    try {
      final ok = await _channel.invokeMethod<bool>('openUri', {
        'uri': uri.toString(),
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Telegram client packages, official first. Tried in order by
  /// [shareToTelegram]; the first installed one gets the share.
  static const telegramPackages = [
    'org.telegram.messenger',
    'org.telegram.messenger.web',
    'org.thunderdog.challegram', // Telegram X
  ];

  /// Shares [paths] DIRECTLY into an app's own share/chat picker, skipping the
  /// system share sheet. Returns false when [packageName] can't handle it.
  Future<bool> shareToApp(
    List<String> paths,
    String mimeType,
    String packageName,
  ) async {
    try {
      final ok = await _channel.invokeMethod<bool>('shareToApp', {
        'paths': paths,
        'mimeType': mimeType,
        'package': packageName,
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens Telegram's chat picker with [paths] attached — the user lands one
  /// tap from Saved Messages (pinned on top) or the @Stickers chat. Falls
  /// through the known Telegram clients; false when none is installed.
  Future<bool> shareToTelegram(List<String> paths, String mimeType) async {
    for (final pkg in telegramPackages) {
      if (await shareToApp(paths, mimeType, pkg)) return true;
    }
    return false;
  }

  /// Device RAM snapshot (ActivityManager.getMemoryInfo + isLowRamDevice).
  /// Returns null when the platform side can't answer — an APK predating the
  /// call, tests without a handler, or a non-Android host — so callers can
  /// choose their own safe default instead of guessing here.
  Future<MemoryInfo?> memoryInfo() async {
    try {
      final map = await _channel.invokeMapMethod<String, Object?>(
        'getMemoryInfo',
      );
      final total = map?['totalMem'];
      final avail = map?['availMem'];
      final lowRam = map?['lowRam'];
      if (total is! int || avail is! int || lowRam is! bool) return null;
      return (totalMem: total, availMem: avail, lowRam: lowRam);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Saves [bytes] as [fileName] into the device's Downloads. Returns the
  /// user-visible location (e.g. `Downloads/sticker.webm`), or null on failure.
  Future<String?> saveToDownloads(
    String fileName,
    String mimeType,
    Uint8List bytes,
  ) async {
    try {
      return await _channel.invokeMethod<String>('saveToDownloads', {
        'fileName': fileName,
        'mimeType': mimeType,
        'bytes': bytes,
      });
    } on PlatformException {
      return null;
    }
  }
}

final platformServicesProvider = Provider<PlatformServices>(
  (ref) => PlatformServices(),
);
