import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/core/theme/app_theme.dart';
import 'package:sticker_maker/features/home/project_repository.dart';
import 'package:sticker_maker/features/packs/pack_detail_screen.dart';
import 'package:sticker_maker/features/packs/pack_repository.dart';
import 'package:sticker_maker/features/packs/sticker_pack.dart';

/// In-memory repository so widget-test fake-async isn't blocked on real file IO.
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

StickerProject _project(String id, String name) =>
    StickerProject(id: id, name: name, frames: [Frame(id: '${id}_f0')]);

PackSticker _sticker(String projectId, {List<String> emojis = const []}) =>
    PackSticker(id: 'ps_$projectId', projectId: projectId, emojis: emojis);

final _projects = [
  _project('p_rex', 'Rex'),
  _project('p_bella', 'Bella'),
  _project('p_charlie', 'Charlie'),
];

/// A 2-sticker static pack: Rex is tagged, Bella is not. (< 3 → "Not ready".)
StickerPack _seedPack() => StickerPack(
  id: 'pack1',
  name: 'Doggos',
  stickers: [
    _sticker('p_rex', emojis: const ['🐶']),
    _sticker('p_bella'),
  ],
);

Future<_FakePackRepository> _pumpDetail(WidgetTester tester) async {
  final repo = _FakePackRepository([_seedPack()]);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => context.push('/pack/pack1'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/pack/:id',
        builder: (context, state) =>
            PackDetailScreen(packId: state.pathParameters['id']!),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        packRepositoryProvider.overrideWithValue(repo),
        savedProjectsProvider.overrideWith((ref) => _projects),
      ],
      child: MaterialApp.router(
        theme: buildStickerTheme(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return repo;
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

  testWidgets('loads the pack with meta and live compliance feedback', (
    tester,
  ) async {
    await _pumpDetail(tester);

    expect(find.text('Doggos'), findsWidgets); // title (+ maybe elsewhere)
    expect(find.text('2 / 30'), findsOneWidget);
    expect(find.text('Static'), findsOneWidget);
    // < 3 stickers → blocking, so the banner says not ready.
    expect(find.text('Not ready yet'), findsOneWidget);
    expect(find.text('Add stickers'), findsOneWidget);
    // The resolved project names render on their rows.
    expect(find.text('Rex'), findsOneWidget);
    expect(find.text('Bella'), findsOneWidget);
  });

  testWidgets('tagging an untagged sticker persists the emoji', (tester) async {
    final repo = await _pumpDetail(tester);

    // Bella is untagged → shows the tag prompt.
    expect(find.text('+ Add emoji tags'), findsOneWidget);
    await tester.tap(find.text('+ Add emoji tags'));
    await tester.pumpAndSettle();

    // Pick a quick emoji, then save.
    expect(find.text('Emoji tags'), findsOneWidget);
    await tester.tap(find.text('🎉'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Both stickers now tagged → the prompt is gone.
    expect(find.text('+ Add emoji tags'), findsNothing);

    final saved = await repo.load('pack1');
    final bella =
        saved!.stickers.firstWhere((s) => s.projectId == 'p_bella');
    expect(bella.emojis, ['🎉']);
  });

  testWidgets('adds an eligible saved sticker from the sheet', (tester) async {
    final repo = await _pumpDetail(tester);

    await tester.tap(find.text('Add stickers'));
    await tester.pumpAndSettle();

    // Only Charlie is eligible (Rex & Bella are already in the pack).
    expect(find.text('Add a sticker'), findsOneWidget);
    expect(find.text('Charlie'), findsOneWidget);
    await tester.tap(find.text('Charlie'));
    await tester.pumpAndSettle();

    expect(find.text('3 / 30'), findsOneWidget);
    expect((await repo.load('pack1'))!.count, 3);
  });

  testWidgets('removing a sticker updates the pack', (tester) async {
    final repo = await _pumpDetail(tester);

    // Each sticker row has a close button; remove the first.
    expect(find.byIcon(Icons.close), findsNWidgets(2));
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();

    expect(find.text('1 / 30'), findsOneWidget);
    expect((await repo.load('pack1'))!.count, 1);
  });
}
