"""Pad every store screenshot and graphic onto a 1080x1920 brand canvas.

Google Play accepts screenshots between 16:9 and 9:16. The raw captures are
1152x2560 (20:9), which is *outside* that range and would be rejected as-is;
padding them onto a 9:16 canvas both fixes the ratio and gives the set a common
background instead of black bars.

Nothing is cropped or stretched here. Each source is scaled to fit and centred,
so the pixels a reviewer sees are the pixels the app drew.

The backdrop is imported from build_feature_graphic rather than re-tuned, so
the padded set and the feature graphic stay the same family.

Run:  python tools/build_1080x1920.py
Out:  docs/release/store-assets/1080x1920/
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

from build_feature_graphic import gradient_backdrop

REPO = Path(__file__).resolve().parent.parent
SHOTS = REPO / "assets/branding/shots"
FEATURE = REPO / "docs/release/store-assets/feature-graphic.png"
OUT = REPO / "docs/release/store-assets/1080x1920"

W, H = 1080, 1920
MARGIN = 48  # breathing room so nothing touches the canvas edge
SHADOW_PAD = 60

# Source file names are timestamps, which say nothing. Rename by what the shot
# actually shows, in the order the capture plan in docs/release/store-listing.md
# lists them, so the upload order is obvious.
RENAMES = {
    "photo_2026-07-20_19-41-47.jpg": "01-source-photo",
    "photo_2026-07-20_19-41-51.jpg": "02-cut-out",
    "photo_2026-07-20_19-41-44.jpg": "03-text",
    "photo_2026-07-20_19-41-49.jpg": "04-adjust",
    "photo_2026-07-20_19-41-38.jpg": "05-frames",
    "photo_2026-07-20_19-41-35.jpg": "06-export",
    "photo_2026-07-20_19-41-25.jpg": "07-packs",
    "photo_2026-07-20_19-41-41.jpg": "08-sticker",
}


def pad(src: Image.Image, name: str) -> Image.Image:
    """Scale to fit inside the margin, centre on the brand backdrop, shadow it."""
    canvas = gradient_backdrop(W, H).convert("RGBA")

    box_w, box_h = W - 2 * MARGIN, H - 2 * MARGIN
    scale = min(box_w / src.width, box_h / src.height)
    # Never upscale past 1:1; enlarging a 512px sticker to fill 1080 would just
    # ship a soft image.
    scale = min(scale, 1.0)
    art = src.convert("RGB").resize(
        (max(1, round(src.width * scale)), max(1, round(src.height * scale))),
        Image.LANCZOS,
    )

    radius = max(8, round(min(art.size) * 0.02))
    mask = Image.new("L", art.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, art.width - 1, art.height - 1], radius=radius, fill=255
    )
    slab = Image.new("RGBA", art.size, (0, 0, 0, 0))
    slab.paste(art, (0, 0), mask)
    ImageDraw.Draw(slab).rounded_rectangle(
        [0, 0, art.width - 1, art.height - 1], radius=radius,
        outline=(255, 255, 255, 56), width=2,
    )

    x, y = (W - art.width) // 2, (H - art.height) // 2
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 150), (x, y + 14), slab.getchannel("A"))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(22)))
    canvas.alpha_composite(slab, (x, y))
    return canvas.convert("RGB")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    jobs: list[tuple[Path, str]] = []
    for fname, label in RENAMES.items():
        p = SHOTS / fname
        if p.exists():
            jobs.append((p, label))
        else:
            print(f"  MISSING, skipped: {fname}")
    if FEATURE.exists():
        jobs.append((FEATURE, "09-feature-graphic"))

    for src_path, label in jobs:
        src = Image.open(src_path)
        out_path = OUT / f"{label}.png"
        img = pad(src, label)
        img.save(out_path, "PNG", optimize=True)
        assert img.size == (W, H), f"{label}: expected {W}x{H}, got {img.size}"
        assert img.mode == "RGB", f"{label}: expected RGB, got {img.mode}"
        print(f"  {label:20} <- {src_path.name:32} {str(src.size):12} "
              f"-> {W}x{H}  {out_path.stat().st_size / 1024:6.0f} KB")

    print(f"\n{len(jobs)} files in {OUT.relative_to(REPO).as_posix()}")


if __name__ == "__main__":
    main()
