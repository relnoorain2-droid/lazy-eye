#!/usr/bin/env python3
"""
make_icon.py - generates the Amblyo app icon into the asset catalog.

CONCEPT (docs/10-APP-ICON-SPEC.md):
Two overlapping circles, one red and one cyan, with the overlap rendered white.
It is literally what the app does - two eyes, two channels, one fused percept -
and red/cyan are the anaglyph colours. Every competitor in this category uses a
cartoon eyeball; a lens/fusion mark stands out in a search grid at 60pt.

WHY IT WRITES STRAIGHT INTO Assets.xcassets:
The first TestFlight upload was rejected by Apple with
  "Missing required icon file ... app icon for iPhone of exactly 120x120"
because the appiconset had a Contents.json but no image. Xcode 15+ needs only a
single 1024x1024 source and derives every other size, so one file per appearance
is enough - but that file has to actually exist.

RULES (Apple will reject otherwise):
  - 1024x1024 exactly
  - fully opaque, NO alpha channel
  - sRGB
  - no rounded corners baked in; iOS applies the squircle mask

    python3 scripts/make_icon.py
"""

from __future__ import annotations
import json
import pathlib

from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
ICONSET = ROOT / "App" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
EXPORT = ROOT / "Assets" / "Icon"

SIZE = 1024


def radial_background(inner: tuple[int, int, int],
                      outer: tuple[int, int, int]) -> Image.Image:
    """Soft radial gradient. Flat colour looks cheap at large sizes."""
    img = Image.new("RGB", (SIZE, SIZE), outer)
    draw = ImageDraw.Draw(img)
    steps = 200
    for i in range(steps, 0, -1):
        t = i / steps
        r = int(SIZE * 0.78 * t)
        colour = tuple(
            int(outer[c] + (inner[c] - outer[c]) * (1 - t)) for c in range(3)
        )
        draw.ellipse([SIZE // 2 - r, SIZE // 2 - r, SIZE // 2 + r, SIZE // 2 + r],
                     fill=colour)
    return img.filter(ImageFilter.GaussianBlur(30))


def screen_blend(base: Image.Image, layer: Image.Image) -> Image.Image:
    """
    Screen blend: 1 - (1-a)(1-b). Where the red and cyan discs overlap this
    drives the result toward white, which is the whole point of the mark - the
    fused region is the bright bit.
    """
    import numpy as np
    b = np.asarray(base.convert("RGB"), dtype=np.float32) / 255.0
    l = np.asarray(layer.convert("RGBA"), dtype=np.float32) / 255.0
    rgb, alpha = l[..., :3], l[..., 3:4]
    effective = rgb * alpha
    out = 1.0 - (1.0 - b) * (1.0 - effective)
    return Image.fromarray((out * 255).clip(0, 255).astype("uint8"), "RGB")


def disc(cx: int, cy: int, r: int, colour: tuple[int, int, int],
         alpha: float) -> Image.Image:
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse([cx - r, cy - r, cx + r, cy + r],
                                  fill=colour + (int(255 * alpha),))
    return layer


def build(bg_in, bg_out, red, cyan, alpha, grayscale=False) -> Image.Image:
    img = radial_background(bg_in, bg_out)
    img = screen_blend(img, disc(438, 512, 250, red, alpha))
    img = screen_blend(img, disc(586, 512, 250, cyan, alpha))

    # Pupil: a small dark circle at the centre of the fused region. Gives the
    # mark a focal point and reads as a lens rather than a Venn diagram.
    ImageDraw.Draw(img).ellipse([512 - 44, 512 - 44, 512 + 44, 512 + 44],
                                fill=bg_out)

    if grayscale:
        img = img.convert("L").convert("RGB")

    # Opaque RGB, no alpha. Apple rejects icons with an alpha channel.
    return img.convert("RGB")


VARIANTS = {
    "AppIcon-light.png": dict(bg_in=(30, 78, 82), bg_out=(14, 42, 45),
                              red=(255, 59, 48), cyan=(0, 212, 224), alpha=0.88),
    "AppIcon-dark.png": dict(bg_in=(16, 44, 47), bg_out=(8, 24, 26),
                             red=(255, 86, 74), cyan=(60, 226, 236), alpha=0.95),
    "AppIcon-tinted.png": dict(bg_in=(30, 78, 82), bg_out=(14, 42, 45),
                               red=(255, 59, 48), cyan=(0, 212, 224), alpha=0.88,
                               grayscale=True),
}

CONTENTS = {
    "images": [
        {"filename": "AppIcon-light.png", "idiom": "universal",
         "platform": "ios", "size": "1024x1024"},
        {"filename": "AppIcon-dark.png", "idiom": "universal",
         "platform": "ios", "size": "1024x1024",
         "appearances": [{"appearance": "luminosity", "value": "dark"}]},
        {"filename": "AppIcon-tinted.png", "idiom": "universal",
         "platform": "ios", "size": "1024x1024",
         "appearances": [{"appearance": "luminosity", "value": "tinted"}]},
    ],
    "info": {"author": "xcode", "version": 1},
}


def main() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    EXPORT.mkdir(parents=True, exist_ok=True)

    for name, kwargs in VARIANTS.items():
        image = build(**kwargs)
        assert image.size == (SIZE, SIZE), "icon must be exactly 1024x1024"
        assert image.mode == "RGB", "icon must have no alpha channel"

        image.save(ICONSET / name, "PNG")
        image.save(EXPORT / name, "PNG")
        print(f"  wrote {name}  ({image.size[0]}x{image.size[1]}, {image.mode})")

    (ICONSET / "Contents.json").write_text(json.dumps(CONTENTS, indent=2) + "\n")
    print(f"  wrote Contents.json referencing {len(VARIANTS)} appearance(s)")
    print(f"\nIcon set: {ICONSET.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
