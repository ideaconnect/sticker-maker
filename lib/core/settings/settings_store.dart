import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Tiny key/value app settings, persisted as a single `settings.json` under the
/// app documents directory. Currently just the first-run flag; kept generic so
/// future preferences (default export target, etc.) slot in without a new file.
/// Pass [baseDir] in tests to use a temp directory.
class SettingsStore {
  SettingsStore({Directory? baseDir}) : _baseOverride = baseDir;

  final Directory? _baseOverride;

  static const _fileName = 'settings.json';
  static const _kOnboardingSeen = 'onboardingSeen';
  static const _kSegModel = 'segmentationModel';

  Future<File> _file() async {
    final base = _baseOverride ?? await getApplicationDocumentsDirectory();
    return File('${base.path}/$_fileName');
  }

  Future<Map<String, dynamic>> _read() async {
    final file = await _file();
    if (!file.existsSync()) return {};
    try {
      return (jsonDecode(await file.readAsString()) as Map)
          .cast<String, dynamic>();
    } catch (_) {
      // A corrupt settings file should never brick the app — treat as empty.
      return {};
    }
  }

  Future<void> _write(Map<String, dynamic> data) async {
    await (await _file()).writeAsString(jsonEncode(data));
  }

  /// Whether the first-run intro has been completed (or skipped).
  Future<bool> onboardingSeen() async =>
      (await _read())[_kOnboardingSeen] == true;

  Future<void> setOnboardingSeen(bool value) async {
    final data = await _read();
    data[_kOnboardingSeen] = value;
    await _write(data);
  }

  /// The user's preferred background-removal model id (see `SegModel`), or null
  /// when unset — the segmentation layer maps that to its default. Stored as a
  /// bare string so this core layer stays free of any feature dependency.
  Future<String?> segmentationModelId() async =>
      (await _read())[_kSegModel] as String?;

  Future<void> setSegmentationModelId(String id) async {
    final data = await _read();
    data[_kSegModel] = id;
    await _write(data);
  }
}

final settingsStoreProvider = Provider<SettingsStore>((ref) => SettingsStore());

/// Resolves to whether onboarding is done. The app shell watches this to pick
/// its start route; invalidate it after completing onboarding.
final onboardingSeenProvider = FutureProvider<bool>(
  (ref) => ref.read(settingsStoreProvider).onboardingSeen(),
);
