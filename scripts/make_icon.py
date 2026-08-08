#!/usr/bin/env python3
"""
make_icon.py - renders the Amblyo app icon.

WHAT IT DRAWS
A photoreal-stylised eye, rendered rather than drawn: an almond aperture, a
spherical sclera, a concave iris with radial stromal fibres, a dark limbal ring,
a corneal specular highlight, and - the detail that actually sells depth - a
bright crescent on the iris wall OPPOSITE the highlight, which is light
refracting through the cornea and bouncing off the far side. Eyes look flat
without it, and every "3D eye" icon that works has it.

Behind the eye sit two soft rim glows, warm red on the left and cyan on the
right. That is the anaglyph pair the therapy actually uses, present as lighting
rather than as a diagram.

WHY NUMPY AND NOT ImageDraw
Everything is a signed distance field composited with smoothstep, so edges are
analytically antialiased and gradients are continuous. ImageDraw gives hard
jaggies at 1024 and banding on gradients - fine for a mockup, visibly cheap on a
home screen next to Apple's own icons.

APPLE'S RULES (violating any one is a rejection)
  - exactly 1024x1024
  - fully opaque, NO alpha channel
  - sRGB
  - square, no baked rounded corners; iOS applies the squircle mask itself

    python3 scripts/make_icon.py
"""

from __future__ import annotations
import json
import pathlib

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
ICONSET = ROOT / "App" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
EXPORT = ROOT / "Assets" / "Icon"

S = 1024
CX = CY = S / 2.0

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def smoothstep(edge0, edge1, x: np.ndarray) -> np.ndarray:
    # edge0/edge1 may be arrays (the fibre-length term varies per pixel), so the
    # denominator has to be guarded rather than assumed non-zero.
    span = np.asarray(edge1, dtype=np.float32) - np.asarray(edge0, dtype=np.float32)
    span = np.where(np.abs(span) < 1e-6, 1e-6, span)
    t = np.clip((x - edge0) / span, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def over(base: np.ndarray, colour, alpha: np.ndarray) -> np.ndarray:
    """Alpha-composite a flat colour (or per-pixel colour array) onto base."""
    c = np.asarray(colour, dtype=np.float32)
    if c.ndim == 1:
        c = c.reshape(1, 1, 3)
    a = alpha[..., None].astype(np.float32)
    return base * (1.0 - a) + c * a


def hexc(value: str) -> np.ndarray:
    value = value.lstrip("#")
    return np.array([int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)],
                    dtype=np.float32)


# Pixel grid, shared by every field below.
_y, _x = np.mgrid[0:S, 0:S].astype(np.float32)
_x += 0.5
_y += 0.5


def dist(cx: float, cy: float, sx: float = 1.0, sy: float = 1.0) -> np.ndarray:
    return np.sqrt(((_x - cx) / sx) ** 2 + ((_y - cy) / sy) ** 2)


# ---------------------------------------------------------------------------
# geometry
# ---------------------------------------------------------------------------

# Almond aperture = intersection of two large circles offset vertically.
# r=560 / offset=318 gives roughly a 2.05:1 lens, which is the proportion a
# relaxed human eye opening actually has. Narrower reads as a squint, wider
# reads as a cartoon.
LID_R, LID_OFF = 560.0, 318.0

IRIS_R = 196.0
PUPIL_R = 76.0

AF = 1.6   # antialias width in px


def eye_alpha() -> np.ndarray:
    top = dist(CX, CY - LID_OFF)      # circle whose LOWER arc is the upper lid
    bottom = dist(CX, CY + LID_OFF)   # circle whose UPPER arc is the lower lid
    return (smoothstep(LID_R + AF, LID_R - AF, top)
            * smoothstep(LID_R + AF, LID_R - AF, bottom))


# ---------------------------------------------------------------------------
# layers
# ---------------------------------------------------------------------------

def background(inner: str, outer: str, rim: float) -> np.ndarray:
    r = dist(CX, CY) / (S * 0.72)
    t = np.clip(r, 0.0, 1.0) ** 1.25
    img = (hexc(inner).reshape(1, 1, 3) * (1.0 - t[..., None])
           + hexc(outer).reshape(1, 1, 3) * t[..., None])

    # The anaglyph pair as lighting. Wide, low-opacity, well outside the eye so
    # it never fights the iris for attention.
    glow_l = np.exp(-(dist(168, 512, 1.0, 0.62) / 300.0) ** 2) * rim
    glow_r = np.exp(-(dist(856, 512, 1.0, 0.62) / 300.0) ** 2) * rim
    img = img + hexc("FF3B30").reshape(1, 1, 3) * glow_l[..., None]
    img = img + hexc("00D4E0").reshape(1, 1, 3) * glow_r[..., None]

    # Corner vignette. Keeps the eye the brightest thing in the frame once the
    # squircle mask crops the corners anyway.
    vig = smoothstep(0.55, 1.05, dist(CX, CY) / (S * 0.62))
    img = img * (1.0 - 0.45 * vig[..., None])
    return np.clip(img, 0.0, 1.0)


