#!/usr/bin/env python3
"""
make_screenshots.py — builds App Store screenshots from raw device captures.

WHY THIS IS A SCRIPT AND NOT A DESIGN FILE
Screenshots get redone: after every UI change, for every new language, and every
time Apple adds a device size. Doing it by hand in an image editor means the
second pass is as expensive as the first and the eighth panel never quite
matches the first. Here the layout is one function, the copy is one list, and
regenerating every size is one command.

THE COPY RULE THAT OVERRIDES EVERY DESIGN CONSIDERATION
App Store screenshot text is scanned by App Review under Guideline 1.4.1 exactly
like in-app text. A single "treatment" or "improves your vision" in a caption is
a rejection, and a rejection costs a week. So `check_captions()` runs the SAME
banned-word list as scripts/lint_claims.py against every caption in this file,
and refuses to render if any of them trips it. The prettiest panel in the world
is worthless if the words on it get the app pulled.

USAGE
    python3 scripts/make_screenshots.py
    python3 scripts/make_screenshots.py --check   # captions only, no rendering
"""

from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "screenshort"
OUTPUT = ROOT / "appstore-screenshots"

# --------------------------------------------------------------------------
# Palette — sampled from the app itself, not invented.
#
# The brand teal is the exact pixel value of a Start button in the capture
# (61, 104, 109). Picking a "close enough" teal by eye is how marketing art
# ends up looking like a different product than the one it is selling.
# --------------------------------------------------------------------------
BRAND = (61, 104, 109)
DEEP = (10, 32, 36)
MID = (23, 69, 74)
CREAM = (251, 250, 247)
AMBER = (224, 168, 60)
MIST = (168, 196, 197)

FONT_DIR = Path("/usr/share/fonts/truetype/google-fonts")
BOLD = FONT_DIR / "Poppins-Bold.ttf"

MEDIUM = FONT_DIR / "Poppins-Medium.ttf"

# --------------------------------------------------------------------------
# The panels.
#
# Ordered deliberately. Most people never scroll past the third, so the first
# three have to carry the whole pitch: what it is, how much a day, and the one
# thing no competitor does.
# --------------------------------------------------------------------------
# ORDER IS A DECISION, NOT A FILE LISTING.
# Most people never scroll past the third panel, so the first three carry the
# whole pitch. The Today screen was second and has been moved to sixth: the
# capture was taken on a fresh install, so it shows "Finish setting up" and a
# row of zeros. The message is good and the picture undersells it — worth
# re-capturing after a real session and promoting again.
PANELS = [
    dict(
        src="IMG_0304.png",
        headline=["32 exercises", "for lazy eye"],
        accent=1,
        sub="Every one explains itself. Tap ? whenever you are not sure.",
        tilt=0,
    ),
    dict(
        src="IMG_0301.png",
        headline=["18 exercises need", "BOTH eyes"],
        accent=1,
        sub="A cheap pair of red-cyan glasses unlocks the two-eye set.",
        tilt=-6,
    ),
    dict(
        src="IMG_0306.png",
        headline=["Games children", "actually finish"],
        accent=1,
        sub="One eye sees the creature. The other sees the wall.",
        tilt=6,
    ),
    dict(
        src="IMG_0305.png",
        headline=["It finds", "your level"],
        accent=1,
        sub="Three right makes it harder. One wrong steps back. Automatically.",
        tilt=0,
    ),
    dict(
        src="IMG_0303.png",
        headline=["Sized to your", "screen exactly"],
        accent=1,
        sub="Measure once. Every shape is then an angle, not a number of pixels.",
        tilt=-6,
    ),
    dict(
        src="IMG_0300.png",
        headline=["One short session", "a day"],
        accent=1,
        sub="A plan built from what you did yesterday, with a hard daily limit.",
        tilt=6,
    ),
    dict(
        src="IMG_0307.png",
        headline=["Honest about", "what it cannot do"],
        accent=1,
        sub="An exercise app, not eye care. It says so on the first screen.",
        tilt=0,
    ),
    dict(
        src="IMG_0308.png",
        headline=["Up to 5 people,", "one subscription"],
        accent=1,
        sub="Each with their own eye, their own plan and their own history.",
        tilt=-6,
    ),
]

SIZES = {
    "iphone-6.9_1290x2796": (1290, 2796),
    "iphone-6.5_1242x2688": (1242, 2688),
    "ipad-13_2064x2752": (2064, 2752),
}


