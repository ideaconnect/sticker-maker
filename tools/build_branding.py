#!/usr/bin/env python3
"""Regenerate assets/branding/* from design/branding/app-icon-master.png.

    pip install pillow numpy
    python tools/build_branding.py            # writes assets/branding/
    python tools/build_branding.py <src> <out dir> [--preview DIR]

Deterministic and re-runnable: the only randomness is a fixed-seed dither.
Requires Pillow + numpy only (no ImageMagick, no network).

Treatment — "full-bleed gradient background + isolated character foreground":
the master artwork is a rounded tile (conic gradient) with a character drawn on
it. Android's adaptive icon wants those as two separate layers, so the script
cuts the character out and *reconstructs* the gradient underneath it, then
renders the gradient edge to edge so any launcher mask shape sees only gradient.

Pipeline
--------
1.  Trim the master to the artwork tile (alpha >= 8)               -> 778 x 735
2.  Isolate the character (white bubble + cyan sticker + pencil) by
    thresholding the dark navy outline, closing it, taking the largest
    connected component and flood-filling it from the outside.
3.  Reconstruct the tile's gradient as a smooth field. The perimeter hue sweeps
    monotonically clockwise — it is an angular (conic) gradient, so the model
    lives in polar (theta, t) coordinates normalised by the rounded-rect
    boundary; filling the character hole is then extrapolation along rays
    rather than a hue smear across the tile. Dithered before 8-bit quantisation
    because a 1024 px gradient this wide bands visibly on OLED.
4.  Layers, all sized in dp on the 108dp adaptive canvas (1024 px):
      adaptive_background.png  432 px, opaque, full bleed
      icon_foreground.png      1024 px, character inside the 66dp safe circle,
                               synthesised drop shadow faded out before 72dp
      icon_monochrome.png      1024 px, white silhouette with the interior line
                               art knocked out (Android 13+ themed icons)
      icon.png                 512 px legacy / Play square: the same two layers
                               composited, character at the master's own scale
      splash.png 512 / splash_android12.png 1152 / logo.png 192
"""

import os
import sys

import numpy as np
from PIL import Image

# ----------------------------------------------------------------------------
# constants
# ----------------------------------------------------------------------------
ICON = 1024                       # adaptive layer size (108dp)
DP = ICON / 108.0                 # px per dp
VIS = int(round(72 * DP))         # 683 px - launcher-visible box
SAFE = int(round(66 * DP))        # 626 px - guaranteed-safe circle
BG_TILE = 700                     # gradient tile size inside the 1024 canvas
BG_OUT = 432                      # shipped background size (xxxhdpi bucket)
LEGACY = 512                      # legacy / Play Console listing icon size
FG_CIRCLE_D = SAFE - 6            # fg min-enclosing circle: 66dp less the feather
SHADOW_FADE = (300.0, 335.0)      # shadow alpha ramps to 0 before the 72dp mask
DITHER_SEED = 20260719


# ----------------------------------------------------------------------------
# small helpers
# ----------------------------------------------------------------------------
def _box_axis(a, r, axis):
    """Edge-replicated box mean of half-width r along `axis` (cumsum, O(n))."""
    if r < 1:
        return a
    a = np.moveaxis(a, axis, 0)
    pad = [(r + 1, r)] + [(0, 0)] * (a.ndim - 1)
    p = np.pad(a, pad, mode="edge")
    c = np.cumsum(p, axis=0, dtype=np.float64)
    out = (c[2 * r + 1:] - c[:-(2 * r + 1)]) / (2 * r + 1)
    return np.moveaxis(out.astype(np.float32), 0, axis)


def gaussian(a, sigma, passes=3):
    """Gaussian blur (3 box passes, edge-replicated) of a float HxW/HxWxC."""
    if sigma <= 0:
        return np.asarray(a, np.float32).copy()
    arr = np.asarray(a, np.float32)
    # box half-width whose `passes`-fold self-convolution matches sigma
    r = max(1, int(round((np.sqrt(12.0 * sigma * sigma / passes + 1.0) - 1.0) / 2.0)))
    for _ in range(passes):
        arr = _box_axis(arr, r, 0)
        arr = _box_axis(arr, r, 1)
    return arr


