import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/core/theme/app_theme.dart';
import 'package:sticker_maker/features/home/all_projects_screen.dart';
import 'package:sticker_maker/features/home/project_repository.dart';
import 'package:sticker_maker/features/packs/pack_repository.dart';
import 'package:sticker_maker/features/packs/sticker_pack.dart';

/// In-memory pack repo so the delete path's `confirmAndDeleteProject` reads an
/// empty pack list in a microtask instead of hitting the real path_provider
/// channel (which never resolves under fake-async pumping).
class _EmptyPackRepository extends PackRepository {
  @override
  Future<List<StickerPack>> list() async => const [];
}

StickerProject _proj(String name, {bool animated = false}) => StickerProject(
  id: 'id_$name',
  name: name,
  frames: animated
      ? [Frame(id: '${name}_a'), Frame(id: '${name}_b')]
      : [Frame(id: '${name}_a')],
);

final _projects = [
  _proj('Happy Dog'),
  _proj('Sad Cat'),
  _proj('Dancing Dog', animated: true),
];

Future<void> _pump(WidgetTester tester, List<StickerProject> projects) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [savedProjectsProvider.overrideWith((ref) => projects)],
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

  testWidgets('lists every saved sticker', (tester) async {
    await _pump(tester, _projects);

    expect(find.text('All stickers'), findsOneWidget);
    expect(find.text('Happy Dog'), findsOneWidget);
    expect(find.text('Sad Cat'), findsOneWidget);
    expect(find.text('Dancing Dog'), findsOneWidget);
  });

  testWidgets('search filters by name', (tester) async {
    await _pump(tester, _projects);

    await tester.enterText(find.byType(TextField), 'dog');
    await tester.pump();

    expect(find.text('Happy Dog'), findsOneWidget);
    expect(find.text('Dancing Dog'), findsOneWidget);
    expect(find.text('Sad Cat'), findsNothing);
  });

  testWidgets('search by "gif" surfaces animated stickers only', (
    tester,
  ) async {
    await _pump(tester, _projects);

    await tester.enterText(find.byType(TextField), 'gif');
    await tester.pump();

    expect(find.text('Dancing Dog'), findsOneWidget);
    expect(find.text('Happy Dog'), findsNothing);
    expect(find.text('Sad Cat'), findsNothing);
  });

  testWidgets('a query with no matches shows the empty state', (tester) async {
    await _pump(tester, _projects);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();

    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('Happy Dog'), findsNothing);
  });

  testWidgets('clearing the search restores all stickers', (tester) async {
    await _pump(tester, _projects);

    await tester.enterText(find.byType(TextField), 'cat');
    await tester.pump();
    expect(find.text('Happy Dog'), findsNothing);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(find.text('Happy Dog'), findsOneWidget);
    expect(find.text('Sad Cat'), findsOneWidget);
    expect(find.text('Dancing Dog'), findsOneWidget);
  });

  testWidgets('with no saved stickers, shows the empty state', (tester) async {
    await _pump(tester, const []);

    expect(find.text('No stickers yet'), findsOneWidget);
  });

  group('tile long-press menu (repository-backed)', () {
    late Directory dir;
    late ProjectRepository repo;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('sm_allproj_');
      repo = ProjectRepository(baseDir: dir);
    });
    tearDown(() {
      imageCache.clear();
      imageCache.clearLiveImages();
      try {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } catch (_) {
        // Windows can briefly keep decoded-file handles open.
      }
    });

    /// Real repository IO inside a widget test: interleave real-async windows
    /// with clock-advancing pumps so file reads/writes, image decodes, and
    /// scheduled provider refreshes can all complete.
    Future<void> settleIO(WidgetTester tester) async {
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
    }

    Future<void> pumpWithRepo(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectRepositoryProvider.overrideWithValue(repo),
            packRepositoryProvider.overrideWithValue(_EmptyPackRepository()),
          ],
          child: MaterialApp(
            theme: buildStickerTheme(),
            home: const AllProjectsScreen(),
          ),
        ),
      );
      await settleIO(tester);
    }

    /// Saves 'Happy Dog' with one image layer pointing at a real tiny PNG in
    /// the repository's assets dir.
    Future<void> seed(WidgetTester tester) {
      final asset = File('${dir.path}/projects/assets/img_1.png');
      return tester.runAsync(() async {
        asset.parent.createSync(recursive: true);
        asset.writeAsBytesSync(img.encodePng(img.Image(width: 4, height: 4)));
        await repo.save(
          StickerProject(
            id: 'src',
            name: 'Happy Dog',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            frames: [
              Frame(
                id: 'src_f0',
                layers: [
                  ImageLayer(
                    id: 'src_l0',
                    name: 'Photo',
                    assetPath: asset.path,
                  ),
                ],
              ),
            ],
          ),
        );
      });
    }

    testWidgets('Duplicate saves a fresh-id copy sharing asset paths', (
      tester,
    ) async {
      await seed(tester);
      await pumpWithRepo(tester);
      expect(find.text('Happy Dog'), findsOneWidget);

      await tester.longPress(find.text('Happy Dog'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicate'));
      await settleIO(tester);

      expect(find.text('Happy Dog copy'), findsOneWidget);

      final all = (await tester.runAsync(() => repo.list()))!;
      expect(all, hasLength(2));
      final src = all.firstWhere((p) => p.name == 'Happy Dog');
      final copy = all.firstWhere((p) => p.name == 'Happy Dog copy');
      expect(copy.id, isNot(src.id));
      expect(copy.frames.single.id, isNot(src.frames.single.id));
      final srcImg = src.frames.single.layers.single as ImageLayer;
      final copyImg = copy.frames.single.layers.single as ImageLayer;
      expect(copyImg.id, isNot(srcImg.id));
      expect(
        copyImg.assetPath,
        srcImg.assetPath,
        reason: 'asset bytes are shared, never re-copied',
      );
    });

    testWidgets('Rename persists the new name via the repository', (
      tester,
    ) async {
      await seed(tester);
      await pumpWithRepo(tester);

      await tester.longPress(find.text('Happy Dog'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      expect(find.text('Rename sticker'), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Grumpy Cat',
      );
      await tester.tap(find.text('Save'));
      await settleIO(tester);

      expect(find.text('Grumpy Cat'), findsOneWidget);
      expect(find.text('Happy Dog'), findsNothing);

      final loaded = await tester.runAsync(() => repo.load('src'));
      expect(loaded!.name, 'Grumpy Cat');
    });

    testWidgets('Delete keeps its confirmation and removes the project', (
      tester,
    ) async {
      await seed(tester);
      await pumpWithRepo(tester);

      await tester.longPress(find.text('Happy Dog'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete "Happy Dog"?'), findsOneWidget);

      await tester.tap(find.text('Delete').last);
      await settleIO(tester);

      expect(find.text('Happy Dog'), findsNothing);
      expect(await tester.runAsync(() => repo.load('src')), isNull);
    });
  });
}