# --------------------------------------------------------------------------
# Caption safety
# --------------------------------------------------------------------------

def banned_patterns() -> list[str]:
    """The live list from lint_claims.py, IMPORTED rather than parsed.

    The first version read the file and pulled the patterns out with a regex.
    It found eight of the thirty and reported PASS — a checker that silently
    covers a quarter of its rules is worse than no checker, because it produces
    confidence instead of doubt. Importing the module is exact by construction:
    if the list moves or grows, this follows it or fails loudly.
    """
    sys.path.insert(0, str(ROOT / "scripts"))
    import lint_claims                      # noqa: E402
    return list(lint_claims.BANNED)


def check_captions() -> int:
    patterns = banned_patterns()
    # A short list means the import found something unexpected. Refuse rather
    # than proceed: silently checking a fraction is the failure this replaced.
    if len(patterns) < 20:
        print(f"make-screenshots: FAIL — only {len(patterns)} banned pattern(s) "
              f"loaded, expected the full list. Not rendering.")
        return 1
    problems = []
    for panel in PANELS:
        text = " ".join(panel["headline"]) + " " + panel["sub"]
        for pattern in patterns:
            if re.search(pattern, text, re.I):
                problems.append((panel["src"], pattern, text))
    if problems:
        print("make-screenshots: FAIL — banned claim language in captions")
        for src, pattern, text in problems:
            print(f"  {src}: /{pattern}/ matched in: {text}")
        return 1
    print(f"make-screenshots: captions PASS — {len(PANELS)} panel(s) "
          f"checked against {len(patterns)} pattern(s).")
    return 0


# --------------------------------------------------------------------------
# Drawing helpers
# --------------------------------------------------------------------------

def font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(path), size)


def gradient(size: tuple[int, int]) -> Image.Image:
    """Diagonal deep-teal wash with a soft glow behind the device.

    Dark, deliberately. The app itself is cream and pale, so a light marketing
    background would let the device melt into it — the screen has to be the
    brightest thing in the frame or the eye has nowhere to land.
    """
    w, h = size
    base = Image.new("RGB", (w, h), DEEP)
    draw = ImageDraw.Draw(base)
    for y in range(h):
        t = y / max(1, h - 1)
        # Ease so the top stays dark longer and the fade feels like light
        # falling rather than a linear ramp.
        e = t * t * (3 - 2 * t)
        draw.line([(0, y), (w, y)],
                  fill=tuple(int(DEEP[i] + (MID[i] - DEEP[i]) * e) for i in range(3)))

    glow = Image.new("L", (w, h), 0)
    ImageDraw.Draw(glow).ellipse(
        [w * 0.5 - w * 0.62, h * 0.30, w * 0.5 + w * 0.62, h * 1.05], fill=110)
    glow = glow.filter(ImageFilter.GaussianBlur(w * 0.13))
    base = Image.composite(Image.new("RGB", (w, h), BRAND), base, glow)

    # A single wide arc, echoing the eye in the app icon. One shape, low
    # contrast: background texture that competes with the device is not texture.
    arc = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(arc).arc(
        [-w * 0.35, h * 0.02, w * 1.35, h * 0.72],
        start=200, end=340, fill=(255, 255, 255, 26), width=max(2, w // 380))
    base = Image.alpha_composite(base.convert("RGBA"), arc).convert("RGB")
    return base


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1],
                                           radius=radius, fill=255)
    return mask


