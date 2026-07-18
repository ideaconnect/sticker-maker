/// Telegram deep links + pack short-name helpers for the guided @Stickers flow
/// (ADR 0003 / #48). Pure and host-testable; the actual hand-off to Telegram is
/// device-verified. Telegram has no client-side pack-creation API — these links
/// only *open @Stickers with a command prefilled* or *install an existing pack*.
abstract final class TelegramLinks {
  TelegramLinks._();

  /// Opens the official @Stickers bot with the create command prefilled — the
  /// user still taps send. `/newvideo` for animated packs, `/newpack` for static.
  ///
  /// e.g. `tg://resolve?domain=stickers&text=%2Fnewvideo`
  static Uri newPackCommand({required bool animated}) => Uri(
    scheme: 'tg',
    host: 'resolve',
    queryParameters: {
      'domain': 'stickers',
      'text': animated ? '/newvideo' : '/newpack',
    },
  );

  /// Web install link for a published pack: `https://t.me/addstickers/<name>`.
  /// Installs an existing pack — it cannot create one.
  static Uri installLink(String shortName) =>
      Uri.https('t.me', '/addstickers/$shortName');

  /// App-scheme install link: `tg://addstickers?set=<name>`.
  static Uri installAppLink(String shortName) => Uri(
    scheme: 'tg',
    host: 'addstickers',
    queryParameters: {'set': shortName},
  );

  /// Suggests a valid Telegram sticker-set short name from a pack title:
  /// lowercase, `[a-z0-9_]` only, must begin with a letter, 1–64 chars.
  /// Returns `stickers` if nothing usable remains.
  static String suggestShortName(String packName) {
    var s = packName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    // Must start with a letter.
    s = s.replaceFirst(RegExp(r'^[^a-z]+'), '');
    // Collapse and trim underscores.
    s = s.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    if (s.isEmpty) return 'stickers';
    return s.length > 64 ? s.substring(0, 64) : s;
  }
}
