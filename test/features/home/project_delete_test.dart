import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/core/theme/app_theme.dart';
import 'package:sticker_maker/features/home/all_projects_screen.dart';
import 'package:sticker_maker/features/home/project_repository.dart';
import 'package:sticker_maker/features/packs/pack_repository.dart';
import 'package:sticker_maker/features/packs/sticker_pack.dart';

/// In-memory repositories so widget-test fake-async isn't blocked on real IO.
class _FakeProjectRepository extends ProjectRepository {
  _FakeProjectRepository(List<StickerProject> initial) {
    for (final p in initial) {
      _store[p.id] = p;
    }
  }

  final Map<String, StickerProject> _store = {};

  bool contains(String id) => _store.containsKey(id);

  @override
  Future<void> save(StickerProject project) async =>
      _store[project.id] = project;
  @override
  Future<List<StickerProject>> list() async => _store.values.toList();
  @override
  Future<StickerProject?> load(String id) async => _store[id];
  @override
  Future<void> delete(String id) async => _store.remove(id);
}

class _FakePackRepository extends PackRepository {
  _FakePackRepository(List<StickerPack> initial) {
    for (final p in initial) {
      _store[p.id] = p;
    }
  }

  final Map<String, StickerPack> _store = {};

  @override
  Future<void> save(StickerPack pack) async => _store[pack.id] = pack;
  @override
  Future<List<StickerPack>> list() async => _store.values.toList();
  @override
  Future<StickerPack?> load(String id) async => _store[id];
  @override
  Future<void> delete(String id) async => _store.remove(id);
}

StickerProject _project(String id, String name) => StickerProject(
  id: id,
  name: name,
  frames: [Frame(id: '${id}_f0')],
);

PackSticker _sticker(String projectId) => PackSticker(
  id: 'ps_$projectId',
  projectId: projectId,
  emojis: const ['🐶'],
);

({_FakeProjectRepository projects, _FakePackRepository packs}) _repos(
  List<StickerPack> packs,
) => (
  projects: _FakeProjectRepository([
    _project('p_rex', 'Rex'),
    _project('p_bella', 'Bella'),
    _project('p_charlie', 'Charlie'),
  ]),
  packs: _FakePackRepository(packs),
);

Future<void> _pump(
  WidgetTester tester,
  _FakeProjectRepository projectRepo,
  _FakePackRepository packRepo,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        projectRepositoryProvider.overrideWithValue(projectRepo),
        packRepositoryProvider.overrideWithValue(packRepo),
      ],
      child: MaterialApp(
        theme: buildStickerTheme(),
        home: const AllProjectsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1080, 2400);
    view.devicePixelRatio = 2.0;
  });
  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets(
    'deleting a pack-member project warns by name and removes its slots '
    'from every pack',
    (tester) async {
      final repos = _repos([
        StickerPack(
          id: 'doggos',
          name: 'Doggos',
          stickers: [_sticker('p_rex'), _sticker('p_bella')],
        ),
        StickerPack(
          id: 'favorites',
          name: 'Favorites',
          stickers: [_sticker('p_rex')],
        ),
      ]);
      await _pump(tester, repos.projects, repos.packs);

      await tester.longPress(find.text('Rex'));
      await tester.pumpAndSettle();

      // The confirm dialog names every affected pack.
      expect(find.text('Delete "Rex"?'), findsOneWidget);
      expect(find.textContaining('Also used in pack "Doggos"'), findsOneWidget);
      expect(
        find.textContaining('Also used in pack "Favorites"'),
        findsOneWidget,
      );

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // The cascade persisted: no pack keeps a slot for the deleted project.
      final doggos = await repos.packs.load('doggos');
      expect(doggos!.stickers.map((s) => s.projectId), ['p_bella']);
      final favorites = await repos.packs.load('favorites');
      expect(favorites!.stickers, isEmpty);

      // ...and the project itself is gone (from disk and from the grid).
      expect(repos.projects.contains('p_rex'), isFalse);
      expect(find.text('Rex'), findsNothing);
    },
  );

  testWidgets('deleting a project in no pack shows a plain confirm', (
    tester,
  ) async {
    final repos = _repos([
      StickerPack(id: 'doggos', name: 'Doggos', stickers: [_sticker('p_rex')]),
    ]);
    await _pump(tester, repos.projects, repos.packs);

    await tester.longPress(find.text('Bella'));
    await tester.pumpAndSettle();

    expect(find.text('Delete "Bella"?'), findsOneWidget);
    expect(find.textContaining('Also used in pack'), findsNothing);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(repos.projects.contains('p_bella'), isFalse);
    expect((await repos.packs.load('doggos'))!.stickers, hasLength(1));
  });

  testWidgets('cancelling the confirm deletes nothing', (tester) async {
    final repos = _repos([
      StickerPack(id: 'doggos', name: 'Doggos', stickers: [_sticker('p_rex')]),
    ]);
    await _pump(tester, repos.projects, repos.packs);

    await tester.longPress(find.text('Rex'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repos.projects.contains('p_rex'), isTrue);
    expect((await repos.packs.load('doggos'))!.stickers, hasLength(1));
    expect(find.text('Rex'), findsOneWidget);
  });
}
