#!/usr/bin/env python3
"""Regenerate website/assets/img/og-card.png - the 1200x630 social card.

    pip install pillow numpy
    python website/tools/build_og_card.py            # writes website/assets/img/
    python website/tools/build_og_card.py <out dir>

Deterministic and re-runnable: the only randomness is a fixed-seed dither.
Requires Pillow + numpy only (no ImageMagick, no network, no CDN fonts).

Inputs, all already in the repo - this script draws nothing by hand:

    assets/branding/icon.png             512 px app icon (from build_branding.py)
    assets/branding/icon_foreground.png  1024 px character-only adaptive layer
    assets/fonts/Fredoka-Variable.ttf    headings   (SIL OFL)
    assets/fonts/Bangers-Regular.ttf     tagline    (SIL OFL)

Layout - a two-column card on a 1200 x 630 Open Graph canvas
------------------------------------------------------------
Left column (x = 84 .. ~700), stacked:

    app icon            128 px square at (84, 122)
    "Sticker Maker"     Fredoka SemiBold 92 px, --text  #efeaf4
    "Make it stick."    Bangers 58 px,          --violet-brt #c4b5fd
    strap line          Fredoka Medium 26 px,   --muted #8b8399

Right column: a 356 px rounded checkerboard patch centred vertically, carrying a
white die-cut sticker. The sticker is not artwork of its own - it is the app's
own character layer, alpha-thresholded to drop the layer's synthesised drop
shadow, dilated to make the white border, then composited back on top. That is
the literal output of the product (subject lifted off its background, die-cut,
sitting on transparency), which is what the card has to communicate.

Background: flat --bg #131019, plus the app's #7c5cff -> #b06bff -> #f472b6
gradient used twice - once as two wide, soft radial glows (behind the icon and
behind the sticker patch) at low alpha, and once at full strength as the 6 px
bar along the top edge. The glow is dithered before 8-bit quantisation: a
gradient this wide over a near-black field bands visibly, and social platforms
re-encode the card, which amplifies banding rather than hiding it.
"""

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# ----------------------------------------------------------------------------
# constants
# ----------------------------------------------------------------------------
W, H = 1200, 630                  # the Open Graph card size, fixed by spec
MARGIN = 84

BG = (0x13, 0x10, 0x19)           # --bg
TEXT = (0xEF, 0xEA, 0xF4)         # --text
MUTED = (0x8B, 0x83, 0x99)        # --muted
VIOLET_BRT = (0xC4, 0xB5, 0xFD)   # --violet-brt
LINE = (0x2F, 0x2A, 0x3B)         # --line

# hero gradient stops: --violet-deep -> mid -> --pink
STOPS = [(0x7C, 0x5C, 0xFF), (0xB0, 0x6B, 0xFF), (0xF4, 0x72, 0xB6)]
GRAD_ANGLE_DEG = 18.0             # sweeps left->right, tilted down slightly

TOP_BAR = 6                       # full-strength gradient rule along the top
GLOW_A = 0.34                     # peak glow alpha over the flat background
GLOW_GAMMA = 1.9                  # steepens the falloff so the corners stay --bg
GLOWS = [((250, 210), 300.0, 1.00),    # behind the icon / wordmark
         ((955, 320), 260.0, 0.90)]    # behind the sticker patch

ICON_PX = 128
ICON_XY = (MARGIN, 122)
WORD_SIZE, WORD_Y = 92, 292       # "Sticker Maker"   (top-left anchored)
TAG_SIZE, TAG_Y = 58, 404         # "Make it stick."
STRAP_SIZE, STRAP_Y = 26, 486     # strap line

WORDMARK = "Sticker Maker"
TAGLINE = "Make it stick."
STRAP = "On-device background removal"

PATCH = 356                       # checkerboard patch, square
PATCH_XY = ((W - MARGIN - PATCH), (H - PATCH) // 2)
PATCH_RADIUS = 28
CHECK_CELL = 22
CHECK_A = (0x24, 0x1F, 0x30)      # checkerboard, deliberately on-brand dark
CHECK_B = (0x1C, 0x18, 0x26)      # (--surface) rather than the classic white

STICKER_BOX = 262                 # sticker fits inside this square on the patch
DIE_CUT = 13                      # white die-cut border half-width, px
CHAR_ALPHA_LO = 150               # icon_foreground alpha below this is shadow:
CHAR_ALPHA_HI = 210               # the synthesised shadow peaks at 0.34*255=87

SS = 4                            # supersampling for the rounded-rect masks
DITHER_SEED = 20260720


# ----------------------------------------------------------------------------
# small helpers
# ----------------------------------------------------------------------------
def rounded_rect_mask(w, h, radius, ss=SS):
    """Antialiased rounded-rectangle coverage in [0,1], float, shape (h, w)."""
    m = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        (0, 0, w * ss - 1, h * ss - 1), radius=radius * ss, fill=255)
    return (np.asarray(m, np.float32).reshape(h, ss, w, ss).mean((1, 3)) / 255.0)


