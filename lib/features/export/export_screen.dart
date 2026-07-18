import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/router.dart';
import '../../core/models/sticker_project.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/checkerboard.dart';
import '../../core/widgets/gradient_button.dart';
import '../../core/widgets/sm_toast.dart';
import '../editor/state/editor_controller.dart';
import '../editor/widgets/sticker_canvas.dart';
import 'animated_export_service.dart';
import 'animation_encoder.dart';
import 'sticker_encoder.dart';

/// Export screen: live preview of the current project, static/animated toggle,
/// target picker, a real size estimate, and export-via-share-sheet (#43/#44).
/// Static PNG/WebP and animated GIF are pure Dart; animated Telegram (.webm
/// VP9+alpha) and WhatsApp (animated .webp) run through the bundled FFmpeg
/// encoders (#69 / ADR 0004).
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  late bool _animated;
  String _target = 'telegram';
  bool _exporting = false;
  String? _sizeLabel;
  String? _sizeFormat; // upper-case format of the last estimate (PNG/WEBM/…)
  bool _initialized = false;

  static const _targets = <_Target>[
    _Target(
      'telegram',
      'Telegram',
      'Static .webp · video sticker (.webm)',
      AppColors.cyan,
      'T',
    ),
    _Target(
      'whatsapp',
      'WhatsApp',
      'Static & animated .webp',
      AppColors.green,
      'W',
    ),
    _Target('png', 'PNG', 'Transparent, 1024px', AppColors.violet, 'P'),
    _Target('webp', 'WebP', 'Transparent, lossless', AppColors.pink, 'WP'),
    _Target(
      'gif',
      'GIF',
      'Animated · Discord, Slack, web',
      AppColors.amber,
      'G',
    ),
  ];

  static const _dims = {
    'telegram': '512 × 512 px',
    'whatsapp': '512 × 512 px',
    'png': '1024 × 1024 px',
    'webp': '512 × 512 px',
    'gif': '512 × 512 px',
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _animated = ref.read(editorControllerProvider).project.isAnimated;
    _updateEstimate();
  }

  /// GIF is its own honest target (Discord/Slack/web) — messengers get the
  /// real sticker formats instead of a flattened GIF.
  bool _useGif(StickerProject project) =>
      project.isAnimated && _target == 'gif';

  /// Messenger targets export true animated stickers when the project is
  /// animated and the Animated mode is on: Telegram → WebM VP9+alpha,
  /// WhatsApp → animated WebP (#69).
  bool _useAnimatedSticker(StickerProject project) =>
      project.isAnimated &&
      _animated &&
      (_target == 'telegram' || _target == 'whatsapp');

  int _pngSize() => _target == 'png' ? 1024 : 512;

  /// Encodes the current selection for the chosen target.
  Future<EncodedSticker> _encode(StickerProject project) {
    if (_useAnimatedSticker(project)) {
      return ref
          .read(animatedExportServiceProvider)
          .encode(
            project,
            _target == 'telegram'
                ? AnimationSpec.telegramWebm
                : AnimationSpec.whatsappWebp,
          );
    }
    if (_useGif(project)) return StickerEncoder.gif(project.frames, fps: 12);
    if (_target == 'whatsapp') {
      // WhatsApp's static cap is 100 KB — downscale WebP to fit.
      return StickerEncoder.webpWithinBudget(
        project.currentFrame,
        maxBytes: 100 * 1024,
      );
    }
    if (_target == 'webp') return StickerEncoder.webp(project.currentFrame);
    return StickerEncoder.png(project.currentFrame, size: _pngSize());
  }

  /// Re-encodes the current selection to show a real size estimate.
  Future<void> _updateEstimate() async {
    setState(() => _sizeLabel = null);
    final project = ref.read(editorControllerProvider).project;
    try {
      final sticker = await _encode(project);
      if (mounted) {
        setState(() {
          _sizeLabel = _formatBytes(sticker.byteLength);
          _sizeFormat = sticker.format.toUpperCase();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _sizeLabel = null);
    }
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final project = ref.read(editorControllerProvider).project;
      final sticker = await _encode(project);
      final dir = await getTemporaryDirectory();
      final name = _sanitize(project.name);
      final file = File(
        '${dir.path}/${name}_${DateTime.now().millisecondsSinceEpoch}.${sticker.format}',
      );
      await file.writeAsBytes(sticker.bytes);
      // WebM is a video container — Telegram's @Stickers needs it sent as a
      // document, which the share sheet handles when the mime says video.
      final mime = sticker.format == 'webm'
          ? 'video/webm'
          : 'image/${sticker.format}';
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: mime)],
          subject: project.name,
          text: 'Made with Sticker Maker',
        ),
      );
      if (mounted) {
        showSmToast(context, 'Shared · ${_formatBytes(sticker.byteLength)}');
      }
    } catch (_) {
      if (mounted) showSmToast(context, "Couldn't export — try again");
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  static String _sanitize(String name) {
    final s = name.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_').trim();
    return s.isEmpty ? 'sticker' : s;
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    return kb < 100 ? '${kb.toStringAsFixed(1)} KB' : '${kb.round()} KB';
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(editorControllerProvider).project;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _topBar(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                children: [
                  _preview(project),
                  const SizedBox(height: 18),
                  if (project.isAnimated) _modeToggle(),
                  if (project.isAnimated) const SizedBox(height: 20),
                  const Text(
                    'SEND TO',
                    style: TextStyle(
                      fontFamily: AppFonts.ui,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final t in _targets) ...[
                    _targetCard(t),
                    const SizedBox(height: 9),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _dims[_target]!,
                        style: const TextStyle(
                          fontFamily: AppFonts.ui,
                          fontSize: 12.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                      Text(
                        _sizeLabel == null
                            ? 'Estimating…'
                            : '~$_sizeLabel · ${_sizeFormat ?? ''}',
                        style: const TextStyle(
                          fontFamily: AppFonts.ui,
                          fontSize: 12.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  if (_target == 'gif') ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Transparent GIFs stay transparent in Discord, Slack and '
                      'browsers. Telegram & WhatsApp chats convert GIFs to '
                      'video — use their sticker targets above instead.',
                      style: TextStyle(
                        fontFamily: AppFonts.ui,
                        fontSize: 11.5,
                        height: 1.45,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  GradientButton(
                    label: _exporting
                        ? 'Sharing…'
                        : 'Share ${_useGif(project) || _useAnimatedSticker(project) ? 'animation' : 'sticker'}',
                    icon: _exporting ? null : Icons.ios_share,
                    busy: _exporting,
                    onPressed: _export,
                    padding: const EdgeInsets.all(16),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(
              Icons.chevron_left,
              size: 26,
              color: AppColors.textSecondary,
            ),
          ),
          const Expanded(
            child: Text(
              'Export sticker',
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontWeight: FontWeight.w600,
                fontSize: 17,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          IconButton(
            onPressed: () => context.goNamed(Routes.home),
            icon: const Icon(Icons.close, size: 22, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _preview(StickerProject project) {
    return Center(
      child: SizedBox(
        width: 170,
        height: 170,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x80000000),
                blurRadius: 40,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const Checkerboard(cell: 11),
                if (project.frames.isNotEmpty)
                  StickerCanvas(frame: project.currentFrame),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _modeTab('Static', Icons.image_outlined, !_animated, () {
              setState(() => _animated = false);
              _updateEstimate();
            }),
          ),
          Expanded(
            child: _modeTab('Animated', Icons.gif_box_outlined, _animated, () {
              setState(() => _animated = true);
              _updateEstimate();
            }),
          ),
        ],
      ),
    );
  }

  Widget _modeTab(
    String label,
    IconData icon,
    bool active,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: active ? AppColors.elevated : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: active ? Colors.white : AppColors.textMuted,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppFonts.ui,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _targetCard(_Target t) {
    final selected = _target == t.id;
    return GestureDetector(
      onTap: () {
        setState(() => _target = t.id);
        _updateEstimate();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? t.color.withValues(alpha: 0.10) : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? t.color.withValues(alpha: 0.6)
                : AppColors.borderFaint,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                t.abbr,
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: t.color,
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.name,
                    style: const TextStyle(
                      fontFamily: AppFonts.ui,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    t.sub,
                    style: const TextStyle(
                      fontFamily: AppFonts.ui,
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? t.color : Colors.transparent,
                border: selected
                    ? null
                    : Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 2,
                      ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Target {
  const _Target(this.id, this.name, this.sub, this.color, this.abbr);
  final String id;
  final String name;
  final String sub;
  final Color color;
  final String abbr;
}
