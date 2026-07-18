import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/frame.dart';
import '../../core/models/sticker_project.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/sm_tokens.dart';
import '../../core/widgets/checkerboard.dart';
import '../about/about_sheet.dart';
import '../editor/state/editor_controller.dart';
import '../editor/widgets/sticker_canvas.dart';
import '../templates/template_picker.dart';
import 'project_repository.dart';

/// Home screen: brand header, the "New Sticker" hero action, quickstart chips
/// and a grid of the user's saved stickers (from [savedProjectsProvider]).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  void _newProject(BuildContext context, WidgetRef ref) {
    final project = StickerProject.empty(
      id: 'sm_${DateTime.now().microsecondsSinceEpoch}',
      createdAt: DateTime.now(),
    );
    ref.read(editorControllerProvider.notifier).loadProject(project);
    context.pushNamed(Routes.editor);
    // Persist in the background so it appears in the Recent grid.
    unawaited(_persist(ref, project));
  }

  Future<void> _persist(WidgetRef ref, StickerProject project) async {
    await ref.read(projectRepositoryProvider).save(project);
    ref.invalidate(savedProjectsProvider);
  }

  /// "Templates" quickstart: pick a pre-composed layout, open it as a fresh,
  /// fully-editable project.
  Future<void> _openTemplates(BuildContext context, WidgetRef ref) async {
    final template = await showTemplatePicker(context);
    if (template == null || !context.mounted) return;
    final now = DateTime.now();
    final id = 'sm_${now.microsecondsSinceEpoch}';
    final project = StickerProject(
      id: id,
      name: template.name,
      frames: [Frame(id: '${id}_f0', layers: template.buildLayers())],
      createdAt: now,
      updatedAt: now,
    );
    ref.read(editorControllerProvider.notifier).loadProject(project);
    unawaited(context.pushNamed(Routes.editor));
    unawaited(_persist(ref, project));
  }

  void _openProject(BuildContext context, WidgetRef ref, StickerProject p) {
    ref.read(editorControllerProvider.notifier).loadProject(p);
    context.pushNamed(Routes.editor);
  }

  Future<void> _deleteProject(WidgetRef ref, String id) async {
    await ref.read(projectRepositoryProvider).delete(id);
    ref.invalidate(savedProjectsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.sm;
    final textTheme = Theme.of(context).textTheme;
    final projectsAsync = ref.watch(savedProjectsProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            _Header(),
            const SizedBox(height: 16),
            _NewStickerCard(onTap: () => _newProject(context, ref)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _QuickChip(
                    label: 'From photo',
                    icon: Icons.image_outlined,
                    accent: AppColors.violet,
                    onTap: () => _newProject(context, ref),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickChip(
                    label: 'Templates',
                    icon: Icons.auto_awesome,
                    accent: AppColors.pink,
                    onTap: () => _openTemplates(context, ref),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickChip(
                    label: 'Blank',
                    icon: Icons.add,
                    accent: AppColors.cyan,
                    onTap: () => _newProject(context, ref),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _PacksEntry(onTap: () => context.pushNamed(Routes.packs)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent stickers',
                  style: textTheme.headlineSmall?.copyWith(fontSize: 15),
                ),
                Text('See all', style: textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 12),
            projectsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => const _EmptyRecent(),
              data: (projects) => projects.isEmpty
                  ? const _EmptyRecent()
                  : GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.82,
                      children: [
                        for (final p in projects)
                          _ProjectCard(
                            project: p,
                            radius: tokens.radiusCard,
                            onTap: () => _openProject(context, ref, p),
                            onDelete: () => _deleteProject(ref, p.id),
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

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = context.sm;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            gradient: tokens.logoGradient,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.violet.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.auto_awesome, size: 22, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sticker Maker',
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontWeight: FontWeight.w700,
                fontSize: 20,
                height: 1,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Make it stick.',
              style: TextStyle(
                fontFamily: AppFonts.ui,
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        const Spacer(),
        Semantics(
          button: true,
          label: 'About and settings',
          child: InkWell(
            onTap: () => showAboutSheet(context),
            customBorder: const CircleBorder(),
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.chipSurface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.more_horiz,
                size: 20,
                color: AppColors.violetLight,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NewStickerCard extends StatelessWidget {
  const _NewStickerCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.sm;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: tokens.heroGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.violetBright.withValues(alpha: 0.35),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.add, size: 28, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'New Sticker',
                        style: TextStyle(
                          fontFamily: AppFonts.display,
                          fontWeight: FontWeight.w600,
                          fontSize: 19,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Start from a photo of your pet',
                        style: TextStyle(
                          fontFamily: AppFonts.ui,
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderFaint),
          ),
          child: Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: AppFonts.ui,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PacksEntry extends StatelessWidget {
  const _PacksEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderFaint),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.violet.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.grid_view_rounded,
                  size: 19,
                  color: AppColors.violetLight,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sticker packs',
                      style: TextStyle(
                        fontFamily: AppFonts.ui,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      'Bundle stickers for WhatsApp & Telegram',
                      style: TextStyle(
                        fontFamily: AppFonts.ui,
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.radius,
    required this.onTap,
    required this.onDelete,
  });

  final StickerProject project;
  final double radius;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isGif = project.isAnimated;
    final layerCount = project.frames.isEmpty
        ? 0
        : project.frames.first.layers.length;
    final count = isGif
        ? '${project.frameCount} frames'
        : '$layerCount ${layerCount == 1 ? 'layer' : 'layers'}';

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        onLongPress: () => _confirmDelete(context),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: AppColors.borderFaint),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(radius),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const Checkerboard(cell: 9),
                      if (project.frames.isNotEmpty)
                        StickerCanvas(frame: project.frames.first),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xB8131019),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isGif ? 'GIF' : 'PNG',
                            style: TextStyle(
                              fontFamily: AppFonts.ui,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                              color: isGif
                                  ? AppColors.orange
                                  : AppColors.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        project.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.ui,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      count,
                      style: const TextStyle(
                        fontFamily: AppFonts.ui,
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text(
          'Delete "${project.name}"?',
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
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.rose),
            ),
          ),
        ],
      ),
    );
    if (ok ?? false) onDelete();
  }
}

class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderFaint),
      ),
      child: const Column(
        children: [
          Icon(Icons.auto_awesome, size: 34, color: AppColors.violetLight),
          SizedBox(height: 12),
          Text(
            'No stickers yet',
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Tap New Sticker to make your first one.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.ui,
              fontSize: 12.5,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