def sclera(img: np.ndarray, eye: np.ndarray) -> np.ndarray:
    r = dist(CX, CY, 1.0, 0.52)

    # Spherical falloff: the eyeball is a sphere, so it dims toward the corners
    # of the opening. Flat white here is what makes cheap eye icons look like
    # stickers.
    shade = smoothstep(180.0, 470.0, r)
    white = hexc("FFFFFF").reshape(1, 1, 3) * (1.0 - 0.22 * shade[..., None]) \
        + hexc("9FB4BC").reshape(1, 1, 3) * (0.22 * shade[..., None])

    # Upper-lid contact shadow. Strongest just under the lid line, gone by the
    # centre. Sells the lid as being in front of the globe.
    lid = dist(CX, CY - LID_OFF)
    shadow = smoothstep(LID_R - 96.0, LID_R, lid) * 0.30
    white = white * (1.0 - shadow[..., None] * 0.75)

    return over(img, white, eye)


def iris(img: np.ndarray, eye: np.ndarray, hue_in: str, hue_mid: str,
         hue_out: str) -> np.ndarray:
    r = dist(CX, CY)
    theta = np.arctan2(_y - CY, _x - CX)
    t = np.clip(r / IRIS_R, 0.0, 1.0)

    base = (hexc(hue_in).reshape(1, 1, 3) * (1.0 - smoothstep(0.0, 0.55, t))[..., None]
            + hexc(hue_mid).reshape(1, 1, 3) * (smoothstep(0.0, 0.55, t)
                                                * (1.0 - smoothstep(0.55, 1.0, t)))[..., None]
            + hexc(hue_out).reshape(1, 1, 3) * smoothstep(0.55, 1.0, t)[..., None])

    # Stromal fibres. Three coprime frequencies so the pattern never visibly
    # repeats, with per-fibre length variation from a slow fourth term.
    fib = (0.50 * np.sin(theta * 53.0 + 0.7)
           + 0.30 * np.sin(theta * 89.0 + 2.1)
           + 0.20 * np.sin(theta * 137.0 + 4.3))
    length = 0.55 + 0.45 * np.sin(theta * 23.0 + 1.4)
    envelope = smoothstep(0.30, 0.48, t) * (1.0 - smoothstep(0.72 * length + 0.28, 1.0, t))
    base = base * (1.0 + (fib * 0.34 * envelope)[..., None])

    # Collarette: the crimped ring where the iris changes depth near the pupil.
    coll = np.exp(-((t - 0.40) / 0.075) ** 2)
    base = base * (1.0 + 0.30 * coll[..., None])

    # Limbal ring. A dark outer edge is the single strongest "real eye" cue.
    limbal = smoothstep(0.80, 1.0, t)
    base = base * (1.0 - 0.72 * limbal[..., None])

    # Concavity: the iris is a dish, so the near wall sits in shadow.
    # NOTE: both factors need the trailing axis. Multiplying (H,W,1) by (H,W)
    # broadcasts to (H,W,W) and allocates 4 GiB.
    concave = smoothstep(0.55, 1.0, t) * smoothstep(620.0, 380.0, _y)
    base = base * (1.0 - 0.30 * concave[..., None])

    # THE 3D BEAT: caustic crescent on the far iris wall, opposite the corneal
    # highlight. Light enters the cornea top-left and lands bottom-right.
    caustic = (np.exp(-((r - IRIS_R * 0.74) / 34.0) ** 2)
               * np.clip(np.cos(theta - 1.05), 0.0, 1.0) ** 2.2)
    base = base + hexc("BFF7FF").reshape(1, 1, 3) * (caustic * 0.85)[..., None]

    a = smoothstep(IRIS_R + AF, IRIS_R - AF, r) * eye
    img = over(img, np.clip(base, 0.0, 1.0), a)

    # Pupil, with a soft inner rim so it is not a pasted black disc.
    pupil = smoothstep(PUPIL_R + AF, PUPIL_R - AF, r) * eye
    img = over(img, hexc("05090C"), pupil)
    img = over(img, hexc("000000"),
               smoothstep(PUPIL_R, PUPIL_R - 26.0, r) * eye * 0.55)
    return img


