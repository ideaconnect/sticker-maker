import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/sticker_project.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/sm_tokens.dart';
import '../editor/state/editor_controller.dart';
import 'project_repository.dart';
import 'widgets/project_tile.dart';

/// Browse and search every saved sticker (#63), reached from the Home
/// "See all". Filters by name (and the GIF/PNG type keyword) live as you type.
class AllProjectsScreen extends ConsumerStatefulWidget {
  const AllProjectsScreen({super.key});

  @override
  ConsumerState<AllProjectsScreen> createState() => _AllProjectsScreenState();
}

class _AllProjectsScreenState extends ConsumerState<AllProjectsScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Case-insensitive match on the project name, plus the `gif`/`png` type so
  /// "gif" surfaces animated stickers.
  static bool _matches(StickerProject p, String q) {
    if (q.isEmpty) return true;
    final needle = q.toLowerCase();
    final type = p.isAnimated ? 'gif' : 'png';
    return p.name.toLowerCase().contains(needle) || type.contains(needle);
  }

  void _openProject(StickerProject p) {
    ref.read(editorControllerProvider.notifier).loadProject(p);
    context.pushNamed(Routes.editor);
  }

  Future<void> _deleteProject(String id) async {
    await ref.read(projectRepositoryProvider).delete(id);
    ref.invalidate(savedProjectsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.sm;
    final projectsAsync = ref.watch(savedProjectsProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _topBar(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
              child: _searchField(),
            ),
            Expanded(
              child: projectsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (_, _) => const _Empty(
                  icon: Icons.error_outline,
                  title: "Couldn't load your stickers",
                  body: 'Try again in a moment.',
                ),
                data: (all) {
                  if (all.isEmpty) {
                    return const _Empty(
                      icon: Icons.auto_awesome,
                      title: 'No stickers yet',
                      body: 'Make one from Home and it will show up here.',
                    );
                  }
                  final matches =
                      all.where((p) => _matches(p, _query)).toList();
                  if (matches.isEmpty) {
                    return _Empty(
                      icon: Icons.search_off,
                      title: 'No matches',
                      body: 'Nothing matches "$_query".',
                    );
                  }
                  return GridView.count(
                    crossAxisCount: 2,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.82,
                    children: [
                      for (final p in matches)
                        ProjectTile(
                          project: p,
                          radius: tokens.radiusCard,
                          onTap: () => _openProject(p),
                          onDelete: () => _deleteProject(p.id),
                        ),
                    ],
                  );
                },
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
              'All stickers',
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

  Widget _searchField() {
    return TextField(
      controller: _controller,
      onChanged: (v) => setState(() => _query = v.trim()),
      textInputAction: TextInputAction.search,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.inputField,
        hintText: 'Search your stickers',
        hintStyle: const TextStyle(color: AppColors.textFaint, fontSize: 14),
        prefixIcon: const Icon(
          Icons.search,
          size: 20,
          color: AppColors.textMuted,
        ),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(
                  Icons.close,
                  size: 18,
                  color: AppColors.textMuted,
                ),
                onPressed: () {
                  _controller.clear();
                  setState(() => _query = '');
                },
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: AppColors.violetLight),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppFonts.ui,
                fontSize: 12.5,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
