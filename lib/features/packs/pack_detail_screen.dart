import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/sticker_project.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/checkerboard.dart';
import '../../core/widgets/gradient_button.dart';
import '../../core/widgets/sm_toast.dart';
import '../editor/widgets/sticker_canvas.dart';
import '../export/compliance_validator.dart';
import '../home/project_repository.dart';
import 'pack_dialogs.dart';
import 'pack_repository.dart';
import 'sticker_pack.dart';
import 'telegram_pack_share.dart';
import 'whatsapp_pack_installer.dart';

/// Edits one sticker pack: add saved stickers, reorder, delete, tag emoji, all
/// with live WhatsApp compliance feedback. Every change is persisted
/// immediately (there is no explicit "save"). Reached via `/pack/:id`.
class PackDetailScreen extends ConsumerStatefulWidget {
  const PackDetailScreen({required this.packId, super.key});

  final String packId;

  @override
  ConsumerState<PackDetailScreen> createState() => _PackDetailScreenState();
}

class _PackDetailScreenState extends ConsumerState<PackDetailScreen> {
  StickerPack? _pack;
  bool _loading = true;
  bool _addingToWhatsApp = false;
  bool _addingToTelegram = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pack = await ref.read(packRepositoryProvider).load(widget.packId);
    if (!mounted) return;
    setState(() {
      _pack = pack;
      _loading = false;
    });
  }

  /// Applies [next], persists it, and refreshes the packs list.
  Future<void> _mutate(StickerPack next) async {
    setState(() => _pack = next);
    await ref.read(packRepositoryProvider).save(next);
    ref.invalidate(savedPacksProvider);
  }

  Future<void> _rename() async {
    final pack = _pack;
    if (pack == null) return;
    final name = await promptPackName(context, initial: pack.name);
    if (name == null) return;
    await _mutate(pack.copyWith(name: name));
  }

  Future<void> _addStickers() async {
    final pack = _pack;
    if (pack == null) return;
    final projects = await ref.read(savedProjectsProvider.future);
    if (!mounted) return;
    final inPack = pack.stickers.map((s) => s.projectId).toSet();
    // Once a pack has a type, only same-type projects can join (no mixing).
    final choices = projects.where((p) {
      if (inPack.contains(p.id)) return false;
      if (pack.isEmpty) return true;
      return p.isAnimated == pack.animated;
    }).toList();

    final picked = await showModalBottomSheet<StickerProject>(
      context: context,
      backgroundColor: AppColors.panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddStickerSheet(
        choices: choices,
        packHasType: !pack.isEmpty,
        animated: pack.animated,
      ),
    );
    if (picked == null) return;

    final sticker = PackSticker(
      id: 'ps_${DateTime.now().microsecondsSinceEpoch}',
      projectId: picked.id,
    );
    var next = pack.withSticker(sticker);
    // The first sticker fixes the pack's static/animated type.
    if (pack.isEmpty) next = next.copyWith(animated: picked.isAnimated);
    await _mutate(next);
  }

  Future<void> _editEmojis(PackSticker sticker) async {
    final pack = _pack;
    if (pack == null) return;
    final tags = await promptEmojis(context, initial: sticker.emojis);
    if (tags == null) return;
    await _mutate(pack.setEmojis(sticker.id, tags));
  }

  void _reorder(int oldIndex, int newIndex) {
    final pack = _pack;
    if (pack == null) return;
    // onReorderItem already adjusts newIndex for the removed item, matching
    // StickerPack.reorder (which removes then inserts at newIndex).
    _mutate(pack.reorder(oldIndex, newIndex));
  }

  Future<void> _deletePack() async {
    final pack = _pack;
    if (pack == null) return;
    final ok = await _confirm(
      context,
      title: 'Delete "${pack.name}"?',
      confirmLabel: 'Delete',
    );
    if (ok != true) return;
    await ref.read(packRepositoryProvider).delete(pack.id);
    ref.invalidate(savedPacksProvider);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final pack = _pack;
    if (pack == null) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _topBar(context, ''),
              const Expanded(
                child: Center(
                  child: Text(
                    'This pack no longer exists.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final projectsAsync = ref.watch(savedProjectsProvider);
    final byId = <String, StickerProject>{
      for (final p in projectsAsync.asData?.value ?? const <StickerProject>[])
        p.id: p,
    };
    final issues = pack.validate();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _topBar(context, pack.name),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  _MetaRow(pack: pack),
                  const SizedBox(height: 14),
                  _ComplianceBanner(issues: issues, count: pack.count),
                  const SizedBox(height: 16),
                  _AddStickerButton(onTap: _addStickers),
                  const SizedBox(height: 14),
                  if (pack.isEmpty)
                    const _EmptyPack()
                  else
                    ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      onReorderItem: _reorder,
                      children: [
                        for (var i = 0; i < pack.stickers.length; i++)
                          _StickerRow(
                            key: ValueKey(pack.stickers[i].id),
                            index: i,
                            sticker: pack.stickers[i],
                            project: byId[pack.stickers[i].projectId],
                            onEditEmojis: () => _editEmojis(pack.stickers[i]),
                            onDelete: () => _mutate(
                              pack.withoutSticker(pack.stickers[i].id),
                            ),
                          ),
                      ],
                    ),
                  if (!pack.isEmpty &&
                      issues.every(
                        (i) => i.severity != IssueSeverity.error,
                      )) ...[
                    const SizedBox(height: 20),
                    GradientButton(
                      label: 'Add to WhatsApp',
                      icon: Icons.add_circle_outline,
                      busy: _addingToWhatsApp,
                      onPressed: () => _addToWhatsApp(pack),
                      padding: const EdgeInsets.all(15),
                    ),
                    const SizedBox(height: 10),
                    GradientButton(
                      label: 'Add to Telegram',
                      icon: Icons.send,
                      busy: _addingToTelegram,
                      onPressed: () => _addToTelegram(pack),
                      padding: const EdgeInsets.all(15),
                      solidColor: const Color(0xFF229ED9), // Telegram blue
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addToWhatsApp(StickerPack pack) async {
    if (_addingToWhatsApp) return;
    setState(() => _addingToWhatsApp = true);
    try {
      final installer = ref.read(whatsAppPackInstallerProvider);
      if (!await installer.isWhatsAppInstalled()) {
        if (mounted) showSmToast(context, 'WhatsApp isn’t installed');
        return;
      }
      final all = await ref.read(savedProjectsProvider.future);
      final byId = {for (final p in all) p.id: p};
      await installer.addToWhatsApp(pack, byId);
      if (mounted) showSmToast(context, 'Opening WhatsApp…');
    } catch (_) {
      if (mounted) showSmToast(context, "Couldn't add to WhatsApp — try again");
    } finally {
      if (mounted) setState(() => _addingToWhatsApp = false);
    }
  }

  Future<void> _addToTelegram(StickerPack pack) async {
    if (_addingToTelegram) return;
    setState(() => _addingToTelegram = true);
    try {
      final all = await ref.read(savedProjectsProvider.future);
      final byId = {for (final p in all) p.id: p};
      final export = await ref
          .read(telegramPackShareProvider)
          .share(pack, byId);
      if (mounted) {
        showSmToast(
          context,
          'Shared — send to @Stickers, name it “${export.shortNameSuggestion}”',
        );
      }
    } catch (_) {
      if (mounted) {
        showSmToast(context, "Couldn't share to Telegram — try again");
      }
    } finally {
      if (mounted) setState(() => _addingToTelegram = false);
    }
  }

  Widget _topBar(BuildContext context, String name) {
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
          Expanded(
            child: GestureDetector(
              onTap: _pack == null ? null : _rename,
              child: Text(
                name.isEmpty ? 'Pack' : name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.display,
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          if (_pack != null)
            IconButton(
              tooltip: 'Rename',
              onPressed: _rename,
              icon: const Icon(
                Icons.edit_outlined,
                size: 19,
                color: AppColors.textMuted,
              ),
            ),
          IconButton(
            tooltip: 'Delete pack',
            onPressed: _pack == null ? null : _deletePack,
            icon: const Icon(
              Icons.delete_outline,
              size: 20,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String confirmLabel,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.panel,
      title: Text(
        title,
        style: const TextStyle(
          fontFamily: AppFonts.display,
          color: AppColors.textPrimary,
          fontSize: 17,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            confirmLabel,
            style: const TextStyle(color: AppColors.rose),
          ),
        ),
      ],
    ),
  );
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.pack});

  final StickerPack pack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Pill(
          label: '${pack.count} / 30',
          icon: Icons.layers_outlined,
          color: AppColors.violet,
        ),
        const SizedBox(width: 8),
        _Pill(
          label: pack.animated ? 'Animated' : 'Static',
          icon: pack.animated ? Icons.gif_box_outlined : Icons.image_outlined,
          color: pack.animated ? AppColors.orange : AppColors.cyan,
        ),
        const Spacer(),
        Text(
          'by ${pack.publisher}',
          style: const TextStyle(
            fontFamily: AppFonts.ui,
            fontSize: 11.5,
            color: AppColors.textFaint,
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.icon, required this.color});

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontFamily: AppFonts.ui,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Live compliance summary: a green "ready" chip, or the list of blocking /
/// advisory issues from [StickerPack.validate].
class _ComplianceBanner extends StatelessWidget {
  const _ComplianceBanner({required this.issues, required this.count});

  final List<ComplianceIssue> issues;
  final int count;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) {
      return _banner(
        color: AppColors.green,
        icon: Icons.check_circle_outline,
        title: 'Ready to share',
        lines: const ['This pack meets WhatsApp’s requirements.'],
      );
    }
    final hasError = issues.any((i) => i.severity == IssueSeverity.error);
    return _banner(
      color: hasError ? AppColors.amber : AppColors.cyan,
      icon: hasError ? Icons.error_outline : Icons.info_outline,
      title: hasError ? 'Not ready yet' : 'Heads up',
      lines: [for (final i in issues) i.message],
    );
  }

  Widget _banner({
    required Color color,
    required IconData icon,
    required String title,
    required List<String> lines,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: AppFonts.ui,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      l,
                      style: const TextStyle(
                        fontFamily: AppFonts.ui,
                        fontSize: 12,
                        height: 1.35,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddStickerButton extends StatelessWidget {
  const _AddStickerButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.cardAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.violet.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 20, color: AppColors.violetLight),
              SizedBox(width: 8),
              Text(
                'Add stickers',
                style: TextStyle(
                  fontFamily: AppFonts.ui,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.violetLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StickerRow extends StatelessWidget {
  const _StickerRow({
    required super.key,
    required this.index,
    required this.sticker,
    required this.project,
    required this.onEditEmojis,
    required this.onDelete,
  });

  final int index;
  final PackSticker sticker;
  final StickerProject? project;
  final VoidCallback onEditEmojis;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderFaint),
        ),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.drag_indicator,
                  size: 20,
                  color: AppColors.textFaint,
                ),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 52,
                height: 52,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const Checkerboard(cell: 7),
                    if (project != null && project!.frames.isNotEmpty)
                      StickerCanvas(frame: project!.frames.first)
                    else
                      const Icon(
                        Icons.broken_image_outlined,
                        size: 20,
                        color: AppColors.textFaint,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project?.name ?? 'Missing sticker',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.ui,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: onEditEmojis,
                    child: sticker.emojis.isEmpty
                        ? const Text(
                            '+ Add emoji tags',
                            style: TextStyle(
                              fontFamily: AppFonts.ui,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.amber,
                            ),
                          )
                        : Text(
                            sticker.emojis.join(' '),
                            style: const TextStyle(fontSize: 16),
                          ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
              icon: const Icon(
                Icons.close,
                size: 18,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPack extends StatelessWidget {
  const _EmptyPack();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderFaint),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            size: 30,
            color: AppColors.violetLight,
          ),
          SizedBox(height: 10),
          Text(
            'No stickers in this pack',
            style: TextStyle(
              fontFamily: AppFonts.ui,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Tap "Add stickers" to pull in your saved designs.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.ui,
              fontSize: 12,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet that lists the saved projects eligible to add.
class _AddStickerSheet extends StatelessWidget {
  const _AddStickerSheet({
    required this.choices,
    required this.packHasType,
    required this.animated,
  });

  final List<StickerProject> choices;
  final bool packHasType;
  final bool animated;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.elevated,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Add a sticker',
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontWeight: FontWeight.w600,
                fontSize: 17,
                color: AppColors.textPrimary,
              ),
            ),
            if (packHasType) ...[
              const SizedBox(height: 4),
              Text(
                'Only ${animated ? 'animated' : 'static'} stickers can join '
                'this pack.',
                style: const TextStyle(
                  fontFamily: AppFonts.ui,
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (choices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Text(
                  'No eligible stickers. Make one first, then add it here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppFonts.ui,
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              )
            else
              Flexible(
                child: GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  children: [
                    for (final p in choices)
                      GestureDetector(
                        onTap: () => Navigator.pop(context, p),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.borderFaint),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                const Checkerboard(cell: 8),
                                if (p.frames.isNotEmpty)
                                  StickerCanvas(frame: p.frames.first),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    color: const Color(0xB8131019),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    child: Text(
                                      p.name,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontFamily: AppFonts.ui,
                                        fontSize: 10.5,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
