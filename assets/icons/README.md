# Third-party icon assets

## `discord.png`

The Discord mark, shown on the Home header next to the About button.

- **Source:** Font Awesome Free 6.7.2, `svgs/brands/discord.svg`, taken verbatim
  from <https://github.com/FortAwesome/Font-Awesome> (`6.x` branch).
- **Licence:** Font Awesome Free icons are **CC BY 4.0**, which permits
  commercial use and requires attribution. This file is that attribution; the
  project website carries the same notice inline in its rendered HTML.
- **How it was produced:** the upstream SVG path was rendered white on a
  transparent background, trimmed to the glyph, centred on a square canvas and
  resized to 192x192. It is a PNG rather than an SVG on purpose: the app ships
  no SVG renderer, and adding one for a single icon is not worth the dependency.

Regenerate it by re-rendering the upstream SVG at 192x192 with `fill="#FFFFFF"`
on a transparent background, then trimming and centring. The colour is white
because Flutter tints it via `ImageIcon`, which multiplies the source by the
requested colour, so the asset must be white for the tint to come out right.

Discord is a trademark of Discord Inc. The mark is used here only to label a
link to the project's own Discord server, which is nominative use, not an
implication of endorsement.
