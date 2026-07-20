#!/usr/bin/env python3
"""Shrink the generated PNGs under android/app/src/main/res, losslessly.

    python tools/optimize_res.py            # rewrite in place
    python tools/optimize_res.py --check    # exit 1 if step 3 was skipped
    python tools/optimize_res.py --dry-run  # report, write nothing
    python tools/optimize_res.py --strict   # also exit 1 on any SKIP line

This is step 3 of the branding regeneration (see tools/build_branding.py's
header). It must run *after* `dart run flutter_launcher_icons` and
`dart run flutter_native_splash:create`, because both call the Dart `image`
package's bare `encodePng` -- no optimisation pass, no bit-depth reduction,
and whatever channel layout they hold in memory is what lands on disk.

Every transform here is LOSSLESS: identical RGB in every pixel with alpha > 0
and an identical alpha channel, byte for byte. That is a deliberate limit, not
an oversight. The artwork is a wide conic gradient plus a soft alpha shadow,
and palette quantisation was measured against it: undithered palettes contour
the gradient (low-pass error up to 13/255 -- textbook topographic banding),
dithered palettes multiply the authored grain by 8-13x, and PNG8's
per-entry alpha collapses the character's shadow ramp to 3-4 hard steps. So
none of that is done. The savings below come only from
  * Pillow's PNG encoder being better than the Dart one at the same pixels,
  * dropping the RGB garbage under fully transparent pixels (invisible, but
    the encoder pays for it), and
  * indexing the monochrome layer, which is genuinely <=256 distinct RGBA
    values and therefore exactly representable, and
  * deleting the night splash duplicates, which is where the real money is.

Recipes, per image class:

  ic_launcher_background  opaque conic gradient      -> re-encode as RGB
  mipmap ic_launcher      gradient + character, opaque -> re-encode as RGB
  ic_launcher_foreground  character + soft shadow    -> clear transparent RGB
  splash / android12splash  transparent tile         -> clear transparent RGB
  ic_launcher_monochrome  white-on-transparent       -> exact palette or LA

Safety rules:
  * a candidate is written only if it is strictly smaller than what is there
    (drawable*/background.png-style degenerate files can only grow, and the
    pass therefore re-rejects them silently on every run);
  * only the six generated filenames are touched, so a future hand-authored
    drawable is never rewritten;
  * output is a pure function of input bytes, so a second run is a no-op.

--check, and why its two branches are graded differently
--------------------------------------------------------
The dedupe branch compares sha256 digests of bytes already on disk. It has zero
dependency on this machine's PNG encoder, so it fails hard: one surviving night
duplicate is a failure.

The re-encode branch compares a *freshly encoded* candidate against the
committed bytes, so it does depend on the encoder build -- not merely on the
version string. Measured on this tree: with the pinned Pillow the margin is +0 B
on all 29 optimizable files (a re-encode reproduces the committed bytes
exactly), but Pillow 10.4.0 -- which links plain zlib, where 11.0+ bundles
zlib-ng -- "finds" 75 B of phantom savings across 4 files and would fail the
check on a perfectly optimized tree. Worse, the fix it suggests (run the tool)
would rewrite those files with the other encoder and flip the check red in the
opposite direction: a ping-pong with no fixed point. So the re-encode branch
only fails once the total exceeds RE_ENCODE_TOLERANCE, which sits ~100x above
the measured drift and ~150x below the smallest real regression (a genuinely
skipped step 3 leaves >1.2 MB on the table, and the smallest single-file
regression that can occur -- one raw monochrome PNG -- is 713 B).

--strict additionally fails on SKIP. A SKIP means "this file is one of the six
the Dart generators emit, but its channel layout does not match any recipe" --
an unhandled state, not a pass. CI runs `--check --strict` so that state can
never be reported green.
"""

import hashlib
import os
import sys

import numpy as np
from PIL import Image

RES = os.path.join("android", "app", "src", "main", "res")

