#!/usr/bin/env python3
"""
make_colorsets.py — generates the asset-catalog colour sets from one source of truth.

Twelve colours x light/dark x a Contents.json each is 12 fiddly JSON files that
drift the moment someone edits one by hand. Generating them means the palette in
docs/05-DESIGN-SYSTEM.md, this script, and Tokens.swift can never disagree.

Run after editing PALETTE:
    python3 scripts/make_colorsets.py
"""

from __future__ import annotations
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "App" / "Resources" / "Assets.xcassets"

# name -> (light hex, dark hex)
# Source of truth: docs/05-DESIGN-SYSTEM.md section 2.
PALETTE: dict[str, tuple[str, str]] = {
    # Brand
    "BrandPrimary":    ("#2D6A6E", "#4FA5A9"),
    "BrandSecondary":  ("#E8B44A", "#F0C468"),
    "BrandAccent":     ("#7C6BB5", "#9A8AD1"),
    # Surfaces
    "SurfaceBase":     ("#FBFAF7", "#121417"),
    "SurfaceRaised":   ("#FFFFFF", "#1C1F24"),
    "SurfaceSunken":   ("#F1EFE9", "#0C0E10"),
    # Text
    "TextPrimary":     ("#1A1D21", "#F2F3F5"),
    "TextSecondary":   ("#5C6470", "#9AA3AE"),
    "Separator":       ("#E3E0D9", "#2A2E34"),
    # Semantic
    "Success":         ("#2F7D52", "#4CA877"),
    "Caution":         ("#B5701F", "#DE9A44"),
    "Critical":        ("#A63A3A", "#D96060"),
    # Stimulus mid-grey. Identical in both appearances ON PURPOSE — a Gabor must
    # modulate symmetrically around it, so it can never follow the theme.
    # docs/05-DESIGN-SYSTEM.md section 2, "Stimulus colours".
    "StimulusNeutral": ("#808080", "#808080"),
}


def components(hex_string: str) -> dict[str, str]:
    h = hex_string.lstrip("#")
    return {
        "red": f"0x{h[0:2].upper()}",
        "green": f"0x{h[2:4].upper()}",
        "blue": f"0x{h[4:6].upper()}",
        "alpha": "1.000",
    }


def colorset(light: str, dark: str) -> dict:
    def entry(hex_string: str, appearances: list | None = None) -> dict:
        item = {
            "idiom": "universal",
            "color": {"color-space": "srgb", "components": components(hex_string)},
        }
        if appearances:
            item["appearances"] = appearances
        return item

    return {
        "colors": [
            entry(light),
            entry(dark, [{"appearance": "luminosity", "value": "dark"}]),
        ],
        "info": {"author": "xcode", "version": 1},
    }


def main() -> None:
    CATALOG.mkdir(parents=True, exist_ok=True)

    root_contents = CATALOG / "Contents.json"
    root_contents.write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    )

    for name, (light, dark) in PALETTE.items():
        folder = CATALOG / f"{name}.colorset"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "Contents.json").write_text(
            json.dumps(colorset(light, dark), indent=2) + "\n"
        )
        print(f"  wrote {name}.colorset")

    # AppIcon placeholder — populated by scripts/make_icon.py in Phase 11.
    icon = CATALOG / "AppIcon.appiconset"
    icon.mkdir(parents=True, exist_ok=True)
    (icon / "Contents.json").write_text(
        json.dumps(
            {
                "images": [
                    {"idiom": "universal", "platform": "ios", "size": "1024x1024"},
                    {
                        "idiom": "universal",
                        "platform": "ios",
                        "size": "1024x1024",
                        "appearances": [
                            {"appearance": "luminosity", "value": "dark"}
                        ],
                    },
                    {
                        "idiom": "universal",
                        "platform": "ios",
                        "size": "1024x1024",
                        "appearances": [
                            {"appearance": "luminosity", "value": "tinted"}
                        ],
                    },
                ],
                "info": {"author": "xcode", "version": 1},
            },
            indent=2,
        )
        + "\n"
    )
    print("  wrote AppIcon.appiconset")
    print(f"\n{len(PALETTE)} colour sets generated in {CATALOG.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
