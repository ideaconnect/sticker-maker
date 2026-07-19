import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_logo.dart';
import 'about_data.dart';

/// Opens the About / settings sheet from the Home avatar: app identity plus
/// links to the privacy summary and open‑source licenses.
Future<void> showAboutSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _AboutSheet(parentContext: context),
  );
}

class _AboutSheet extends StatelessWidget {
  const _AboutSheet({required this.parentContext});

  /// The screen's context, used to navigate after the sheet closes.
  final BuildContext parentContext;

  void _go(BuildContext sheetContext, String route) {
    Navigator.of(sheetContext).pop();
    parentContext.pushNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
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
            const SizedBox(height: 18),
            const Row(
              children: [
                AppLogo(size: 46, radius: 14),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AboutInfo.appName,
                        style: TextStyle(
                          fontFamily: AppFonts.display,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'v${AboutInfo.appVersion} · ${AboutInfo.publisher}',
                        style: TextStyle(
                          fontFamily: AppFonts.ui,
                          fontSize: 11.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _AboutRow(
              icon: Icons.verified_user_outlined,
              label: 'Privacy policy',
              sub: 'Private by design — nothing is collected',
              onTap: () => _go(context, Routes.privacy),
            ),
            const SizedBox(height: 10),
            _AboutRow(
              icon: Icons.article_outlined,
              label: 'Open‑source licenses',
              sub: 'The great work we build on',
              onTap: () => _go(context, Routes.licenses),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
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
                child: Icon(icon, size: 19, color: AppColors.violetLight),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontFamily: AppFonts.ui,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      sub,
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