def dither_to_u8(f, seed=DITHER_SEED):
    """Triangular-noise dither then quantise: kills gradient banding."""
    rng = np.random.default_rng(seed)
    n = rng.random(f.shape) - rng.random(f.shape)      # triangular in (-1, 1)
    return np.clip(np.rint(f + n * 0.75), 0, 255).astype(np.uint8)


def gradient_field(w, h, angle_deg=GRAD_ANGLE_DEG):
    """The 3-stop hero gradient projected onto `angle_deg`, as float (h, w, 3)."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    a = np.radians(angle_deg)
    t = xx * np.cos(a) + yy * np.sin(a)
    t = (t - t.min()) / (t.max() - t.min())            # 0..1 along the sweep
    s = np.array(STOPS, np.float32)
    k = np.clip(t * 2.0, 0, 2.0)                       # 2 segments, 3 stops
    i = np.clip(np.floor(k), 0, 1).astype(np.int32)
    f = (k - i)[..., None]
    return s[i] * (1 - f) + s[i + 1] * f


def glow_field(w, h):
    """Sum of the soft radial glows, clipped to [0,1], float (h, w)."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    g = np.zeros((h, w), np.float32)
    for (cx, cy), sigma, amp in GLOWS:
        d2 = (xx - cx) ** 2 + (yy - cy) ** 2
        g += amp * np.exp(-d2 / (2.0 * sigma * sigma))
    return np.clip(g, 0.0, 1.0) ** GLOW_GAMMA


def fredoka(path, size, instance):
    f = ImageFont.truetype(path, size)
    f.set_variation_by_name(instance)                  # default axis is Light
    return f