def resize_f(a, size, resample=Image.LANCZOS):
    """LANCZOS-resize a float HxW or HxWxC array. size = (w, h)."""
    single = a.ndim == 2
    arr = a[..., None] if single else a
    out = np.empty((size[1], size[0], arr.shape[2]), np.float32)
    for c in range(arr.shape[2]):
        im = Image.fromarray(arr[..., c].astype(np.float32), mode="F")
        out[..., c] = np.asarray(im.resize(size, resample), dtype=np.float32)
    return out[..., 0] if single else out


def binary_dilate(m, r):
    """Disc dilation via blur+threshold (r in px)."""
    if r <= 0:
        return m.copy()
    return gaussian(m.astype(np.float32), r * 0.85) > 0.12


def binary_erode(m, r):
    return ~binary_dilate(~m, r)


def label_largest(mask):
    """Largest 4-connected component of a bool mask, without scipy."""
    h, w = mask.shape
    lab = np.zeros((h, w), np.int32)
    cur = 0
    best = (0, 0)
    idx = np.argwhere(mask)
    seen = mask.copy()
    for y0, x0 in idx:
        if not seen[y0, x0]:
            continue
        cur += 1
        stack = [(y0, x0)]
        seen[y0, x0] = False
        n = 0
        while stack:
            y, x = stack.pop()
            lab[y, x] = cur
            n += 1
            if y > 0 and seen[y - 1, x]:
                seen[y - 1, x] = False
                stack.append((y - 1, x))
            if y < h - 1 and seen[y + 1, x]:
                seen[y + 1, x] = False
                stack.append((y + 1, x))
            if x > 0 and seen[y, x - 1]:
                seen[y, x - 1] = False
                stack.append((y, x - 1))
            if x < w - 1 and seen[y, x + 1]:
                seen[y, x + 1] = False
                stack.append((y, x + 1))
        if n > best[1]:
            best = (cur, n)
    return lab == best[0]


def flood_outside(blocked):
    """True where reachable from the border without crossing `blocked`."""
    h, w = blocked.shape
    free = ~blocked
    out = np.zeros((h, w), bool)
    stack = []
    for x in range(w):
        for y in (0, h - 1):
            if free[y, x] and not out[y, x]:
                out[y, x] = True
                stack.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if free[y, x] and not out[y, x]:
                out[y, x] = True
                stack.append((y, x))
    while stack:
        y, x = stack.pop()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and free[ny, nx] and not out[ny, nx]:
                out[ny, nx] = True
                stack.append((ny, nx))
    return out