# --check only fails the re-encode branch above this many bytes of total
# savings; see the "--check" section of the module docstring for the numbers.
# The dedupe branch is encoder-independent and has no tolerance.
RE_ENCODE_TOLERANCE = 8192

# only files the two Dart generators emit -- never a hand-authored drawable
OPAQUE = ("ic_launcher.png", "ic_launcher_background.png")
TRANSPARENT = ("ic_launcher_foreground.png", "splash.png", "android12splash.png")
INDEXABLE = ("ic_launcher_monochrome.png",)
GENERATED = OPAQUE + TRANSPARENT + INDEXABLE


def _png_bytes(im, **kw):
    import io
    buf = io.BytesIO()
    im.save(buf, format="PNG", optimize=True, **kw)
    return buf.getvalue()


def candidate(path):
    """Smallest lossless re-encoding of `path`, or None if it has no recipe."""
    name = os.path.basename(path)
    with Image.open(path) as src:
        rgba = np.asarray(src.convert("RGBA"))

    if name in OPAQUE:
        if rgba[..., 3].min() != 255:            # not actually opaque: bail out
            return None
        return _png_bytes(Image.fromarray(rgba[..., :3], "RGB"))

    if name in TRANSPARENT:
        a = rgba.copy()
        a[a[..., 3] == 0, :3] = 0                # invisible, but it costs bytes
        return _png_bytes(Image.fromarray(a, "RGBA"))

    if name in INDEXABLE:
        flat = rgba.reshape(-1, 4)
        pal, idx = np.unique(flat, axis=0, return_inverse=True)
        best = None
        if len(pal) <= 256:                      # exactly representable as PNG8
            p = Image.fromarray(idx.astype(np.uint8).reshape(rgba.shape[:2]), "P")
            p.putpalette(pal.astype(np.uint8).tobytes(), "RGBA")
            best = _png_bytes(p)
        # the layer is white-on-transparent, so luminance+alpha is also exact
        if np.array_equal(rgba[..., 0], rgba[..., 1]) and \
           np.array_equal(rgba[..., 1], rgba[..., 2]):
            la = _png_bytes(Image.fromarray(rgba[..., [0, 3]], "LA"))
            if best is None or len(la) < len(best):
                best = la
        return best

    return None


def verify(path, blob):
    """Assert the candidate is pixel-identical where it can be seen."""
    import io
    with Image.open(path) as a:
        old = np.asarray(a.convert("RGBA")).astype(np.int16)
    with Image.open(io.BytesIO(blob)) as b:
        new = np.asarray(b.convert("RGBA")).astype(np.int16)
    if old.shape != new.shape:
        return "shape %s -> %s" % (old.shape, new.shape)
    if not np.array_equal(old[..., 3], new[..., 3]):
        return "alpha channel changed"
    vis = old[..., 3] > 0
    if not np.array_equal(old[vis][:, :3], new[vis][:, :3]):
        return "visible RGB changed"
    return None


def night_duplicates(res):
    """drawable-night-*/android12splash.png that equal their day twin."""
    dupes = []
    for d in sorted(os.listdir(res)):
        if not d.startswith("drawable-night-"):
            continue
        night = os.path.join(res, d, "android12splash.png")
        day = os.path.join(res, d.replace("drawable-night-", "drawable-"),
                           "android12splash.png")
        if not (os.path.isfile(night) and os.path.isfile(day)):
            continue
        h = lambda p: hashlib.sha256(open(p, "rb").read()).hexdigest()
        if h(night) == h(day):
            dupes.append(night)
    return dupes