def die_cut_sticker(fg_path, box):
    """The app's character as a white die-cut sticker, RGBA `box` x `box`.

    icon_foreground.png carries a synthesised drop shadow in its alpha, so the
    shape is taken from a hard threshold (shadow peaks well under CHAR_ALPHA_LO)
    and the soft rim is recovered by ramping between LO and HI. The white border
    is that shape dilated by DIE_CUT via a max filter on a supersampled copy,
    which keeps the corners round instead of chamfered.
    """
    src = Image.open(fg_path).convert("RGBA")
    a = np.asarray(src, np.float32)[..., 3]
    hard = (a >= CHAR_ALPHA_HI)
    ys, xs = np.where(hard)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1

    soft = np.clip((a - CHAR_ALPHA_LO) / float(CHAR_ALPHA_HI - CHAR_ALPHA_LO),
                   0, 1)[y0:y1, x0:x1]
    rgb = np.asarray(src, np.uint8)[y0:y1, x0:x1, :3]

    # fit the character (not its border) inside box - 2*DIE_CUT
    inner = box - 2 * DIE_CUT
    ch, cw = soft.shape
    scale = inner / float(max(cw, ch))
    nw, nh = max(1, int(round(cw * scale))), max(1, int(round(ch * scale)))
    char_a = Image.fromarray(np.rint(soft * 255).astype(np.uint8), "L") \
        .resize((nw, nh), Image.LANCZOS)
    char_rgb = Image.fromarray(rgb, "RGB").resize((nw, nh), Image.LANCZOS)

    # white border = dilation of the character alpha by DIE_CUT px
    pad = DIE_CUT + 2
    big = Image.new("L", (nw + 2 * pad, nh + 2 * pad), 0)
    big.paste(char_a, (pad, pad))
    d = np.asarray(big, np.float32)
    r = DIE_CUT
    yy, xx = np.mgrid[-r:r + 1, -r:r + 1]
    disc = (xx * xx + yy * yy) <= r * r
    # separable-enough max dilation: rows then columns of the disc's bounding
    # offsets, restricted to the disc, done with np.maximum over the offsets
    out = np.zeros_like(d)
    for dy, dx in zip(*np.where(disc)):
        oy, ox = int(dy) - r, int(dx) - r
        out = np.maximum(out, np.roll(np.roll(d, oy, 0), ox, 1))
    border = Image.fromarray(np.clip(np.rint(out), 0, 255).astype(np.uint8), "L")

    # white plate cut to the dilated shape, then the character over it
    card = Image.new("RGBA", big.size, (255, 255, 255, 0))
    card.paste((255, 255, 255, 255), (0, 0), border)
    card.paste(char_rgb, (pad, pad), char_a)

    canvas = Image.new("RGBA", (box, box), (255, 255, 255, 0))
    canvas.paste(card, ((box - card.width) // 2, (box - card.height) // 2), card)
    return canvas


# ----------------------------------------------------------------------------
def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    here = os.path.dirname(os.path.abspath(__file__))
    site = os.path.dirname(here)                       # website/
    root = os.path.dirname(site)                       # repo root
    out_dir = args[0] if args else os.path.join(site, "assets", "img")
    os.makedirs(out_dir, exist_ok=True)

    brand = os.path.join(root, "assets", "branding")
    fonts = os.path.join(root, "assets", "fonts")
    icon_path = os.path.join(brand, "icon.png")
    fg_path = os.path.join(brand, "icon_foreground.png")
    fredoka_path = os.path.join(fonts, "Fredoka-Variable.ttf")
    bangers_path = os.path.join(fonts, "Bangers-Regular.ttf")
    for p in (icon_path, fg_path, fredoka_path, bangers_path):
        if not os.path.exists(p):
            print("missing input: %s" % p)
            return 2
    report = {}

    # -- 1. background: flat --bg, the hero gradient masked by the soft glows --
    grad = gradient_field(W, H)
    glow = glow_field(W, H)
    base = np.empty((H, W, 3), np.float32)
    base[:] = np.array(BG, np.float32)
    a = (glow * GLOW_A)[..., None]
    field = base * (1 - a) + grad * a

    # full-strength gradient rule along the top edge
    field[:TOP_BAR] = grad[:TOP_BAR]
    report["glow_peak_alpha"] = round(float(a.max()), 3)

    card = Image.fromarray(dither_to_u8(field), "RGB").convert("RGBA")

    # -- 2. checkerboard patch, rounded and hairlined ------------------------
    yy, xx = np.mgrid[0:PATCH, 0:PATCH]
    cb = np.where((((yy // CHECK_CELL) + (xx // CHECK_CELL)) % 2)[..., None] == 0,
                  np.array(CHECK_A, np.float32), np.array(CHECK_B, np.float32))
    pm = rounded_rect_mask(PATCH, PATCH, PATCH_RADIUS)
    # 1 px --line hairline: the rounded mask minus a 1 px inset of itself
    inner = np.zeros_like(pm)
    inner[1:-1, 1:-1] = rounded_rect_mask(PATCH - 2, PATCH - 2, PATCH_RADIUS - 1)
    ring = np.clip(pm - inner, 0, 1)
    cb = cb * (1 - ring[..., None]) + np.array(LINE, np.float32) * ring[..., None]
    patch = Image.fromarray(np.clip(np.rint(cb), 0, 255).astype(np.uint8), "RGB") \
        .convert("RGBA")
    patch.putalpha(Image.fromarray(np.rint(pm * 255).astype(np.uint8), "L"))
    card.alpha_composite(patch, PATCH_XY)

    # -- 3. the die-cut sticker on the patch ---------------------------------
    sticker = die_cut_sticker(fg_path, STICKER_BOX)
    card.alpha_composite(sticker, (PATCH_XY[0] + (PATCH - STICKER_BOX) // 2,
                                   PATCH_XY[1] + (PATCH - STICKER_BOX) // 2))
    report["sticker_box_px"] = STICKER_BOX

    # -- 4. app icon, rounded to match the launcher mask ---------------------
    icon = Image.open(icon_path).convert("RGBA").resize(
        (ICON_PX, ICON_PX), Image.LANCZOS)
    im = rounded_rect_mask(ICON_PX, ICON_PX, int(round(ICON_PX * 0.235)))
    icon.putalpha(Image.fromarray(np.rint(im * 255).astype(np.uint8), "L"))
    card.alpha_composite(icon, ICON_XY)

    # -- 5. type -------------------------------------------------------------
    d = ImageDraw.Draw(card)
    f_word = fredoka(fredoka_path, WORD_SIZE, "SemiBold")
    f_tag = ImageFont.truetype(bangers_path, TAG_SIZE)
    f_strap = fredoka(fredoka_path, STRAP_SIZE, "Medium")

    d.text((MARGIN, WORD_Y), WORDMARK, font=f_word, fill=TEXT, anchor="lt")
    d.text((MARGIN, TAG_Y), TAGLINE, font=f_tag, fill=VIOLET_BRT, anchor="lt")
    d.text((MARGIN, STRAP_Y), STRAP, font=f_strap, fill=MUTED, anchor="lt")
    report["wordmark_w"] = int(d.textlength(WORDMARK, font=f_word))
    report["tagline_w"] = int(d.textlength(TAGLINE, font=f_tag))
    report["text_right_edge"] = max(report["wordmark_w"], report["tagline_w"]) + MARGIN
    report["patch_left_edge"] = PATCH_XY[0]

    # -- 6. write ------------------------------------------------------------
    # RGB, not RGBA: the card is opaque edge to edge, and some social scrapers
    # flatten an alpha channel against white rather than against the post.
    path = os.path.join(out_dir, "og-card.png")
    card.convert("RGB").save(path, optimize=True)
    chk = Image.open(path)
    report["out"] = "%s %sx%s %s" % (os.path.basename(path), chk.size[0],
                                     chk.size[1], chk.mode)
    report["bytes"] = os.path.getsize(path)
    for k, v in report.items():
        print(f"{k}: {v}")
    assert chk.size == (W, H), "og card must be exactly %dx%d" % (W, H)
    return 0


if __name__ == "__main__":
    sys.exit(main())
