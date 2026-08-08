#!/usr/bin/env python3
"""
check_app_icon.py - validates the app icon against Apple's upload rules.

WHY THIS EXISTS
TestFlight build 8 archived, signed and uploaded successfully, then died in
Apple's validation with:

    Validation failed (409) Missing required icon file. The bundle does not
    contain an app icon for iPhone / iPod Touch of exactly '120x120' pixels.

The cause was an AppIcon.appiconset whose Contents.json declared three entries
and contained zero PNG files. Everything upstream of Apple was perfectly happy:
the catalog was valid JSON, Xcode compiled it without complaint, the archive
built. The failure only appeared after a full macOS build and upload - roughly
five minutes of CI plus the wait for Apple to answer.

This script reproduces that specific check in about ten milliseconds on the free
Linux runner, before the macOS job even starts.

WHY IT PARSES THE PNG HEADER BY HAND INSTEAD OF USING PILLOW
The lint job has no third-party dependencies and adding numpy and Pillow to it
would cost more setup time than the check itself takes. A PNG's IHDR chunk sits
at a fixed offset and carries width, height, bit depth and colour type - which
is exactly, and only, what Apple's rules are about.

WHAT APPLE ACTUALLY REQUIRES OF THE 1024x1024 SOURCE
  - exactly 1024x1024
  - no alpha channel (colour type must be 2 = truecolour, not 6 = truecolour+alpha)
  - not indexed or greyscale
  - and, obviously, the file has to exist

    python3 scripts/check_app_icon.py
"""

from __future__ import annotations
import json
import pathlib
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ICONSET = ROOT / "App" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"

REQUIRED_SIZE = 1024

# PNG colour types, from the spec. Only 2 is acceptable for an app icon.
COLOUR_TYPES = {
    0: "greyscale",
    2: "truecolour (RGB)",
    3: "indexed",
    4: "greyscale + alpha",
    6: "truecolour + alpha (RGBA)",
}
ACCEPTABLE_COLOUR_TYPE = 2

errors: list[str] = []


def fail(message: str) -> None:
    errors.append(message)
    # GitHub Actions surfaces this as an inline annotation on the run.
    print(f"::error::{message}")


def read_png_header(path: pathlib.Path) -> tuple[int, int, int, int] | None:
    """Returns (width, height, bit_depth, colour_type) from the IHDR chunk."""
    with path.open("rb") as handle:
        signature = handle.read(8)
        if signature != b"\x89PNG\r\n\x1a\n":
            return None
        # 4-byte chunk length, 4-byte type, then the IHDR payload.
        handle.read(4)
        if handle.read(4) != b"IHDR":
            return None
        width, height, bit_depth, colour_type = struct.unpack(">IIBB",
                                                              handle.read(10))
    return width, height, bit_depth, colour_type


def main() -> int:
    print("app-icon check")

    if not ICONSET.is_dir():
        fail(f"No icon set at {ICONSET.relative_to(ROOT)}")
        return 1

    manifest = ICONSET / "Contents.json"
    if not manifest.is_file():
        fail("AppIcon.appiconset has no Contents.json")
        return 1

    try:
        contents = json.loads(manifest.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        fail(f"Contents.json is not valid JSON: {error}")
        return 1

    images = contents.get("images", [])
    if not images:
        fail("Contents.json declares no images")
        return 1

    declared = 0
    for entry in images:
        appearance = "any"
        for item in entry.get("appearances", []):
            appearance = item.get("value", appearance)

        filename = entry.get("filename")
        if not filename:
            # THE EXACT BUILD-8 FAILURE. An entry with no filename is a
            # declaration with nothing behind it, and Apple only notices after
            # the upload.
            fail(f"Icon entry ({appearance} appearance) has no filename — "
                 f"this is what made Apple reject build 8")
            continue

        declared += 1
        path = ICONSET / filename
        if not path.is_file():
            fail(f"Contents.json references {filename}, which does not exist")
            continue

        header = read_png_header(path)
        if header is None:
            fail(f"{filename} is not a readable PNG")
            continue

        width, height, bit_depth, colour_type = header
        detail = (f"{width}x{height}, {bit_depth}-bit, "
                  f"{COLOUR_TYPES.get(colour_type, colour_type)}")

        ok = True
        if (width, height) != (REQUIRED_SIZE, REQUIRED_SIZE):
            fail(f"{filename} is {width}x{height}; Apple requires exactly "
                 f"{REQUIRED_SIZE}x{REQUIRED_SIZE}")
            ok = False
        if colour_type != ACCEPTABLE_COLOUR_TYPE:
            fail(f"{filename} is {COLOUR_TYPES.get(colour_type, colour_type)}; "
                 f"app icons must have no alpha channel and must not be "
                 f"indexed or greyscale")
            ok = False

        print(f"  {'ok  ' if ok else 'FAIL'} {filename:<24} {detail}")

    if declared == 0:
        fail("No icon entry has a filename — the icon set is empty")

    if errors:
        print(f"\napp-icon check: FAIL — {len(errors)} problem(s)")
        print("Run: python3 scripts/make_icon.py")
        return 1

    print(f"\napp-icon check: PASS — {declared} image(s) meet Apple's rules.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
