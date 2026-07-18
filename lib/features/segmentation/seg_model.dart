import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_store.dart';

/// The background-removal model the user prefers, surfaced in the Cut out tool's
/// "AI Model" picker. Each option maps to a [SegmentationEngine.id] so the
/// registry can run the chosen engine first and fall back to the other.
///
/// Kept as data (label/tagline/blurb) so the picker and the info sheet render
/// straight from the enum — the same pattern as `EditorTool`.
enum SegModel {
  /// The platform's built-in AI — ML Kit Subject Segmentation on Android.
  builtin(
    id: 'builtin',
    engineId: 'mlkit',
    label: 'Built-in AI',
    tagline: 'On-device · fast & private',
    blurb:
        'Runs on-device for fast, private cut-outs. Great for pets and people '
        'with clear edges — nothing leaves your phone.',
  ),

  /// The bundled open-source U²-Netp model (#28), shipped inside the app.
  u2net(
    id: 'u2net',
    engineId: 'bundled',
    label: 'U²-Net',
    tagline: 'Open-source · sharper detail',
    blurb:
        'An open-source salient-object model bundled with the app. Works fully '
        'offline and is often sharper on fine detail like fur, hair and '
        'whiskers — a little slower to run.',
  );

  const SegModel({
    required this.id,
    required this.engineId,
    required this.label,
    required this.tagline,
    required this.blurb,
  });

  /// Stable key persisted in settings (matches the design's model ids).
  final String id;

  /// The [SegmentationEngine.id] this preference selects.
  final String engineId;

  /// Short name shown in the picker row and in the "removed" toast.
  final String label;

  /// One-line descriptor under the name in the picker.
  final String tagline;

  /// Longer explanation shown in the "Which AI model?" info sheet.
  final String blurb;

  /// Resolves a persisted [id] back to a model, defaulting to [builtin]
  /// (the design's default) for a null/unknown value.
  static SegModel fromId(String? id) {
    for (final m in values) {
      if (m.id == id) return m;
    }
    return builtin;
  }

  /// The model an [engineId] corresponds to, or null if it isn't one we expose
  /// (used to label which engine actually produced a result).
  static SegModel? fromEngineId(String engineId) {
    for (final m in values) {
      if (m.engineId == engineId) return m;
    }
    return null;
  }
}

/// Loads the persisted [SegModel] preference and writes changes back through
/// [SettingsStore]. The UI watches this; `_removeBackground` reads it to pick
/// the preferred engine.
class SegModelController extends AsyncNotifier<SegModel> {
  @override
  Future<SegModel> build() async => SegModel.fromId(
    await ref.read(settingsStoreProvider).segmentationModelId(),
  );

  /// Selects [model] optimistically (so the picker updates immediately) and
  /// persists it.
  Future<void> select(SegModel model) async {
    state = AsyncData(model);
    await ref.read(settingsStoreProvider).setSegmentationModelId(model.id);
  }
}

final segModelProvider = AsyncNotifierProvider<SegModelController, SegModel>(
  SegModelController.new,
);