def main():
    # a typo like `--dryrun` must not fall through to the rewriting default
    unknown = [a for a in sys.argv[1:]
               if a not in ("--check", "--dry-run", "--strict")]
    if unknown:
        print("unknown argument(s): %s" % " ".join(unknown))
        print(__doc__.split("\n\n")[0].strip())
        return 2

    check = "--check" in sys.argv
    dry = "--dry-run" in sys.argv
    strict = "--strict" in sys.argv
    # --check/--dry-run only pretend, so the report must not read like a rewrite
    verb = "would " if (check or dry) else ""
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    res = os.path.join(root, RES)
    rel = lambda p: os.path.relpath(p, root).replace("\\", "/")
    saved = 0
    saved_encode = 0                             # graded with a tolerance
    stale = []
    dupes = []                                   # graded strictly
    skipped = []                                 # unhandled: --strict fails

    # 1. night duplicates. flutter_native_splash 2.4.8 has no "no dark image"
    #    sentinel (cli_commands.dart:179 does `android12DarkImagePath:
    #    android12DarkImage ?? android12Image`), so it always writes a byte copy
    #    of the day art. values-night-v31/styles.xml names @drawable/
    #    android12splash, which resolves to the non-night bucket once these are
    #    gone -- same pixels, so there is nothing to see.
    for p in night_duplicates(res):
        n = os.path.getsize(p)
        saved += n
        stale.append(p)
        dupes.append(p)
        print(f"  {verb}dedupe  {rel(p):<58s} -{n:>9,d} B")
        if not (check or dry):
            os.remove(p)
            d = os.path.dirname(p)               # the night buckets hold nothing
            if not os.listdir(d):                # else -- do not leave a husk
                os.rmdir(d)

    # 2. lossless re-encode
    for dirpath, _, files in os.walk(res):
        for f in sorted(files):
            if f not in GENERATED:
                continue
            p = os.path.join(dirpath, f)
            if p in stale:                       # already accounted for: a
                continue                         # night duplicate --check/--dry
            blob = candidate(p)                  # -run only pretended to delete
            if blob is None:                     # a generated file whose class
                skipped.append(p)                # recipe refused it: say why
                print(f"  SKIP    {rel(p):<58s} "
                      "no lossless recipe applies (unexpected channel layout)")
                continue
            old = os.path.getsize(p)
            if len(blob) >= old:                 # never grow a file
                continue
            bad = verify(p, blob)
            if bad:
                skipped.append(p)
                print(f"  SKIP    {rel(p):<58s} not lossless: {bad}")
                continue
            saved += old - len(blob)
            saved_encode += old - len(blob)
            stale.append(p)
            print(f"  {verb}encode  {rel(p):<58s} {old:>9,d} -> {len(blob):>9,d} B")
            if not (check or dry):
                with open(p, "wb") as fh:
                    fh.write(blob)

    print(f"  {'WOULD SAVE' if (check or dry) else 'TOTAL SAVED':<66s} "
          f"{saved:>9,d} B")

    rc = 0
    if check:
        # dedupe: byte-exact, encoder-independent -> no tolerance.
        # re-encode: encoder-dependent -> tolerance (see the docstring).
        if dupes:
            print(f"res/ is not optimized: {len(dupes)} night-splash duplicate(s) "
                  f"still present ({saved - saved_encode:,d} B).")
            rc = 1
        if saved_encode > RE_ENCODE_TOLERANCE:
            print(f"res/ is not optimized: {saved_encode:,d} B of re-encoding "
                  f"left on the table (tolerance {RE_ENCODE_TOLERANCE:,d} B).")
            rc = 1
        elif saved_encode:
            print(f"note: {saved_encode:,d} B of re-encode savings is within the "
                  f"{RE_ENCODE_TOLERANCE:,d} B PNG-encoder-drift tolerance; "
                  "not a failure.")
        if rc:
            print("Run `python tools/optimize_res.py` after the "
                  "flutter_launcher_icons / flutter_native_splash generators.")
    if strict and skipped:
        # An unhandled state is not a pass: the file is one of the six the Dart
        # generators emit, but no recipe recognised it (see build_branding.py's
        # note on package:image's box-average alpha rounding for how this
        # happens). Something upstream changed; look before shipping it.
        print(f"{len(skipped)} generated file(s) SKIPPED above: no lossless "
              "recipe applies. --strict treats that as a failure.")
        rc = rc or 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