def clean_status_bar(shot: Image.Image, crop: int = 168) -> Image.Image:
    """Removes the capture's own status bar and draws a neutral one.

    TWO THINGS HAD TO GO, AND ONE OF THEM MATTERS A LOT.
    Every capture carries "◀ TestFlight" in the top-left, because they were
    taken from a TestFlight build. On an App Store listing that is a screenshot
    of a beta distribution channel — it tells a reviewer the images are not of
    the shipping app, and it tells a customer the same thing less kindly.
    Several captures also caught a half-scrolled Start button frozen over the
    status bar, which reads as a rendering fault.

    Cropping alone would leave the phone looking decapitated, so the strip is
    rebuilt: 9:41 (Apple's own convention in every marketing image they publish)
    and plain signal, wi-fi and battery glyphs, on the page's real background
    colour sampled from the capture itself.
    """
    w, h = shot.size
    body = shot.crop((0, crop, w, h))
    background = shot.getpixel((6, crop + 4))

    bar = Image.new("RGB", (w, crop), background)
    draw = ImageDraw.Draw(bar)
    ink = (26, 30, 32)
    f = font(BOLD, int(crop * 0.30))

    draw.text((int(w * 0.085), int(crop * 0.40)), "9:41", font=f, fill=ink)

    right = int(w * 0.915)
    # Battery
    bw, bh = int(w * 0.055), int(crop * 0.26)
    bx, by = right - bw, int(crop * 0.47)
    draw.rounded_rectangle([bx, by, bx + bw, by + bh], radius=bh // 3,
                           outline=ink, width=max(2, w // 500))
    draw.rounded_rectangle([bx + 3, by + 3, bx + bw - 3, by + bh - 3],
                           radius=bh // 4, fill=ink)
    # Wi-Fi: three arcs and a dot
    cx = bx - int(w * 0.030)
    cy = by + bh
    for i, r in enumerate((int(w * 0.020), int(w * 0.013), int(w * 0.006))):
        draw.arc([cx - r, cy - r, cx + r, cy + r], start=205, end=335,
                 fill=ink, width=max(2, w // 480))
    draw.ellipse([cx - 3, cy - 4, cx + 3, cy + 2], fill=ink)
    # Signal: four rising bars
    sx = cx - int(w * 0.048)
    for i in range(4):
        bar_h = int(crop * (0.10 + 0.045 * i))
        x0 = sx + i * int(w * 0.011)
        draw.rounded_rectangle([x0, cy - bar_h, x0 + int(w * 0.007), cy],
                               radius=2, fill=ink)

    out = Image.new("RGB", (w, h), background)
    out.paste(bar, (0, 0))
    out.paste(body, (0, crop))
    return out


def device(shot: Image.Image, width: int) -> Image.Image:
    """The screenshot in a phone body: bezel, rounded screen, subtle rim light."""
    ratio = shot.height / shot.width
    screen_w = width
    screen_h = int(screen_w * ratio)
    bezel = max(6, int(screen_w * 0.022))
    radius = int(screen_w * 0.115)

    body_w, body_h = screen_w + bezel * 2, screen_h + bezel * 2
    body = Image.new("RGBA", (body_w, body_h), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle(
        [0, 0, body_w - 1, body_h - 1],
        radius=radius + bezel, fill=(14, 18, 20, 255))

    screen = shot.resize((screen_w, screen_h), Image.LANCZOS).convert("RGBA")
    screen.putalpha(rounded_mask((screen_w, screen_h), radius))
    body.alpha_composite(screen, (bezel, bezel))

    # Rim light along the top-left edge. Without it the black body reads as a
    # hole cut in the background rather than an object in front of it.
    rim = Image.new("RGBA", (body_w, body_h), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle(
        [0, 0, body_w - 1, body_h - 1], radius=radius + bezel,
        outline=(255, 255, 255, 46), width=max(2, bezel // 3))
    body.alpha_composite(rim)
    return body


def perspective(image: Image.Image, degrees: float) -> Image.Image:
    """A gentle Y-axis rotation, for depth.

    Not a real 3D render — a plane rotation, which is all a flat screen in a
    marketing panel ever is. The angle stays small on purpose: past about eight
    degrees the UI inside stops being readable, and an unreadable screenshot
    sells nothing however good it looks.
    """
    if abs(degrees) < 0.01:
        return image
    w, h = image.size
    pad = int(w * 0.30)
    canvas = Image.new("RGBA", (w + pad * 2, h), (0, 0, 0, 0))
    canvas.alpha_composite(image, (pad, 0))
    w2, h2 = canvas.size

    # 0.16 was too timid to see at panel scale — the first render came out
    # looking flat, which is the worst outcome: the cost of the transform with
    # none of the depth. 0.46 reads as a tilt while keeping the UI legible.
    shrink = math.sin(math.radians(abs(degrees))) * h * 0.46
    if degrees > 0:
        target = [(0, shrink), (w2, 0), (w2, h2), (0, h2 - shrink)]
    else:
        target = [(0, 0), (w2, shrink), (w2, h2 - shrink), (0, h2)]
    source = [(0, 0), (w2, 0), (w2, h2), (0, h2)]

    matrix = []
    for (sx, sy), (tx, ty) in zip(source, target):
        matrix.append([tx, ty, 1, 0, 0, 0, -sx * tx, -sx * ty])
        matrix.append([0, 0, 0, tx, ty, 1, -sy * tx, -sy * ty])
    import numpy as np
    A = np.array(matrix, dtype=float)
    B = np.array(source, dtype=float).reshape(8)
    coeffs = np.linalg.solve(A, B)
    return canvas.transform((w2, h2), Image.PERSPECTIVE, coeffs,
                            Image.BICUBIC)


def drop_shadow(image: Image.Image, blur: int, offset: tuple[int, int],
                opacity: int) -> Image.Image:
    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, opacity), mask=image.split()[3])
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    out = Image.new("RGBA",
                    (image.width + abs(offset[0]) + blur * 2,
                     image.height + abs(offset[1]) + blur * 2), (0, 0, 0, 0))
    out.alpha_composite(shadow, (blur + max(0, offset[0]), blur + max(0, offset[1])))
    out.alpha_composite(image, (blur, blur))
    return out


def wrap(draw, text: str, f, max_width: int) -> list[str]:
    words, lines, line = text.split(), [], ""
    for word in words:
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=f) <= max_width:
            line = trial
        else:
            if line:
                lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


# --------------------------------------------------------------------------
# Panel composition
# --------------------------------------------------------------------------

def build(panel: dict, size: tuple[int, int], index: int) -> Image.Image:
    w, h = size
    canvas = gradient(size).convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    is_pad = w / h > 0.6
    margin = int(w * (0.085 if not is_pad else 0.10))

    head_size = int(w * (0.083 if not is_pad else 0.062))
    sub_size = int(w * (0.032 if not is_pad else 0.024))
    head_font = font(BOLD, head_size)
    sub_font = font(MEDIUM, sub_size)

    y = int(h * (0.062 if not is_pad else 0.055))

    # Headline. The accent line is amber rather than the brand teal: teal on a
    # teal wash is a tone difference, and a tone difference is not emphasis.
    for i, line in enumerate(panel["headline"]):
        colour = AMBER if i == panel.get("accent", -1) else (255, 255, 255)
        draw.text((margin, y), line, font=head_font, fill=colour)
        y += int(head_size * 1.12)

    y += int(head_size * 0.24)
    for line in wrap(draw, panel["sub"], sub_font, w - margin * 2):
        draw.text((margin, y), line, font=sub_font, fill=MIST)
        y += int(sub_size * 1.45)

    # Device
    shot = clean_status_bar(Image.open(SOURCE / panel["src"]).convert("RGB"))
    available_h = h - y - int(h * 0.045)
    device_w = int(w * (0.70 if not is_pad else 0.50))
    frame = device(shot, device_w)
    if frame.height > available_h:
        scale = available_h / frame.height
        frame = frame.resize((int(frame.width * scale), int(frame.height * scale)),
                             Image.LANCZOS)

    frame = perspective(frame, panel.get("tilt", 0))
    frame = drop_shadow(frame, blur=int(w * 0.028),
                        offset=(0, int(h * 0.010)), opacity=150)

    x = (w - frame.width) // 2
    canvas.alpha_composite(frame, (x, y + int(h * 0.012)))

    # Page dots, so a viewer can see there is more than one panel.
    dot_r = max(3, w // 260)
    gap = dot_r * 5
    total = len(PANELS) * gap - (gap - dot_r * 2)
    dx = (w - total) // 2
    dy = h - int(h * 0.028)
    for i in range(len(PANELS)):
        fill = (255, 255, 255, 230) if i == index else (255, 255, 255, 70)
        draw.ellipse([dx, dy, dx + dot_r * 2, dy + dot_r * 2], fill=fill)
        dx += gap

    return canvas.convert("RGB")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true",
                        help="check captions only, render nothing")
    args = parser.parse_args()

    if check_captions() != 0:
        return 1
    if args.check:
        return 0

    if not SOURCE.exists():
        print(f"make-screenshots: no source folder at {SOURCE}")
        return 1

    for name, size in SIZES.items():
        folder = OUTPUT / name
        folder.mkdir(parents=True, exist_ok=True)
        for i, panel in enumerate(PANELS, start=1):
            image = build(panel, size, i - 1)
            assert image.size == size, f"{name} came out {image.size}, wanted {size}"
            out = folder / f"{i:02d}.png"
            image.save(out, "PNG")
        print(f"make-screenshots: {name} — {len(PANELS)} panel(s) at {size[0]}x{size[1]}")

    print(f"make-screenshots: written to {OUTPUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