def cornea(img: np.ndarray, eye: np.ndarray) -> np.ndarray:
    # Primary specular: soft, elliptical, overlapping the pupil edge. Sitting it
    # partly over the pupil is what makes it read as glass in front of the iris
    # rather than a white dot painted on it.
    # A power of 3.2 keeps the core near-solid and lets it fall away fast at the
    # rim. At 1.7 it dissolved into the bright iris and read as a smudge.
    # Straddling the pupil edge, not floating on open iris: the reflection needs
    # black underneath it to read as glass in front of the eye.
    hi = np.exp(-(dist(452, 446, 1.0, 0.86) / 50.0) ** 3.2)
    img = over(img, hexc("FFFFFF"), np.clip(hi, 0.0, 1.0) * eye * 0.97)
    halo = np.exp(-(dist(452, 446, 1.0, 0.86) / 96.0) ** 2)
    img = over(img, hexc("FFFFFF"), halo * eye * 0.10)

    # Secondary, small and sharp, from a second light. Real reflections come in
    # pairs; a lone highlight looks rendered.
    hi2 = np.exp(-(dist(596, 592) / 27.0) ** 2)
    img = over(img, hexc("EAFBFF"), hi2 * eye * 0.55)

    # Wet meniscus along the lower lid.
    lid = dist(CX, CY + LID_OFF)
    wet = smoothstep(LID_R - 26.0, LID_R - 4.0, lid) * smoothstep(LID_R, LID_R - 3.0, lid)
    img = over(img, hexc("FFFFFF"), wet * eye * 0.45)
    return img


def lashline(img: np.ndarray, tint: str) -> np.ndarray:
    """A soft dark edge around the aperture: eyelid thickness, not eyeliner."""
    top = dist(CX, CY - LID_OFF)
    bottom = dist(CX, CY + LID_OFF)
    inside = (smoothstep(LID_R + AF, LID_R - AF, top)
              * smoothstep(LID_R + AF, LID_R - AF, bottom))
    band = (smoothstep(LID_R - 15.0, LID_R, top)
            + smoothstep(LID_R - 9.0, LID_R, bottom) * 0.65)
    return over(img, hexc(tint), np.clip(band, 0.0, 1.0) * inside * 0.55)


# ---------------------------------------------------------------------------
# variants
# ---------------------------------------------------------------------------

VARIANTS = {
    "AppIcon-light.png": dict(bg_in="14545E", bg_out="061A20", rim=0.16,
                              hue_in="52DCF2", hue_mid="12A8C4", hue_out="0A3550",
                              lash="04161C"),
    "AppIcon-dark.png": dict(bg_in="0B3038", bg_out="020A0D", rim=0.20,
                             hue_in="6AE8FA", hue_mid="17BCD8", hue_out="072538",
                             lash="000508"),
    "AppIcon-tinted.png": dict(bg_in="14545E", bg_out="061A20", rim=0.16,
                               hue_in="52DCF2", hue_mid="12A8C4", hue_out="0A3550",
                               lash="04161C", grayscale=True),
}


def render(bg_in, bg_out, rim, hue_in, hue_mid, hue_out, lash,
           grayscale=False) -> Image.Image:
    eye = eye_alpha()
    img = background(bg_in, bg_out, rim)
    img = sclera(img, eye)
    img = iris(img, eye, hue_in, hue_mid, hue_out)
    img = cornea(img, eye)
    img = lashline(img, lash)

    if grayscale:
        lum = img @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
        img = np.repeat(lum[..., None], 3, axis=2)

    out = (np.clip(img, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    return Image.fromarray(out, "RGB")


def main() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    EXPORT.mkdir(parents=True, exist_ok=True)

    for name, kwargs in VARIANTS.items():
        image = render(**kwargs)
        assert image.size == (S, S), "icon must be exactly 1024x1024"
        assert image.mode == "RGB", "icon must have no alpha channel"
        image.save(ICONSET / name, "PNG")
        image.save(EXPORT / name, "PNG")
        print(f"  {name}  {image.size[0]}x{image.size[1]}  {image.mode}")

    contents = {
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
    (ICONSET / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")

    # Home-screen legibility check. An icon is judged at 60pt, not at 1024.
    src = Image.open(EXPORT / "AppIcon-light.png")
    strip = Image.new("RGB", (560, 200), (22, 22, 24))
    x = 24
    for px in (180, 120, 80, 60, 40):
        thumb = src.resize((px, px), Image.LANCZOS)
        strip.paste(thumb, (x, 100 - px // 2))
        x += px + 24
    strip.save(EXPORT / "preview-sizes.png")
    print("  preview-sizes.png  (legibility check at 180/120/80/60/40 px)")


if __name__ == "__main__":
    main()
