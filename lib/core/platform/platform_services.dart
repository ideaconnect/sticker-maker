import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
