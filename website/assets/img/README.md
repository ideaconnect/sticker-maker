# website/assets/img - provenance

Nothing in this directory is hand-drawn. Every file is either a **copy** of a
generated repo artefact or is itself **generated** by a committed script, so all
of it can be reproduced from the repo without a designer in the loop.

## Copied (do not edit in place - edit the source and re-copy)

| File | Source | Notes |
| --- | --- | --- |
| `logo.png` | `assets/branding/logo.png` | 192x192 RGBA, byte-identical copy. The in-app mark; used for the site header. |
| `icon-512.png` | `assets/branding/icon.png` | 512x512 RGBA, byte-identical copy. The Play Console listing square. |

Both sources are produced by `python tools/build_branding.py` from
`design/branding/app-icon-master.png`. If the brand mark changes, re-run that
script and re-copy - never retouch the copies here.

## Generated

| File | Produced by | Notes |
| --- | --- | --- |
| `favicon-64.png` | one-off Pillow LANCZOS downscale of `assets/branding/icon.png` | 64x64 RGBA, `optimize=True`. |
| `apple-touch-icon.png` | one-off Pillow LANCZOS downscale of `assets/branding/icon.png` | 180x180 RGBA, `optimize=True`. |
| `og-card.png` | `python website/tools/build_og_card.py` | 1200x630 RGB Open Graph / Twitter social card. Deterministic (fixed-seed dither); re-run it and the bytes are identical. |

Both downscales are a single call each and are trivially reproducible:

```python
from PIL import Image
src = Image.open("assets/branding/icon.png").convert("RGBA")
for size, name in ((64, "favicon-64.png"), (180, "apple-touch-icon.png")):
    src.resize((size, size), Image.LANCZOS).save(
        "website/assets/img/" + name, optimize=True)
```

`build_og_card.py` reads `assets/branding/icon.png`,
`assets/branding/icon_foreground.png` and the two OFL fonts in `assets/fonts/`,
so the card's typography and artwork always match the shipped app. Its layout
and colour constants are documented in its module docstring.

## Optimisation

`tools/optimize_res.py` is **not** used here. It hard-codes
`android/app/src/main/res` (see its `RES` constant) and rejects any argument
other than `--check` / `--dry-run` / `--strict`, so it cannot be pointed at this
directory; CI runs it in `--check --strict` mode over the Android path only.
Everything generated here is written with Pillow's `optimize=True` instead, and
the copies inherit the optimisation `build_branding.py` already applied.

## Fonts

Not in this directory - see `website/assets/fonts/`, which carries
`Fredoka-Variable.ttf` and `Bangers-Regular.ttf` copied from `assets/fonts/`
**together with `OFL-Fredoka.txt` and `OFL-Bangers.txt`**. The SIL Open Font
License requires the licence to travel with the fonts; do not delete those two
text files.
