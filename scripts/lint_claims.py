#!/usr/bin/env python3
"""
lint_claims.py — fails the build if banned medical-claim language reaches
user-visible text.

Rationale: App Store Guideline 1.4.1. See docs/08-COMPLIANCE-LEGAL.md section 3.
A single stray "treatment" in a screenshot caption or a Swift string literal is
enough to trigger a rejection that costs a week of review turnaround. This is
the cheapest insurance in the project.

WHAT IT SCANS
  App/**/*.swift            -> string literals only (not comments, not code)
  App/Resources/**/*.md     -> whole file, minus allow-listed blocks
  App/Resources/**/*.xcstrings, *.strings  -> whole file
  fastlane/metadata/**/*.txt -> whole file
  docs/screenshot-captions.json -> whole file

WHAT IT DOES NOT SCAN
  docs/**  -> the specs legitimately discuss the banned words in order to ban them.

ALLOW-LISTING
  Some banned words are required in disclaimers ("does not diagnose, treat, cure
  or prevent"). Wrap those regions in markers:

      <!-- claims-lint:disable -->
      ...disclaimer text...
      <!-- claims-lint:enable -->

  In Swift, put // claims-lint:disable-next-line above the literal.

USAGE
  python3 scripts/lint_claims.py            # scan, exit 1 on any hit
  python3 scripts/lint_claims.py --list     # print the banned list and exit
"""

from __future__ import annotations
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# --------------------------------------------------------------------------
# The banned list. Source of truth is docs/08-COMPLIANCE-LEGAL.md section 3.
# Keep the two in sync; if you add a term here, add it there.
# --------------------------------------------------------------------------

BANNED = [
    # treatment / cure claims
    r"treats?\b", r"treating\b", r"treatment[s]?\b",
    r"therap(y|ies|eutic)\b",
    r"cure[sd]?\b", r"curing\b",
    r"heal(s|ed|ing)?\b",
    r"remed(y|ies)\b",
    # diagnosis claims
    r"diagnos(e|es|ed|ing|is|tic)\b",
    r"screen(s|ing)? for\b",
    r"test(s|ing)? for\b",
    # authority borrowing
    r"\bFDA\b", r"FDA-?cleared\b", r"FDA-?approved\b",
    r"clinically (proven|validated|tested)\b",
    r"medically (proven|approved)\b",
    r"doctor[- ]recommended\b",
    r"prescription\b",
    r"medical device\b",
    # outcome promises
    r"improve[sd]? your (vision|eyesight|sight)\b",
    r"restore[sd]? (vision|eyesight|sight)\b",
    r"correct(s|ed)? (your )?lazy eye\b",
    r"straighten(s|ed)? your eye",
    r"fix(es|ed)? your (eye|vision|sight)",
    r"guarantee[sd]?\b",
    r"proven results\b",
    r"will improve\b",
    r"replace[sd]? patching\b",
    r"alternative to patching\b",
    # the unsafe advice the reference app gave (docs/14 R4)
    r"fatigue (is|indicates) a (beneficial|good|positive)",
    r"push through (the )?(strain|fatigue|pain)",
    r"dark room\b",
]

# Phrases that contain a banned substring but are themselves REQUIRED.
# Checked before the banned patterns; a line matching any of these is skipped.
ALLOWED_PHRASES = [
    r"not a medical device",
    r"is not a medical treatment",
    r"does not diagnose, treat, cure,? or prevent",
    r"not a substitute for professional medical care",
    r"not a substitute for care from a qualified eye care professional",
    r"not a diagnostic tool",
    r"those (studies|trials) tested .{0,60}not this app",
    r"was not studied",
]

DISABLE_BLOCK = re.compile(
    r"<!--\s*claims-lint:disable\s*-->.*?<!--\s*claims-lint:enable\s*-->",
    re.DOTALL | re.IGNORECASE,
)
DISABLE_NEXT_LINE = re.compile(r"claims-lint:disable-next-line", re.IGNORECASE)

# Swift string literals: "..." and """...""" (naive but adequate — we want
# false positives to be loud, not silent).
SWIFT_MULTILINE = re.compile(r'"""(.*?)"""', re.DOTALL)
SWIFT_LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')

BANNED_RE = [(p, re.compile(p, re.IGNORECASE)) for p in BANNED]
ALLOWED_RE = [re.compile(p, re.IGNORECASE) for p in ALLOWED_PHRASES]

