import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/responsive_center.dart';
import '../export/compliance_validator.dart';
import 'pack_dialogs.dart';
import 'pack_repository.dart';
import 'sticker_pack.dart';

/// Lists the user's saved sticker packs and lets them start a new one.
/// Tapping a pack drills into [PackDetailScreen] (`/pack/:id`).
class PacksScreen extends ConsumerWidget {
  const PacksScreen({super.key});

  Future<void> _createPack(BuildContext context, WidgetRef ref) async {
    final name = await promptPackName(context);
    if (name == null || !context.mounted) return;
    final id = 'pack_${DateTime.now().microsecondsSinceEpoch}';
    await ref
        .read(packRepositoryProvider)
        .save(StickerPack(id: id, name: name));
    ref.invalidate(savedPacksProvider);
    if (context.mounted) {
      unawaited(
        context.pushNamed(Routes.packDetail, pathParameters: {'id': id}),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packsAsync = ref.watch(savedPacksProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _topBar(context),
            Expanded(
              child: ResponsiveCenter(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  children: [
                    _NewPackCard(onTap: () => _createPack(context, ref)),
                    const SizedBox(height: 20),
                    const Text(
                      'YOUR PACKS',
                      style: TextStyle(
                        fontFamily: AppFonts.ui,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    packsAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (_, _) => const _EmptyPacks(),
                      data: (packs) => packs.isEmpty
                          ? const _EmptyPacks()
                          : Column(
                              children: [
                                for (final p in packs) ...[
                                  _PackRow(
                                    pack: p,
                                    onTap: () => context.pushNamed(
                                      Routes.packDetail,
                                      pathParameters: {'id': p.id},
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                              ],
                            ),
                    ),
                  ],
                ),
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
              'Sticker packs',
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontWeight: FontWeight.w600,
                fontSize: 17,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _NewPackCard extends StatelessWidget {
  const _NewPackCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.violet.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.violet.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.add,
                    size: 24,
                    color: AppColors.violetLight,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'New pack',
                        style: TextStyle(
                          fontFamily: AppFonts.display,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Bundle stickers for WhatsApp & Telegram',
                        style: TextStyle(
                          fontFamily: AppFonts.ui,
                          fontSize: 12,
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
      ),
    );
  }
}

class _PackRow extends StatelessWidget {
  const _PackRow({required this.pack, required this.onTap});

  final StickerPack pack;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // A pack is share-ready when it has no blocking WhatsApp issues.
    final ready = pack.validate().every(
      (i) => i.severity != IssueSeverity.error,
    );
    final accent = pack.animated ? AppColors.orange : AppColors.cyan;
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
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  pack.animated
                      ? Icons.gif_box_outlined
                      : Icons.grid_view_rounded,
                  size: 21,
                  color: accent,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pack.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppFonts.ui,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${pack.count} ${pack.count == 1 ? 'sticker' : 'stickers'}'
                      ' · ${pack.animated ? 'Animated' : 'Static'}',
                      style: const TextStyle(
                        fontFamily: AppFonts.ui,
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusDot(ready: ready),
              const SizedBox(width: 8),
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

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.ready});

  final bool ready;

  @override
  Widget build(BuildContext context) {
    final color = ready ? AppColors.green : AppColors.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        ready ? 'Ready' : 'Draft',
        style: TextStyle(
          fontFamily: AppFonts.ui,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _EmptyPacks extends StatelessWidget {
  const _EmptyPacks();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderFaint),
      ),
      child: const Column(
        children: [
          Icon(Icons.grid_view_rounded, size: 32, color: AppColors.violetLight),
          SizedBox(height: 12),
          Text(
            'No packs yet',
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Create a pack, then add your saved stickers to it.',
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
