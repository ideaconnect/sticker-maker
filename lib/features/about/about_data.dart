/// Static "About" content: the privacy summary and the third‑party license
/// notices shown in‑app. Pure data so it can be unit‑tested and kept in sync
/// with `docs/legal/privacy-policy.md`.
abstract final class AboutInfo {
  AboutInfo._();

  static const appName = 'Sticker Maker';
  static const appVersion = '1.0.0';
  static const publisher = 'IDCT · Bartosz Pachołek';
  static const contactEmail = 'bartosz@idct.tech';

  /// Canonical hosted privacy policy. Keep identical to the URL entered in
  /// Play Console and served from `docs/legal/privacy-policy.md`. The trailing
  /// slash is canonical: the site is built with Jekyll's `permalink: pretty`,
  /// so the slash-less form costs a redirect.
  static const privacyUrl = 'https://idct.tech/sticker-maker/privacy/';

  /// The project's Discord server, linked from the Home header.
  static const discordUrl = 'https://discord.gg/uYsuaa8HNm';

  /// The plain‑language privacy promises shown on the in‑app privacy screen.
  static const privacyHighlights = <String>[
    'Everything happens on your device — nothing is uploaded.',
    'AI background removal runs locally; your photos never leave your phone.',
    'No data collection, no analytics, no crash tracking.',
    'No ads and no advertising IDs — ever.',
    'No account and no sign‑in.',
  ];
}

/// One third‑party component we ship, with attribution and its SPDX license.
class LicenseNotice {
  const LicenseNotice({
    required this.category,
    required this.name,
    required this.by,
    required this.license,
    required this.use,
  });

  final String category;
  final String name;

  /// Author / copyright holder.
  final String by;

  /// SPDX identifier or license name.
  final String license;

  /// What the component is used for in the app.
  final String use;
}

/// The curated in‑app notices. Flutter's aggregated license page (linked from
/// the Licenses screen) additionally lists every pub package automatically;
/// this list covers the bundled assets and headline components a reader cares
/// about. `[planned]` items ship with the native encoders (#42).
const licenseNotices = <LicenseNotice>[
  // Fonts (bundled — see assets/fonts/*.txt).
  LicenseNotice(
    category: 'Fonts',
    name: 'Plus Jakarta Sans',
    by: 'Tokotype',
    license: 'SIL OFL 1.1',
    use: 'UI typeface',
  ),
  LicenseNotice(
    category: 'Fonts',
    name: 'Fredoka',
    by: 'Milena Brandão · Hafontia',
    license: 'SIL OFL 1.1',
    use: 'Display typeface',
  ),
  LicenseNotice(
    category: 'Fonts',
    name: 'Bangers',
    by: 'Vernon Adams',
    license: 'SIL OFL 1.1',
    use: 'Comic caption font',
  ),
  LicenseNotice(
    category: 'Fonts',
    name: 'Luckiest Guy',
    by: 'Astigmatic',
    license: 'Apache-2.0',
    use: 'Caption font',
  ),
  LicenseNotice(
    category: 'Fonts',
    name: 'Pacifico',
    by: 'Cyreal',
    license: 'SIL OFL 1.1',
    use: 'Script caption font',
  ),
  LicenseNotice(
    category: 'Fonts',
    name: 'Rubik',
    by: 'Hubert & Fischer · Google',
    license: 'SIL OFL 1.1',
    use: 'Caption font',
  ),
  // On‑device AI.
  LicenseNotice(
    category: 'On‑device AI',
    name: 'Google ML Kit — Subject Segmentation',
    by: 'Google',
    license: 'Google ML Kit Terms',
    use: 'Background removal (Android)',
  ),
  LicenseNotice(
    category: 'On‑device AI',
    name: 'ONNX Runtime',
    by: 'Microsoft',
    license: 'MIT',
    use: 'Runs the bundled fallback model',
  ),
  LicenseNotice(
    category: 'On‑device AI',
    name: 'Bundled segmentation model',
    by: 'Sticker Maker',
    license: 'Apache-2.0',
    use: 'On‑device fallback background removal',
  ),
  // Media encoding.
  LicenseNotice(
    category: 'Media encoding',
    name: 'image (Dart)',
    by: 'Brendan Duncan',
    license: 'Apache-2.0 / MIT',
    use: 'PNG & animated GIF encoding',
  ),
  LicenseNotice(
    category: 'Media encoding',
    name: 'libwebp [planned]',
    by: 'Google',
    license: 'BSD-3-Clause',
    use: 'Animated WebP stickers',
  ),
  LicenseNotice(
    category: 'Media encoding',
    name: 'libvpx & libwebm [planned]',
    by: 'Google / WebM Project',
    license: 'BSD-3-Clause',
    use: 'Telegram WebM (VP9) video stickers',
  ),
  // Framework & packages.
  LicenseNotice(
    category: 'Framework & packages',
    name: 'Flutter',
    by: 'Google',
    license: 'BSD-3-Clause',
    use: 'App framework',
  ),
  LicenseNotice(
    category: 'Framework & packages',
    name: 'go_router · path_provider · share_plus · image_picker',
    by: 'Flutter team',
    license: 'BSD-3-Clause',
    use: 'Routing, storage, sharing, image picking',
  ),
  LicenseNotice(
    category: 'Framework & packages',
    name: 'Riverpod',
    by: 'Remi Rousselet',
    license: 'MIT',
    use: 'State management',
  ),
  LicenseNotice(
    category: 'Framework & packages',
    name: 'pasteboard',
    by: 'Kingsword',
    license: 'MIT',
    use: 'Paste image from clipboard',
  ),
];

/// Distinct categories in [licenseNotices], in first‑seen order.
List<String> licenseCategories() {
  final seen = <String>[];
  for (final n in licenseNotices) {
    if (!seen.contains(n.category)) seen.add(n.category);
  }
  return seen;
}