def pullpush(img, w):
    """Multi-scale weighted inpaint. img HxWxC float, w HxW float in [0,1]."""
    vals = [img * w[..., None]]
    wts = [w.astype(np.float32)]
    # reduce each axis independently all the way down to 1x1, otherwise a level
    # can still contain zero-weight cells and those decode as black
    while wts[-1].shape[0] > 1 or wts[-1].shape[1] > 1:
        v, ww = vals[-1], wts[-1]
        h, wd = ww.shape
        sy, sx = (2 if h > 1 else 1), (2 if wd > 1 else 1)
        ph, pw = (-h) % sy, (-wd) % sx
        if ph or pw:
            v = np.pad(v, ((0, ph), (0, pw), (0, 0)))
            ww = np.pad(ww, ((0, ph), (0, pw)))
            h, wd = ww.shape
        v = v.reshape(h // sy, sy, wd // sx, sx, v.shape[2]).sum((1, 3))
        ww = ww.reshape(h // sy, sy, wd // sx, sx).sum((1, 3))
        vals.append(v)
        wts.append(ww)
    filled = None
    for lvl in range(len(vals) - 1, -1, -1):
        v, ww = vals[lvl], wts[lvl]
        safe = np.maximum(ww, 1e-8)[..., None]
        here = v / safe
        a = np.clip(ww, 0.0, 1.0)[..., None]
        if filled is None:
            filled = here
        else:
            up = resize_f(filled, (ww.shape[1], ww.shape[0]), Image.BILINEAR)
            filled = a * here + (1.0 - a) * up
    return filled[:img.shape[0], :img.shape[1]]


def min_enclosing_circle(pts, iters=4000):
    """Badoiu-Clarkson approximation; deterministic given pts order."""
    c = pts.mean(0)
    for i in range(1, iters + 1):
        d = pts - c
        far = pts[np.argmax((d * d).sum(1))]
        c = c + (far - c) / (i + 1)
    r = np.sqrt(((pts - c) ** 2).sum(1)).max()
    return c, r


def rounded_mask(size, radius, ss=4):
    """Antialiased rounded-square alpha in [0,1], float, (h=w=size)."""
    n = size * ss
    r = radius * ss
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) + 0.5
    dx = np.maximum(np.maximum(r - xx, xx - (n - r)), 0)
    dy = np.maximum(np.maximum(r - yy, yy - (n - r)), 0)
    inside = (np.hypot(dx, dy) <= r).astype(np.float32)
    return inside.reshape(size, ss, size, ss).mean((1, 3))


def dither_to_u8(f, seed=DITHER_SEED):
    """Triangular-noise dither then quantise: kills gradient banding."""
    rng = np.random.default_rng(seed)
    n = rng.random(f.shape) - rng.random(f.shape)   # triangular in (-1,1)
    return np.clip(np.rint(f + n * 0.75), 0, 255).astype(np.uint8)


def save_rgba(arr_rgb_u8, alpha_u8, path):
    im = Image.fromarray(np.dstack([arr_rgb_u8, alpha_u8]), "RGBA")
    im.save(path, optimize=True)
    return im


def radius_map(size):
    """Distance of every pixel from the canvas centre."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    return np.hypot(yy - (size - 1) / 2.0, xx - (size - 1) / 2.0)


# ----------------------------------------------------------------------------
def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    src_path = args[0] if args else os.path.join(root, "design", "branding",
                                                 "app-icon-master.png")
    out_dir = args[1] if len(args) > 1 else os.path.join(root, "assets", "branding")
    preview_dir = None
    if "--preview" in sys.argv:
        preview_dir = sys.argv[sys.argv.index("--preview") + 1]
        os.makedirs(preview_dir, exist_ok=True)
    os.makedirs(out_dir, exist_ok=True)
    P = lambda n: os.path.join(out_dir, n)
    report = {}

    src = Image.open(src_path).convert("RGBA")
    S = np.asarray(src).astype(np.float32)
    A = S[..., 3]

    # -- 1. trim to the artwork tile (alpha >= 8; alpha>0 is dust-contaminated)
    ys, xs = np.where(A >= 8)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    tile = S[y0:y1, x0:x1]                       # 778 x 735 RGBA float
    th, tw = tile.shape[:2]
    trgb, ta = tile[..., :3], tile[..., 3]
    report["tile_wh"] = [int(tw), int(th)]

    # -- 2. isolate the character -------------------------------------------
    lum = 0.2126 * trgb[..., 0] + 0.7152 * trgb[..., 1] + 0.0722 * trgb[..., 2]
    dark = (lum < 90) & (ta > 200)
    dark = binary_erode(binary_dilate(dark, 2.5), 2.5)      # morphological close
    outline = label_largest(dark)
    char = ~flood_outside(outline) | outline
    char = binary_erode(binary_dilate(char, 3.0), 3.0)      # fill pinholes
    report["char_area_px"] = int(char.sum())

    # -- 3. smooth gradient field -------------------------------------------
    solid = ta >= 250
    interior = binary_erode(solid, 12.0)

    # (a) POLAR prior. The measured artwork is an angular (conic) hue sweep,
    #     not a linear or bilinear gradient, so model it in (theta, t) polar
    #     coordinates normalised by the rounded-rect boundary. The character
    #     hole is contiguous in t (small radii) while every theta still has
    #     valid samples near the rim, which makes the fill an extrapolation
    #     along rays instead of a hue smear across the tile.
    cx0, cy0 = (tw - 1) / 2.0, (th - 1) / 2.0
    ax, by = tw / 2.0, th / 2.0
    R = 165.0 * tw / 776.0

    def sdf(px, py):
        """Signed distance to the rounded rectangle (negative = inside)."""
        qx = np.abs(px) - (ax - R)
        qy = np.abs(py) - (by - R)
        return (np.hypot(np.maximum(qx, 0), np.maximum(qy, 0))
                + np.minimum(np.maximum(qx, qy), 0) - R)

    NT, NA = 24, 360
    ang = (np.arange(NA) + 0.5) / NA * 2 * np.pi
    lo = np.zeros(NA)
    hi = np.full(NA, max(ax, by) * 1.6)
    for _ in range(40):                      # bisect the boundary along each ray
        mid = (lo + hi) / 2
        inside = sdf(mid * np.cos(ang), mid * np.sin(ang)) < 0
        lo = np.where(inside, mid, lo)
        hi = np.where(inside, hi, mid)
    r_edge = (lo + hi) / 2

    yy_t, xx_t = np.mgrid[0:th, 0:tw].astype(np.float32)
    dxp, dyp = xx_t - cx0, yy_t - cy0
    theta = np.mod(np.arctan2(dyp, dxp), 2 * np.pi)
    ai = np.clip((theta / (2 * np.pi) * NA - 0.5).astype(np.int32), 0, NA - 1)
    rad_t = np.hypot(dxp, dyp)
    tt = rad_t / np.maximum(r_edge[ai], 1e-6)
    ti = np.clip((tt * NT).astype(np.int32), 0, NT - 1)

    # Valid background samples: opaque tile, away from the character AND its
    # painted cast shadow, and inside t<=0.90 -- the outer 10 % of every ray is
    # the tile's own rim / bottom bevel, which is art, not gradient.
    valid = interior & ~binary_dilate(char, 20.0) & (tt <= 0.90)
    report["gradient_valid_frac"] = round(float(valid.mean()), 4)

    acc = np.zeros((NT, NA, 3), np.float64)
    cnt = np.zeros((NT, NA), np.float64)
    np.add.at(acc, (ti[valid], ai[valid]), trgb[valid])
    np.add.at(cnt, (ti[valid], ai[valid]), 1.0)
    tab = np.zeros_like(acc, np.float32)
    nz = cnt > 0
    tab[nz] = (acc[nz] / cnt[nz, None]).astype(np.float32)
    # inpaint the polar table, wrapping in theta (tile it 3x, keep the middle)
    tab3 = np.concatenate([tab] * 3, axis=1)
    w3 = np.concatenate([nz.astype(np.float32)] * 3, axis=1)
    tab3 = pullpush(tab3, w3)
    tab = gaussian(tab3, 2.0)[:, NA:2 * NA]

    # bilinear sample of the table back into image space
    fa = np.clip(tt * NT - 0.5, 0, NT - 1)
    f0 = np.floor(fa).astype(np.int32)
    f1 = np.clip(f0 + 1, 0, NT - 1)
    fw = (fa - f0)[..., None]
    ga = theta / (2 * np.pi) * NA - 0.5
    g0 = np.mod(np.floor(ga).astype(np.int32), NA)
    g1 = np.mod(g0 + 1, NA)
    gw = (ga - np.floor(ga))[..., None]
    poly = ((tab[f0, g0] * (1 - gw) + tab[f0, g1] * gw) * (1 - fw) +
            (tab[f1, g0] * (1 - gw) + tab[f1, g1] * gw) * fw)
    poly = gaussian(poly, 8.0)

    # (b) diffusion inpaint of the real data. This is faithful everywhere the
    #     hole is thin (the rounded corners, the rim) but smears hue across the
    #     wide character hole, so blend it towards the polar model as a function
    #     of depth inside that hole only.
    diffused = pullpush(trgb, valid.astype(np.float32))
    charD = binary_dilate(char, 6.0)
    depth = gaussian((~charD).astype(np.float32), 45.0)
    conf = np.where(charD, np.clip(depth * 1.8, 0, 1), 1.0).astype(np.float32)
    field = gaussian(diffused * conf[..., None] +
                     poly * (1 - conf)[..., None], 26.0)

    # Every ray converges at the polar origin, so the innermost t-bin averages
    # all 360 hues into a desaturated knot. It is hidden behind the character at
    # rest, but launcher parallax can slide it into view, so replace the core
    # with a heavily smoothed copy of its own surroundings.
    core = np.clip((60.0 - rad_t) / 40.0, 0, 1)[..., None]
    field = field * (1 - core) + gaussian(field, 70.0) * core
    report["conic_core_px"] = int((core[..., 0] > 0).sum())

    # -- 4. adaptive background (full bleed, opaque) -------------------------
    g = resize_f(field, (BG_TILE, BG_TILE))
    off = (ICON - BG_TILE) // 2
    yy, xx = np.mgrid[0:ICON, 0:ICON]
    sy = np.clip(yy - off, 0, BG_TILE - 1)
    sx = np.clip(xx - off, 0, BG_TILE - 1)
    bg = g[sy, sx]                                 # clamp-extended
    # progressive blur outside the gradient tile so the extension reads as haze
    outside = ((yy < off) | (yy >= off + BG_TILE) |
               (xx < off) | (xx >= off + BG_TILE)).astype(np.float32)
    dist = np.maximum.reduce([off - yy, yy - (off + BG_TILE - 1),
                              off - xx, xx - (off + BG_TILE - 1)])
    ramp = np.clip(dist / float(off), 0, 1) * outside
    bg = bg * (1 - ramp[..., None]) + gaussian(bg, 12.0) * ramp[..., None]
    # Ships at 432 px: it is a smooth gradient, and 432 is exactly what the
    # largest density bucket (xxxhdpi) asks for -- 1024 would be 15x the bytes
    # for nothing. The full-res copy stays in memory for the legacy icon.
    bg_out = dither_to_u8(resize_f(bg, (BG_OUT, BG_OUT)))
    Image.fromarray(bg_out, "RGB").save(P("adaptive_background.png"), optimize=True)

    # -- 5. character cutout -------------------------------------------------
    a = gaussian(char.astype(np.float32), 1.0)
    calpha = np.clip((a - 0.50) / 0.30, 0, 1)      # ~1 px erode + 1 px feather
    # bleed the character's own colours outward so the feathered rim can never
    # pick up background gradient  (premultiply-safe)
    crgb = pullpush(trgb, (calpha > 0.9).astype(np.float32))
    pts = np.argwhere(calpha > 0.5)[:, ::-1].astype(np.float32)  # (x, y)
    ccen, crad = min_enclosing_circle(pts)

    def place_character(circle_d, fade=None, alpha_override=None, shadow=True):
        """Character scaled to `circle_d` (min-enclosing circle) on the ICON
        canvas, plus its synthesised shadow. `fade` ramps the shadow to zero
        between two radii so a circular mask never cuts it."""
        scale = (circle_d / 2.0) / crad
        nw, nh = int(round(tw * scale)), int(round(th * scale))
        src_a = calpha if alpha_override is None else alpha_override
        fr = resize_f(crgb, (nw, nh))
        fa_r = np.clip(resize_f(src_a, (nw, nh)), 0, 1)
        cx, cy = ccen[0] * scale, ccen[1] * scale

        fg_rgb = np.zeros((ICON, ICON, 3), np.float32)
        fg_a = np.zeros((ICON, ICON), np.float32)
        px, py = int(round(ICON / 2 - cx)), int(round(ICON / 2 - cy))
        sx0, sy0 = max(0, -px), max(0, -py)
        dx0, dy0 = max(0, px), max(0, py)
        ww = min(nw - sx0, ICON - dx0)
        hh = min(nh - sy0, ICON - dy0)
        fg_rgb[dy0:dy0 + hh, dx0:dx0 + ww] = fr[sy0:sy0 + hh, sx0:sx0 + ww]
        fg_a[dy0:dy0 + hh, dx0:dx0 + ww] = fa_r[sy0:sy0 + hh, sx0:sx0 + ww]

        # synthesised soft drop shadow (the original's painted shadow lives on
        # the gradient and cannot travel with the cutout; a fresh one also
        # stays correct under Android's foreground parallax)
        k = circle_d / float(SAFE)
        sh = np.zeros_like(fg_a)
        dy_sh = int(round(14 * k))
        sh[dy_sh:, :] = fg_a[:ICON - dy_sh, :]
        sh = gaussian(sh, 16.0 * k) * 0.34
        sh = np.clip(sh - fg_a, 0, 1)              # keep it strictly outside
        if not shadow:
            sh *= 0.0
        if fade is not None:
            r0, r1 = fade
            sh *= np.clip((r1 - radius_map(ICON)) / (r1 - r0), 0, 1)

        out_a = np.clip(fg_a + sh * (1 - fg_a), 0, 1)
        den = np.maximum(out_a, 1e-6)[..., None]
        out_rgb = (fg_rgb * fg_a[..., None] +
                   np.array([9, 24, 61], np.float32) *
                   (sh * (1 - fg_a))[..., None]) / den
        return out_rgb, out_a, fg_a

    fg_rgb, fg_a, solid_a = place_character(FG_CIRCLE_D, fade=SHADOW_FADE)
    save_rgba(dither_to_u8(fg_rgb), np.rint(fg_a * 255).astype(np.uint8),
              P("icon_foreground.png"))
    rr = radius_map(ICON)
    report["char_max_r"] = round(float(rr[solid_a * 255 >= 8].max()), 1)
    report["char_outside_66dp"] = int(((solid_a * 255 >= 8) & (rr > 66 * DP / 2)).sum())
    report["shadow_max_r"] = round(float(rr[fg_a * 255 >= 8].max()), 1)
    report["fg_outside_72dp"] = int(((fg_a * 255 >= 8) & (rr > 72 * DP / 2)).sum())
    # parallax check: the launcher can slide the layers +/-4dp against each
    # other -- the reconstructed core must stay hidden the whole way
    worst = 1.0
    for dx in (-38, 0, 38):
        for dy in (-38, 0, 38):
            sl = np.roll(np.roll(fg_a, dy, 0), dx, 1)[460:560, 460:580]
            worst = min(worst, float(sl.min()))
    report["core_cover_alpha_parallax"] = round(worst, 3)

    # -- 6. monochrome layer (Android 13+ themed icons) ----------------------
    # Flat white silhouette with the artwork's *interior* line work knocked out
    # (eyes, mouth, the bubble/sticker seam, the pencil) so the mark still reads
    # as the character and not as a blob. The outline that bounds the silhouette
    # is excluded from the knockout, otherwise the shape falls apart. No drop
    # shadow here: the themed icon tints the whole alpha channel with one
    # colour, so a soft shadow would come back as a grey haze.
    inner_ink = dark & binary_erode(char, 11.0)
    ink = np.clip(gaussian(inner_ink.astype(np.float32), 1.0) * 1.6, 0, 1)
    mono_alpha = np.clip(calpha - ink, 0, 1)
    _, mono_a, _ = place_character(FG_CIRCLE_D, alpha_override=mono_alpha,
                                   shadow=False)
    save_rgba(np.full((ICON, ICON, 3), 255, np.uint8),
              np.rint(mono_a * 255).astype(np.uint8), P("icon_monochrome.png"))

    # -- 7. legacy square icon ----------------------------------------------
    # Exactly the two adaptive layers composited: full-bleed reconstructed
    # gradient + the character at the master's own relative scale. Compositing
    # the *original tile* over the gradient instead would re-introduce the
    # tile's rim highlight as a ghost rounded-rect seam.
    lh = int(round(th * ICON / tw))
    gl = resize_f(field, (ICON, lh))
    rows = np.clip(np.mgrid[0:ICON, 0:ICON][0] - (ICON - lh) // 2, 0, lh - 1)
    base = gl[rows, np.mgrid[0:ICON, 0:ICON][1]]
    lrgb, la, _ = place_character(2.0 * crad * ICON / tw)
    can = lrgb * la[..., None] + base * (1 - la[..., None])
    # 512 px is the Play Console listing size and 2.6x the largest legacy
    # mipmap (192), so nothing downstream wants more than that.
    Image.fromarray(dither_to_u8(resize_f(can, (LEGACY, LEGACY))),
                    "RGB").save(P("icon.png"), optimize=True)

    # -- 8. splash artwork (transparent, master tile) ------------------------
    def tile_on_canvas(canvas, tile_w):
        h2 = int(round(th * tile_w / tw))
        rr2 = resize_f(trgb, (tile_w, h2))
        aa = np.clip(resize_f(ta, (tile_w, h2)), 0, 255)
        cr = np.zeros((canvas, canvas, 3), np.float32)
        ca = np.zeros((canvas, canvas), np.float32)
        ox, oy2 = (canvas - tile_w) // 2, (canvas - h2) // 2
        cr[oy2:oy2 + h2, ox:ox + tile_w] = rr2
        ca[oy2:oy2 + h2, ox:ox + tile_w] = aa
        return cr, ca

    # These three keep the master's own pixels rather than the reconstructed
    # field, so they are NOT dithered: the artwork is already textured, the
    # LANCZOS downscale breaks up what little banding it has, and the noise
    # would roughly double the PNG. (Palettising was tested and rejected — 255
    # colours visibly posterise the gradient.)
    def save_tile(canvas, tile_w, name):
        cr, ca = tile_on_canvas(canvas, tile_w)
        save_rgba(np.clip(np.rint(cr), 0, 255).astype(np.uint8),
                  np.rint(ca).astype(np.uint8), P(name))

    save_tile(512, 500, "splash.png")
    # The Android 12+ splash icon is a 1152 px canvas whose visible area is only
    # the centre 768 px circle, so the tile has to be much smaller relative to
    # it than in the legacy splash: at 610 px its farthest painted point sits at
    # r = 377, seven pixels inside the 384 px mask.
    save_tile(1152, 610, "splash_android12.png")
    # 192 px covers up to 64 dp at 3x density, which is all the in-app mark
    # needs; anything bigger should render the icon layers instead.
    save_tile(192, 190, "logo.png")

    # -- 10. optional contrast sheet (never written into assets/) ------------
    if preview_dir:
        full = Image.alpha_composite(
            Image.fromarray(dither_to_u8(bg), "RGB").convert("RGBA"),
            Image.open(P("icon_foreground.png")).convert("RGBA"))
        crop = full.crop(((ICON - VIS) // 2, (ICON - VIS) // 2,
                          (ICON + VIS) // 2,
                          (ICON + VIS) // 2)).resize((360, 360), Image.LANCZOS)
        yy2, xx2 = np.mgrid[0:360 * 4, 0:360 * 4] + 0.5
        circle = ((np.hypot(yy2 - 720, xx2 - 720) <= 720).astype(np.float32)
                  .reshape(360, 4, 360, 4).mean((1, 3)))
        sheet = Image.new("RGB", (1200, 460), (0x80, 0x80, 0x80))
        sheet.paste(Image.new("RGB", (1200, 230), (0xED, 0xED, 0xED)), (0, 0))
        for i, m in enumerate([circle, rounded_mask(360, 72),
                               np.ones((360, 360), np.float32)]):
            x, y = 20 + i * 400, 50
            c8 = np.array(crop.convert("RGB"), np.float32)
            base_s = np.array(sheet.crop((x, y, x + 360, y + 360)), np.float32)
            comp = c8 * m[..., None] + base_s * (1 - m[..., None])
            sheet.paste(Image.fromarray(np.clip(comp, 0, 255).astype(np.uint8)),
                        (x, y))
        sheet.save(os.path.join(preview_dir, "preview.png"), optimize=True)

    for k, v in report.items():
        print(f"{k}: {v}")
    total = 0
    for n in sorted(os.listdir(out_dir)):
        b = os.path.getsize(os.path.join(out_dir, n))
        total += b
        print(f"  {n:26s} {b:>9,d} B")
    print(f"  {'TOTAL':26s} {total:>9,d} B")


if __name__ == "__main__":
    main()
