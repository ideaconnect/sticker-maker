import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/router.dart';
import '../../core/models/sticker_project.dart';
import '../../core/platform/platform_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/checkerboard.dart';
import '../../core/widgets/gradient_button.dart';
import '../../core/widgets/sm_toast.dart';
import '../editor/state/editor_controller.dart';
import '../editor/widgets/sticker_canvas.dart';
import '../home/project_repository.dart';
import '../packs/pack_dialogs.dart';
import '../packs/pack_repository.dart';
import '../packs/sticker_pack.dart';
import 'animated_export_service.dart';
import 'animation_encoder.dart';
import 'static_webp_encoder.dart';
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

  /// Monotonic id of the latest estimate request. Estimates can interleave
  /// (encodes take seconds); only the request that still owns this generation
  /// may write the label, so a slow stale encode never clobbers a fresh one.
  int _estimateGen = 0;

  /// Last successful encode, keyed by (target, Static/Animated toggle, project
  /// revision). The size estimate already paid for a full encode — export and
  /// download reuse those bytes instead of encoding the same thing again.
  ({(String, bool, DateTime?) key, EncodedSticker sticker})? _lastEncode;

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

  /// Messenger targets export true animated stickers: Telegram → WebM
  /// VP9+alpha (when the Animated mode is on), WhatsApp → animated WebP (#69).
  /// WhatsApp ignores the Static/Animated toggle: packs are typed by the
  /// project itself (all-static or all-animated, see StickerPack), so an
  /// animated project always ships animated there — the toggle is hidden too.
  bool _useAnimatedSticker(StickerProject project) =>
      project.isAnimated &&
      (_target == 'whatsapp' || (_animated && _target == 'telegram'));

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
      // WhatsApp's static cap is 100 KB at *exactly* 512×512 — fit it via the
      // lossy quality ladder, never by downscaling (WhatsApp rejects any
      // non-512 sticker).
      return ref
          .read(staticWebpBudgetEncoderProvider)
          .encode(project.currentFrame, stickerName: project.name);
    }
    if (_target == 'webp') return StickerEncoder.webp(project.currentFrame);
    return StickerEncoder.png(project.currentFrame, size: _pngSize());
  }

  /// Cache key for one encoded result. [_encode] is deterministic for a given
  /// target + Static/Animated toggle + project revision (updatedAt is bumped on
  /// every save), so a matching key means the bytes are still valid.
  (String, bool, DateTime?) _encodeKey(StickerProject project) =>
      (_target, _animated, project.updatedAt);

  /// [_encode] with a single-entry result cache: when the key still matches
  /// (same target/toggle/revision) the previous bytes are reused, so the
  /// export/download tap doesn't re-pay for the encode the estimate already
  /// ran. The key is captured before the await — [_encode] reads the target
  /// state synchronously, so the result belongs to the captured key even if
  /// the user switches targets mid-encode.
  Future<EncodedSticker> _encodeCached(StickerProject project) async {
    final key = _encodeKey(project);
    final cached = _lastEncode;
    if (cached != null && cached.key == key) return cached.sticker;
    final sticker = await _encode(project);
    _lastEncode = (key: key, sticker: sticker);
    return sticker;
  }

  /// Encodes the current selection to show a real size estimate (the result is
  /// cached and reused by the actual export). Guarded by [_estimateGen]: on
  /// BOTH the success and the failure path a stale completion is discarded —
  /// a stale error resetting the label would otherwise pin "Estimating…" over
  /// a fresh result.
  Future<void> _updateEstimate() async {
    final gen = ++_estimateGen;
    setState(() => _sizeLabel = null);
    final project = ref.read(editorControllerProvider).project;
    try {
      final sticker = await _encodeCached(project);
      if (!mounted || gen != _estimateGen) return;
      setState(() {
        _sizeLabel = _formatBytes(sticker.byteLength);
        _sizeFormat = sticker.format.toUpperCase();
      });
    } catch (_) {
      if (!mounted || gen != _estimateGen) return;
      setState(() => _sizeLabel = null);
    }
  }

  Future<void> _export() async {
    if (_exporting) return;
    // WhatsApp has no single-file sticker hand-off (unlike Telegram's
    // @Stickers): the OS only serves stickers from an installed *pack of 3+*.
    // So "Add to WhatsApp" routes through the pack builder instead of a share.
    if (_target == 'whatsapp') {
      await _addToWhatsAppPack();
      return;
    }
    setState(() => _exporting = true);
    try {
      final project = ref.read(editorControllerProvider).project;
      final sticker = await _encodeCached(project);
      final dir = await getTemporaryDirectory();
      final name = _sanitize(project.name);
      final file = File(
        '${dir.path}/${name}_${DateTime.now().millisecondsSinceEpoch}.${sticker.format}',
      );
      await file.writeAsBytes(sticker.bytes);
      final mime = sticker.format == 'webm'
          ? 'video/webm'
          : 'image/${sticker.format}';
      if (sticker.format == 'webm') {
        // Explain the sticker steps FIRST — once Telegram takes over the
        // screen the user can't read them. Only proceed on "I understand".
        if (mounted) setState(() => _exporting = false);
        final proceed = mounted && await _showTelegramStickerGuide() == true;
        if (!proceed) return;

        // Hand the .webm straight to Telegram's chat picker (Saved Messages is
        // pinned there; the @Stickers chat works directly too), skipping the
        // system share sheet.
        //
        // Crucially the mime is a generic FILE type, not video/webm: Telegram
        // routes video/* through its video flow (compression, video player),
        // which @Stickers rejects — as a document it arrives exactly the way
        // the bot requires (STICKER_VIDEO_NODOC otherwise).
        const docMime = 'application/octet-stream';
        final sent = await ref.read(platformServicesProvider).shareToTelegram([
          file.path,
        ], docMime);
        if (!sent && mounted) {
          // No Telegram installed — regular share sheet as fallback.
          await SharePlus.instance.share(
            ShareParams(
              files: [XFile(file.path, mimeType: docMime)],
              subject: project.name,
            ),
          );
        }
      } else {
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
      }
    } catch (_) {
      if (mounted) showSmToast(context, "Couldn't export — try again");
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Encodes the current selection and saves it straight into Downloads.
  Future<void> _download() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final project = ref.read(editorControllerProvider).project;
      final sticker = await _encodeCached(project);
      final name =
          '${_sanitize(project.name)}_${DateTime.now().millisecondsSinceEpoch}'
          '.${sticker.format}';
      final mime = sticker.format == 'webm'
          ? 'video/webm'
          : 'image/${sticker.format}';
      final location = await ref
          .read(platformServicesProvider)
          .saveToDownloads(name, mime, sticker.bytes);
      if (mounted) {
        showSmToast(
          context,
          location == null ? "Couldn't save the file" : 'Saved to $location',
        );
      }
    } catch (_) {
      if (mounted) showSmToast(context, "Couldn't export — try again");
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Sentinel returned by [_showWhatsAppPackSheet] for "create a new pack".
  static const _newPackChoice = '__new_pack__';

  /// WhatsApp only serves stickers from an installed *pack of at least 3*, so a
  /// lone sticker can't cross over like Telegram's single-file @Stickers flow.
  /// Instead we persist this design and let the user drop it into a new or
  /// existing pack, then finish in the pack screen where "Add to WhatsApp"
  /// installs the whole pack via the ContentProvider (#46).
  Future<void> _addToWhatsAppPack() async {
    setState(() => _exporting = true);
    try {
      final project = ref.read(editorControllerProvider).project;
      // Persist so the pack can reference it by id. The editor auto-saves on a
      // debounce; force it now so a just-made design is definitely on disk.
      await ref
          .read(projectRepositoryProvider)
          .save(project.copyWith(updatedAt: DateTime.now()));
      if (!mounted) return;
      ref.invalidate(savedProjectsProvider);

      final packs = await ref.read(packRepositoryProvider).list();
      if (!mounted) return;
      // A pack is all-static or all-animated; only a same-type (or still-empty)
      // pack can take this sticker — and never one that already contains it
      // (withSticker would silently no-op, mirroring pack detail's picker).
      final compatible = packs
          .where(
            (p) =>
                !p.stickers.any((s) => s.projectId == project.id) &&
                (p.isEmpty || p.animated == project.isAnimated),
          )
          .toList();

      final choice = await _showWhatsAppPackSheet(compatible);
      if (choice == null || !mounted) return;

      final StickerPack base;
      if (choice == _newPackChoice) {
        final name = await promptPackName(context);
        if (name == null || !mounted) return;
        base = StickerPack(
          id: 'pack_${DateTime.now().microsecondsSinceEpoch}',
          name: name,
          animated: project.isAnimated,
        );
      } else {
        base = choice as StickerPack;
      }

      // withSticker is a no-op if this project is already in the pack.
      var next = base.withSticker(
        PackSticker(
          id: 'ps_${DateTime.now().microsecondsSinceEpoch}',
          projectId: project.id,
        ),
      );
      // An empty pack inherits its static/animated type from its first sticker.
      if (base.isEmpty) next = next.copyWith(animated: project.isAnimated);
      await ref.read(packRepositoryProvider).save(next);
      if (!mounted) return;
      ref.invalidate(savedPacksProvider);

      // Land in the pack: the compliance banner shows how many more stickers
      // WhatsApp needs, and "Add to WhatsApp" installs the finished pack.
      unawaited(
        context.pushNamed(Routes.packDetail, pathParameters: {'id': next.id}),
      );
    } catch (_) {
      if (mounted) showSmToast(context, "Couldn't open the pack — try again");
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Lets the user start a new WhatsApp pack from this sticker, or drop it into
  /// a compatible existing one. Returns [_newPackChoice], the chosen
  /// [StickerPack], or null when dismissed.
  Future<Object?> _showWhatsAppPackSheet(List<StickerPack> compatible) {
    return showModalBottomSheet<Object>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const Text(
                'Add to a WhatsApp pack',
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                  color: AppColors.green,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'WhatsApp only shows stickers that belong to a pack of at '
                'least 3. Create a pack or add this sticker to one, then send '
                'the whole pack to WhatsApp.',
                style: TextStyle(
                  fontFamily: AppFonts.ui,
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              GradientButton(
                label: 'New pack with this sticker',
                icon: Icons.add,
                glowColor: AppColors.green,
                onPressed: () => Navigator.of(ctx).pop(_newPackChoice),
              ),
              if (compatible.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'OR ADD TO',
                  style: TextStyle(
                    fontFamily: AppFonts.ui,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 10),
                for (final p in compatible) ...[
                  _packChoiceRow(ctx, p),
                  const SizedBox(height: 9),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _packChoiceRow(BuildContext ctx, StickerPack pack) {
    return GestureDetector(
      onTap: () => Navigator.of(ctx).pop(pack),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.cardAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderFaint),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                pack.animated
                    ? Icons.gif_box_outlined
                    : Icons.grid_view_rounded,
                size: 19,
                color: AppColors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pack.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.ui,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${pack.count} / 30 · ${pack.animated ? 'Animated' : 'Static'}',
                    style: const TextStyle(
                      fontFamily: AppFonts.ui,
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.add_circle_outline,
              size: 20,
              color: AppColors.green,
            ),
          ],
        ),
      ),
    );
  }

  /// Shown BEFORE handing the .webm to Telegram, so the user knows the steps
  /// before Telegram takes over the screen. Returns true when they tap
  /// "I understand" (proceed to share), null/false when dismissed. Turning the
  /// exported .webm into a real sticker goes through @Stickers (`/newvideo`) —
  /// Telegram has no API to create packs directly from an app.
  Future<bool?> _showTelegramStickerGuide() {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const Text(
                'Make it a Telegram sticker',
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                  color: AppColors.cyan,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Next, Telegram will open with your sticker attached as a '
                "file. Here's how to turn it into a sticker:\n\n"
                '1. Send it to Saved Messages (top of the list)\n'
                '   (Ignore the lower quality in Saved Messages — it will '
                'look good as a sticker!)\n'
                '2. Open the @Stickers bot\n'
                '3. Send /newvideo and a pack title\n'
                '4. Forward your sticker file from Saved Messages\n'
                '5. Pick an emoji, then /publish',
                style: TextStyle(
                  fontFamily: AppFonts.ui,
                  fontSize: 13,
                  height: 1.6,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              GradientButton(
                label: 'I understand',
                icon: Icons.check_rounded,
                glowColor: AppColors.cyan,
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
            ],
          ),
        ),
      ),
    );
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
                  // No Static/Animated choice for WhatsApp — the pack flow
                  // types the sticker by the project (see _useAnimatedSticker).
                  if (project.isAnimated && _target != 'whatsapp') ...[
                    _modeToggle(),
                    const SizedBox(height: 20),
                  ],
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
                        ? 'Working…'
                        : _target == 'whatsapp'
                        ? 'Add to WhatsApp'
                        : 'Share ${_useGif(project) || _useAnimatedSticker(project) ? 'animation' : 'sticker'}',
                    icon: _exporting
                        ? null
                        : _target == 'whatsapp'
                        ? Icons.add_circle_outline
                        : Icons.ios_share,
                    busy: _exporting,
                    onPressed: _export,
                    padding: const EdgeInsets.all(16),
                  ),
                  const SizedBox(height: 10),
                  GradientButton(
                    label: 'Download',
                    icon: Icons.download_outlined,
                    solidColor: AppColors.neutralButton,
                    foreground: AppColors.textSecondary,
                    onPressed: _exporting ? null : _download,
                    padding: const EdgeInsets.all(15),
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