TARGETS = [
    ("App", ("*.swift",)),
    ("App/Resources", ("*.md", "*.strings", "*.xcstrings", "*.json")),
    ("fastlane/metadata", ("*.txt", "*.md")),
    ("docs", ("screenshot-captions.json",)),
]


def is_allowed(line: str) -> bool:
    return any(r.search(line) for r in ALLOWED_RE)


def scan_text(text: str, path: Path, offset_map=None) -> list[tuple[int, str, str]]:
    """Return [(line_no, pattern, line_text)] for each violation."""
    text = DISABLE_BLOCK.sub(lambda m: "\n" * m.group(0).count("\n"), text)
    hits = []
    prev_disabled = False
    for i, line in enumerate(text.splitlines(), start=1):
        if prev_disabled:
            prev_disabled = DISABLE_NEXT_LINE.search(line) is not None
            continue
        if DISABLE_NEXT_LINE.search(line):
            prev_disabled = True
            continue
        if is_allowed(line):
            continue
        for pattern, rx in BANNED_RE:
            m = rx.search(line)
            if m:
                real_line = offset_map(i) if offset_map else i
                hits.append((real_line, m.group(0), line.strip()))
                break
    return hits


def scan_swift(path: Path) -> list[tuple[int, str, str]]:
    """Only string literals in Swift — comments and identifiers are exempt."""
    src = path.read_text(encoding="utf-8", errors="replace")
    lines = src.splitlines()
    hits = []
    disabled_lines = {
        i + 2 for i, l in enumerate(lines) if DISABLE_NEXT_LINE.search(l)
    }
    for i, line in enumerate(lines, start=1):
        if i in disabled_lines:
            continue
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("///"):
            continue
        literals = SWIFT_MULTILINE.findall(line) + [
            m.group(1) for m in SWIFT_LITERAL.finditer(line)
        ]
        for lit in literals:
            if is_allowed(lit):
                continue
            for pattern, rx in BANNED_RE:
                m = rx.search(lit)
                if m:
                    hits.append((i, m.group(0), stripped))
                    break
    # multiline literals spanning lines
    for m in SWIFT_MULTILINE.finditer(src):
        block = m.group(1)
        start_line = src[: m.start()].count("\n") + 1
        for j, bl in enumerate(block.splitlines()):
            ln = start_line + j
            if ln in disabled_lines or is_allowed(bl):
                continue
            for pattern, rx in BANNED_RE:
                mm = rx.search(bl)
                if mm and not any(h[0] == ln for h in hits):
                    hits.append((ln, mm.group(0), bl.strip()))
                    break
    return hits


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print banned patterns")
    args = ap.parse_args()

    if args.list:
        print("Banned patterns (docs/08-COMPLIANCE-LEGAL.md section 3):")
        for p in BANNED:
            print("  " + p)
        print("\nAllowed phrases (exempt):")
        for p in ALLOWED_PHRASES:
            print("  " + p)
        return 0

    all_hits: list[tuple[Path, int, str, str]] = []
    scanned = 0

    for rel, globs in TARGETS:
        base = ROOT / rel
        if not base.exists():
            continue
        for g in globs:
            for path in sorted(base.rglob(g)):
                if any(part in {".git", "DerivedData", "build"} for part in path.parts):
                    continue
                scanned += 1
                if path.suffix == ".swift":
                    hits = scan_swift(path)
                else:
                    hits = scan_text(
                        path.read_text(encoding="utf-8", errors="replace"), path
                    )
                for ln, term, text in hits:
                    all_hits.append((path, ln, term, text))

    print(f"claims-lint: scanned {scanned} file(s)")

    if not all_hits:
        print("claims-lint: PASS — no banned medical-claim language found.")
        return 0

    print(f"\nclaims-lint: FAIL — {len(all_hits)} violation(s)\n")
    for path, ln, term, text in all_hits:
        rel = path.relative_to(ROOT)
        print(f"  {rel}:{ln}")
        print(f"      banned term: {term!r}")
        print(f"      line: {text[:160]}")
        print()
    print("See docs/08-COMPLIANCE-LEGAL.md section 3 for approved alternatives.")
    print("If this text is a required disclaimer, wrap it in")
    print("  <!-- claims-lint:disable --> ... <!-- claims-lint:enable -->")
    print("or add // claims-lint:disable-next-line above the Swift literal.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
