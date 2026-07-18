import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A bundled license text shipped as an asset (the shipped fonts are SIL OFL /
/// Apache-2.0, which require distributing their license text with the app).
class BundledLicense {
  const BundledLicense(this.packages, this.asset);

  /// Component name(s) the license covers, shown on the full license page.
  final List<String> packages;

  /// Asset path of the license text (declared in pubspec).
  final String asset;
}

/// Font license texts bundled in `assets/fonts/`. Kept in sync with the
/// `fonts:` section of pubspec and the notices in [licenseNotices].
const bundledLicenses = <BundledLicense>[
  BundledLicense(['Plus Jakarta Sans'], 'assets/fonts/OFL-PlusJakartaSans.txt'),
  BundledLicense(['Fredoka'], 'assets/fonts/OFL-Fredoka.txt'),
  BundledLicense(['Bangers'], 'assets/fonts/OFL-Bangers.txt'),
  BundledLicense(
    ['Luckiest Guy'],
    'assets/fonts/LICENSE-LuckiestGuy-Apache.txt',
  ),
  BundledLicense(['Pacifico'], 'assets/fonts/OFL-Pacifico.txt'),
  BundledLicense(['Rubik'], 'assets/fonts/OFL-Rubik.txt'),
];

/// Registers the bundled font license texts into [LicenseRegistry] so they
/// appear on Flutter's aggregated license page (reachable from the in‑app
/// Licenses screen). Call once at startup. Pass [bundle] in tests.
void registerBundledLicenses([AssetBundle? bundle]) {
  final assets = bundle ?? rootBundle;
  LicenseRegistry.addLicense(() async* {
    for (final entry in bundledLicenses) {
      final text = await assets.loadString(entry.asset);
      yield LicenseEntryWithLineBreaks(entry.packages, text);
    }
  });
}
