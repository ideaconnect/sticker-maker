import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/core/theme/app_theme.dart';
import 'package:sticker_maker/features/home/all_projects_screen.dart';
import 'package:sticker_maker/features/home/project_repository.dart';

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
}
