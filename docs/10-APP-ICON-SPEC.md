# 10 — APP ICON SPEC

The reference app's icon is a flat cartoon eye on a blue hex pattern — indistinguishable from the
dozen other lazy-eye apps, all of which use a cartoon eye. **Our advantage is to not draw an eye.**

---

## 1. CONCEPT — "THE FUSION"

Two overlapping circles — one red, one cyan — with the **overlap rendered in clean white**.

Why this is the right mark:

- It is literally what the app does: two eyes, two channels, one fused percept. Red and cyan are the
  anaglyph colours. The white overlap is fusion.
- It reads as a **lens/optics** mark instantly, without being a cartoon eyeball.
- It is **unique in the category** — every competitor is an eye. A Venn/lens mark stands out in a
  search result grid at 60×60 pt.
- It survives extreme downscaling: at 29×29 pt it is still two coloured discs with a bright centre.
- It is trivially animatable for the launch screen (the two circles slide together and the centre
  blooms) and for the Learn illustrations.
- Colour-blind users still perceive two distinct shapes and a bright core — the mark works on
  luminance alone.

**Optional refinement:** make the white overlap a soft vertical almond (a *vesica piscis*), which
reads simultaneously as a lens, a pupil, and the fused region. This is the version to build.

---

## 2. GEOMETRY (1024 × 1024 canvas)

```
Canvas            1024 × 1024
Background        radial gradient, centre #1E4E52 → edges #0E2A2D   (deep teal, matches brandPrimary)
                  plus a very subtle 2% noise overlay to avoid banding

Left circle       centre (438, 512)   radius 250   fill #FF3B30 at 88% opacity, screen blend
Right circle      centre (586, 512)   radius 250   fill #00D4E0 at 88% opacity, screen blend
Overlap           renders naturally to near-white via screen blending

Vesica highlight  the lens-shaped intersection, filled #FFFFFF at 92%,
                  with a 6 px outer glow #FFFFFF at 25%

Inner mark        a 46 px-radius circle at (512, 512), #0E2A2D at 70%
                  — reads as a pupil, gives the mark a focal point

Safe area         keep all marks within a 880 × 880 centred box
Corner radius     none — iOS applies the squircle mask; never bake in corners
```

**Hard rules:**

- **No text, no letters, no "A"** — text is illegible at 29 pt and looks amateur.
- **No transparency** in the 1024 marketing icon. Fully opaque, no alpha channel, or App Store Connect
  rejects the upload.
- **No drop shadow, no bevel, no gloss.** iOS adds its own treatment.
- No thin strokes below 8 px at 1024 — they vanish at small sizes.

---

## 3. VARIANTS TO PRODUCE

| Variant | Change |
|---|---|
| **Light (default)** | As specified above |
| **Dark** (iOS 18+ `AppIcon` dark variant) | Background → `#08181A`; circles brightened to 95% opacity |
| **Tinted** (iOS 18+ monochrome variant) | Grayscale luminance version: circles as mid-grey discs, overlap white. Test that it survives iOS's tinting — this is the variant everyone forgets and it looks broken by default |
| **Kids mode alt icon** | Same geometry with `brandSecondary` amber replacing teal, and a friendlier rounded highlight |
| **Launch screen** | Static version of the mark, centred, on `surfaceBase` |

Alternate icons are a nice retention touch — offer the Kids icon as a free unlock, and a "Pro" dark
variant to subscribers.

---

## 4. DELIVERABLES

For **Xcode 15+ / iOS 18+** you only need the single 1024×1024 for each appearance — Xcode generates
the rest. Produce:

```
Assets/Icon/
  icon-1024-light.png       1024×1024, opaque, sRGB, no alpha
  icon-1024-dark.png
  icon-1024-tinted.png      grayscale
  icon-kids-1024.png
  icon.svg                  master vector source
  launch-mark.svg
```

Then in `App/Resources/Assets.xcassets/AppIcon.appiconset/` use the **single-size** configuration with
Any/Dark/Tinted appearances.

---

## 5. GENERATION SCRIPT (runs on Windows, no design tool needed)

`scripts/make_icon.py` — Python + Pillow. Deterministic, versioned, regenerable.

```python
# scripts/make_icon.py
# pip install pillow
from PIL import Image, ImageDraw, ImageFilter
import math

S = 1024

def radial_bg(c_in, c_out):
    img = Image.new("RGB", (S, S), c_out)
    d = ImageDraw.Draw(img)
    steps = 220
    for i in range(steps, 0, -1):
        t = i / steps
        r = int(S * 0.78 * t)
        col = tuple(int(c_out[j] + (c_in[j] - c_out[j]) * (1 - t)) for j in range(3))
        d.ellipse([S//2 - r, S//2 - r, S//2 + r, S//2 + r], fill=col)
    return img.filter(ImageFilter.GaussianBlur(28))

def disc(cx, cy, r, color, alpha):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse([cx-r, cy-r, cx+r, cy+r], fill=color + (int(255*alpha),))
    return layer

def screen(base, layer):
    """Screen blend: 1 - (1-a)(1-b), respecting the layer's alpha."""
    b = base.convert("RGBA")
    out = Image.new("RGBA", (S, S))
    bp, lp, op = b.load(), layer.load(), out.load()
    for y in range(S):
        for x in range(S):
            br, bg, bb, _ = bp[x, y]
            lr, lg, lb, la = lp[x, y]
            a = la / 255.0
            f = lambda c1, c2: int(255 - (255 - c1) * (255 - c2 * a) / 255)
            op[x, y] = (f(br, lr), f(bg, lg), f(bb, lb), 255)
    return out

def build(bg_in, bg_out, red, cyan, alpha, out_path, grayscale=False):
    img = radial_bg(bg_in, bg_out)
    img = screen(img, disc(438, 512, 250, red,  alpha))
    img = screen(img, disc(586, 512, 250, cyan, alpha))
    d = ImageDraw.Draw(img)
    d.ellipse([512-46, 512-46, 512+46, 512+46], fill=bg_out + (255,))   # pupil
    img = img.convert("L").convert("RGB") if grayscale else img.convert("RGB")
    img.save(out_path, "PNG")
    print("wrote", out_path)

build((30,78,82), (14,42,45), (255,59,48),  (0,212,224), 0.88, "Assets/Icon/icon-1024-light.png")
build((16,44,47), (8,24,26),  (255,86,74),  (60,226,236), 0.95, "Assets/Icon/icon-1024-dark.png")
build((30,78,82), (14,42,45), (255,59,48),  (0,212,224), 0.88, "Assets/Icon/icon-1024-tinted.png", grayscale=True)
build((92,58,18), (46,29,9),  (255,140,60), (255,214,102), 0.9, "Assets/Icon/icon-kids-1024.png")
```

The nested-loop screen blend is slow (~10 s) but dependency-free and obvious. Swap in NumPy if it
annoys you.

---

## 6. QA CHECKLIST

- [ ] Renders correctly at 1024, 180, 120, 87, 80, 60, 58, 40, 29 pt
- [ ] Legible on both a white and a black Home Screen wallpaper
- [ ] Distinct from the top 10 "lazy eye" search results when placed beside them
- [ ] Dark variant does not disappear against a dark wallpaper
- [ ] Tinted variant is not a muddy blob (this is the usual failure)
- [ ] No alpha channel in any 1024 file (`sips`/Pillow check in CI)
- [ ] sRGB colour profile
- [ ] Passes the "squint test" — blur it heavily; the two-circles-plus-bright-centre structure must
      still be readable
