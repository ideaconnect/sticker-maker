import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import 'about_data.dart';

/// Curated third‑party attributions, grouped by category, with a link to
/// Flutter's full aggregated license page (which also lists every pub package).
class LicensesScreen extends StatelessWidget {
  const LicensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final categories = licenseCategories();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _topBar(context, 'Open‑source licenses'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  const Text(
                    'Sticker Maker is built on wonderful open‑source work. '
                    'Thank you to everyone who made it.',
                    style: TextStyle(
                      fontFamily: AppFonts.ui,
                      fontSize: 13,
                      height: 1.45,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 18),
                  for (final category in categories) ...[
                    _SectionHeader(category),
                    const SizedBox(height: 10),
                    for (final n
                        in licenseNotices.where((n) => n.category == category))
                      _NoticeCard(n),
                    const SizedBox(height: 18),
                  ],
                  OutlinedButton.icon(
                    onPressed: () => showLicensePage(
                      context: context,
                      applicationName: AboutInfo.appName,
                      applicationVersion: AboutInfo.appVersion,
                    ),
                    icon: const Icon(Icons.article_outlined, size: 18),
                    label: const Text('View full license texts'),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontFamily: AppFonts.ui,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: AppColors.textMuted,
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard(this.notice);

  final LicenseNotice notice;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderFaint),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notice.name,
                  style: const TextStyle(
                    fontFamily: AppFonts.ui,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${notice.use} · ${notice.by}',
                  style: const TextStyle(
                    fontFamily: AppFonts.ui,
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.violet.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              notice.license,
              style: const TextStyle(
                fontFamily: AppFonts.ui,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: AppColors.violetLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _topBar(BuildContext context, String title) {
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
          child: Text(
            title,
            style: const TextStyle(
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
