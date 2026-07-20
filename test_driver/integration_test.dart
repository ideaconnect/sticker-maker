// Host-side driver for `integration_test/store_screenshots_test.dart`.
//
// `flutter drive` runs this in the host VM while the target test runs on the
// device. Every `binding.takeScreenshot(name)` from the device arrives here as
// raw PNG bytes, which we write to `$STORE_SHOTS_DIR/<name>.png`.
//
//   STORE_SHOTS_DIR=/abs/path/raw flutter drive \
//     --driver test_driver/integration_test.dart \
//     --target integration_test/store_screenshots_test.dart \
//     -d <device-id> --dart-define=SHOT_MODE=driver
//
// See `tools/store_shots/run_driver.sh` for the wrapper that also pushes the
// photo fixture.

import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final outDir =
      Platform.environment['STORE_SHOTS_DIR'] ?? 'build/store-shots/raw';

  await integrationDriver(
    onScreenshot:
        (String name, List<int> bytes, [Map<String, Object?>? args]) async {
          final file = File('$outDir${Platform.pathSeparator}$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes, flush: true);
          stdout.writeln(
            'STORE_SHOT_WROTE:${file.path} (${bytes.length} bytes)',
          );
          return true;
        },
  );
}
