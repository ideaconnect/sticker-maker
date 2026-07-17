import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';

/// Imports photos into the app: picks from the gallery or camera (downscaled to
/// keep memory in check) and copies the result into the app's project assets so
/// the [ImageLayer.assetPath] stays valid across launches.
class ImageImportService {
  ImageImportService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  static const double _maxDimension = 2048;
  static const int _quality = 92;

  /// Returns the stored asset path, or null if the user cancelled.
  Future<String?> pickFromGallery() => _pickAndStore(ImageSource.gallery);

  Future<String?> pickFromCamera() => _pickAndStore(ImageSource.camera);

  Future<String?> _pickAndStore(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: _maxDimension,
      maxHeight: _maxDimension,
      imageQuality: _quality,
      requestFullMetadata: false,
    );
    if (picked == null) return null;
    return storeXFile(picked);
  }

  /// Pastes an image from the system clipboard, if any. Returns the stored asset
  /// path, or null when the clipboard holds no image.
  Future<String?> pasteFromClipboard() async {
    final bytes = await Pasteboard.image;
    if (bytes == null) return null;
    return storeBytes(bytes);
  }

  /// Copies [file] into the project assets directory and returns the new path.
  /// Exposed for testing with a synthetic [XFile].
  Future<String> storeXFile(XFile file) async {
    final assets = await _assetsDir();
    final ext = file.name.contains('.') ? file.name.split('.').last : 'png';
    final dest = '${assets.path}/img_${_stamp()}.$ext';
    await File(file.path).copy(dest);
    return dest;
  }

  /// Writes raw image [bytes] into the project assets directory.
  Future<String> storeBytes(Uint8List bytes, {String ext = 'png'}) async {
    final assets = await _assetsDir();
    final dest = '${assets.path}/img_${_stamp()}.$ext';
    await File(dest).writeAsBytes(bytes);
    return dest;
  }

  Future<Directory> _assetsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final assets = Directory('${base.path}/projects/assets');
    if (!assets.existsSync()) await assets.create(recursive: true);
    return assets;
  }

  int _stamp() => DateTime.now().microsecondsSinceEpoch;
}

final imageImportServiceProvider = Provider<ImageImportService>(
  (ref) => ImageImportService(),
);
