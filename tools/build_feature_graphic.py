"""Build the Google Play feature graphic (1024x500) from real app material.

Play's spec for this asset:
  - exactly 1024 x 500 px
  - JPEG or 24-bit PNG, **no alpha** (a transparent asset shows the Play UI
    background through it)
  - keep meaning away from the edges: the graphic is cropped to different
    aspect ratios across Play surfaces

Source material is the maintainer's own: a sticker exported from the app
(dog cut-out + "WOOF!" + a speech bubble) and the app icon. The sticker was
screenshotted against black rather than saved with alpha, so the alpha is
recovered here by flood-filling the background inwards from the border.

Why a flood fill and not a brightness threshold: the dog is a black husky
mix. Any global "dark == background" rule eats the subject. Filling only from
the border keeps enclosed dark regions (the fur) opaque, because they are not
reachable from outside. Verified: the recovered mask is a clean silhouette.

Run:  python tools/build_feature_graphic.py
Out:  docs/release/store-assets/feature-graphic.png
"""

from __future__ import annotations

from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

REPO = Path(__file__).resolve().parent.parent
STICKER = REPO / "assets/branding/shots/photo_2026-07-20_19-41-41.jpg"
ICON = REPO / "assets/branding/icon.png"
FONT_DISPLAY = REPO / "assets/fonts/Fredoka-Variable.ttf"
FONT_BANGERS = REPO / "assets/fonts/Bangers-Regular.ttf"
FONT_UI = REPO / "assets/fonts/PlusJakartaSans-Variable.ttf"
OUT = REPO / "docs/release/store-assets/feature-graphic.png"

W, H = 1024, 500

# The app's own tokens, so the graphic sits next to the icon without clashing.
BG = (19, 16, 25)
VIOLET_DEEP = (124, 92, 255)
VIOLET_MID = (176, 107, 255)
PINK = (244, 114, 182)
TEXT = (239, 234, 244)
MUTED = (170, 162, 186)

# Background flood-fill tolerance, on the brightest channel. 18 keeps the
# darkest fur (which reads up to ~32) on the subject side of the line.
KEY_TOL = 18
OUTLINE_PX = 9  # the app's die-cut outline, scaled for this canvas


def recover_alpha(img: Image.Image, tol: int = KEY_TOL) -> Image.Image:
    """Alpha for a sticker screenshotted on black, via a border flood fill."""
    lum = np.asarray(img.convert("RGB")).astype(np.int16).max(axis=2)
    h, w = lum.shape
    seen = np.zeros((h, w), bool)
    q: deque[tuple[int, int]] = deque()

    def push(y: int, x: int) -> None:
        if not seen[y, x] and lum[y, x] <= tol:
            seen[y, x] = True
            q.append((y, x))

    for x in range(w):
        push(0, x)
        push(h - 1, x)
    for y in range(h):
        push(y, 0)
        push(y, w - 1)
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w:
                push(ny, nx)

    subject = ~seen
    # The source is a JPEG screenshot and carries a bright one-pixel artifact
    # column at its right edge. The fill cannot cross it, so it survives as
    # "subject" and the die-cut outline then draws a white bar down the whole
    # graphic. Keep only components big enough to be real artwork; the dog, the
    # caption and the bubble are each orders of magnitude larger than the strip.
    return Image.fromarray(_drop_specks(subject, min_frac=0.004), "L")


def _drop_specks(mask: np.ndarray, min_frac: float) -> np.ndarray:
    """Zero out connected components smaller than `min_frac` of the frame."""
    h, w = mask.shape
    min_area = int(h * w * min_frac)
    out = np.zeros((h, w), np.uint8)
    todo = mask.copy()
    kept = []
    for sy in range(h):
        for sx in range(w):
            if not todo[sy, sx]:
                continue
            comp: list[tuple[int, int]] = []
            q = deque([(sy, sx)])
            todo[sy, sx] = False
            while q:
                y, x = q.popleft()
                comp.append((y, x))
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and todo[ny, nx]:
                        todo[ny, nx] = False
                        q.append((ny, nx))
            if len(comp) >= min_area:
                kept.append(len(comp))
                ys, xs = zip(*comp)
                out[np.array(ys), np.array(xs)] = 255
    print(f"  kept {len(kept)} sticker components, areas={sorted(kept, reverse=True)}")
    return out


def die_cut(sticker: Image.Image, width: int = OUTLINE_PX) -> Image.Image:
    """Add the app's signature white outline around an RGBA sticker."""
    pad = width * 2 + 8
    big = Image.new("RGBA", (sticker.width + pad * 2, sticker.height + pad * 2), (0, 0, 0, 0))
    big.paste(sticker, (pad, pad), sticker)
    a = big.getchannel("A")
    # Repeated MaxFilter dilates; a single large kernel would square off corners.
    grown = a
    for _ in range(width):
        grown = grown.filter(ImageFilter.MaxFilter(3))
    grown = grown.filter(ImageFilter.GaussianBlur(0.6)).point(lambda v: 255 if v > 110 else 0)

    out = Image.new("RGBA", big.size, (0, 0, 0, 0))
    white = Image.new("RGBA", big.size, (255, 255, 255, 255))
    out.paste(white, (0, 0), grown)
    out.alpha_composite(big)
    return out


def gradient_backdrop() -> Image.Image:
    """Flat brand base with the hero gradient washed across it."""
    base = Image.new("RGB", (W, H), BG)
    px = np.asarray(base).astype(np.float64)
    ys, xs = np.mgrid[0:H, 0:W]

    def wash(cx, cy, radius, colour, strength):
        d = np.sqrt(((xs - cx) / radius) ** 2 + ((ys - cy) / radius) ** 2)
        k = np.clip(1.0 - d, 0.0, 1.0) ** 2 * strength
        for c in range(3):
            px[:, :, c] += (colour[c] - px[:, :, c]) * k

    wash(W * 0.10, H * 1.05, W * 0.62, VIOLET_DEEP, 0.60)
    wash(W * 0.46, H * -0.10, W * 0.55, VIOLET_MID, 0.34)
    wash(W * 0.92, H * 0.80, W * 0.52, PINK, 0.42)
    return Image.fromarray(np.clip(px, 0, 255).astype(np.uint8), "RGB")


def checker(size: int, cell: int = 16) -> Image.Image:
    """The app's transparency checkerboard, as a faint backing for the sticker."""
    c = Image.new("RGBA", (size, size), (255, 255, 255, 26))
    d = ImageDraw.Draw(c)
    for y in range(0, size, cell):
        for x in range(0, size, cell):
            if (x // cell + y // cell) % 2 == 0:
                d.rectangle([x, y, x + cell - 1, y + cell - 1], fill=(255, 255, 255, 52))
    return c


def font(path: Path, size: int, weight: str | None = None) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(path), size)
    if weight:
        try:
            f.set_variation_by_name(weight)
        except Exception:
            pass  # static face, or no such named instance
    return f


def main() -> None:
    canvas = gradient_backdrop().convert("RGBA")

    # --- hero sticker, right side -------------------------------------------
    raw = Image.open(STICKER).convert("RGB")
    rgba = raw.convert("RGBA")
    rgba.putalpha(recover_alpha(raw))
    bbox = rgba.getchannel("A").getbbox()
    sticker = die_cut(rgba.crop(bbox))

    # Fit inside a box rather than scaling by height alone. The source sticker
    # carries the caption and the bubble out to its own edges, so a
    # height-driven scale pushes the die-cut outline off the canvas and the
    # graphic ends up with a white line down its right edge.
    box_x0, box_y0, box_x1, box_y1 = 516, 34, W - 30, H - 30
    box_w, box_h = box_x1 - box_x0, box_y1 - box_y0
    scale = min(box_w / sticker.width, box_h / sticker.height)
    sticker = sticker.resize(
        (max(1, round(sticker.width * scale)), max(1, round(sticker.height * scale))),
        Image.LANCZOS,
    )
    sx = box_x0 + (box_w - sticker.width) // 2
    sy = box_y0 + (box_h - sticker.height) // 2

    # A faint checkerboard disc behind the sticker reads as "transparent PNG".
    # Kept low-contrast and fully inside the sticker's footprint, so it never
    # looks like a stray grey smudge on the gradient.
    disc = round(min(sticker.width, sticker.height) * 0.92)
    patch = checker(disc, cell=max(10, disc // 22))
    ring = Image.new("L", (disc, disc), 0)
    ImageDraw.Draw(ring).ellipse([0, 0, disc - 1, disc - 1], fill=90)
    patch.putalpha(
        Image.composite(patch.getchannel("A"), Image.new("L", (disc, disc), 0), ring)
        .filter(ImageFilter.GaussianBlur(6))
    )
    canvas.alpha_composite(
        patch,
        (sx + (sticker.width - disc) // 2, sy + (sticker.height - disc) // 2),
    )

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 130), (sx, sy + 10), sticker.getchannel("A"))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(16)))
    canvas.alpha_composite(sticker, (sx, sy))

    # --- wordmark, left ------------------------------------------------------
    d = ImageDraw.Draw(canvas)
    x0 = 64

    icon = Image.open(ICON).convert("RGBA").resize((78, 78), Image.LANCZOS)
    rounded = Image.new("L", icon.size, 0)
    ImageDraw.Draw(rounded).rounded_rectangle([0, 0, 77, 77], radius=22, fill=255)
    canvas.paste(icon, (x0, 118), rounded)

    d.text((x0 + 96, 128), "Sticker", font=font(FONT_DISPLAY, 62, "SemiBold"), fill=TEXT)
    d.text((x0 + 96, 188), "Maker", font=font(FONT_DISPLAY, 62, "SemiBold"), fill=TEXT)
    d.text((x0, 262), "MAKE IT STICK.", font=font(FONT_BANGERS, 54), fill=PINK)
    d.text(
        (x0 + 3, 330),
        "One-tap cut-out, on your phone.",
        font=font(FONT_UI, 23, "Medium"),
        fill=TEXT,
    )
    d.text(
        (x0 + 3, 362),
        "No ads. No subscriptions.",
        font=font(FONT_UI, 23, "Medium"),
        fill=MUTED,
    )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    # Flattened to RGB: Play requires no alpha on this asset.
    canvas.convert("RGB").save(OUT, "PNG", optimize=True)
    check = Image.open(OUT)
    print(f"wrote {OUT.relative_to(REPO).as_posix()}  {check.size}  {check.mode}  "
          f"{OUT.stat().st_size / 1024:.0f} KB")
    assert check.size == (W, H), f"must be {W}x{H}, got {check.size}"
    assert check.mode == "RGB", f"must be RGB (no alpha), got {check.mode}"


if __name__ == "__main__":
    main()
