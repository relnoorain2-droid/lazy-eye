#!/usr/bin/env python3
"""
Cheap Swift sanity checks that run on Windows or the free Linux runner, in
about a second, and catch three classes of mistake that have each cost a full
macOS CI round (~4 minutes of billed time plus the wait):

  1. DUPLICATE DECLARATION — the same member declared twice against one type.
     Cost me CI run 34: `ThemePreference.displayName` already existed in an
     extension in Theme.swift and I added a second one next to the enum.

  2. TOP-LEVEL NAME CLASH — two types with the same name in one module.

  3. MEMBER OWNERSHIP — a member called on a type that does not declare it.
     Cost me CI run 18 (`isPro` is on `EntitlementStatus`, not
     `SubscriptionManager`) and run 35 (`resolvedHardestValue` is on
     `StaircaseConfiguration`, not `ExerciseDescriptor`).

WHAT THIS IS NOT
A type checker. It cannot infer the type of an arbitrary expression, so check 3
only fires for receivers that are spelled as type names (static access). An
earlier attempt at something cleverer produced twelve false alarms about members
that demonstrably existed, because a regex cannot track nested types. This one
tracks brace depth to find the real enclosing type, and stays quiet unless it is
confident. A checker that cries wolf is worse than no checker, because you stop
reading it.

Exit code 1 on a finding, so CI can run it before spending macOS minutes.
"""

import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIRS = ["App", "Tests", "UITests"]

TYPE_RE = re.compile(
    r'^\s*(?:@\w+\s+)*(?:public |internal |private |fileprivate |final )*'
    r'(struct|enum|class|extension|protocol)\s+([\w.]+)')
MEMBER_RE = re.compile(
    r'^\s*(?:@\w+\s+)*(?:public |private |fileprivate |internal |static |class )*'
    r'(?:var|let|func)\s+(\w+)')
CASE_RE = re.compile(r'^\s*case\s+([\w, ]+)')

# Receivers that look like types but belong to the SDK, or are Swift keywords.
IGNORED_RECEIVERS = {
    "Self", "Task", "Set", "Array", "Dictionary", "String", "Int", "Double",
    "Bool", "Date", "Calendar", "Bundle", "URL", "UUID", "Color", "Text",
    "Image", "Font", "Binding", "View", "Animation", "Locale", "TimeZone",
    "JSONDecoder", "JSONEncoder", "UserDefaults", "Logger", "Decimal",
}


def index_sources():
    """Map every declared member to the type(s) that own it, and every type to
    where it was declared.

    TWO RULES MAKE THIS QUIET ENOUGH TO BE USEFUL.

    · A declaration counts as a MEMBER only when its brace depth is exactly one
      inside its type. Without that, every `let cap = ...` inside a method reads
      as a property, and a test file with `let context` in twelve functions
      reports twelve duplicate declarations. The first draft of this script did
      exactly that and produced 138 findings, all false — which is worse than no
      script, because nobody reads the 139th.

    · Type names are QUALIFIED by their nesting. Four exercises each declare
      their own nested `Answer` enum, and those are four different types, not a
      clash."""
    members = defaultdict(list)      # (type, member) -> [locations]
    owners = defaultdict(set)        # member -> {types}
    types = defaultdict(list)        # type name -> [locations]

    for directory in SOURCE_DIRS:
        base = ROOT / directory
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.swift")):
            depth = 0
            stack = []
            rel = path.relative_to(ROOT)
            for number, line in enumerate(path.read_text(encoding="utf-8").split("\n"), 1):
                match = TYPE_RE.match(line)
                if match:
                    name = match.group(2)
                    # Qualified by nesting, so `GaborOrientationExercise.Answer`
                    # and `VernierExercise.Answer` are two types, not a clash.
                    qualified = ".".join([entry[1] for entry in stack] + [name])
                    stack.append((depth, qualified, match.group(1)))
                    if match.group(1) != "extension":
                        types[qualified].append(f"{rel}:{number}")

                # Members sit exactly one brace inside their type. Anything
                # deeper is a local, and locals are not members.
                if stack and depth == stack[-1][0] + 1:
                    owner, kind = stack[-1][1], stack[-1][2]
                    member = MEMBER_RE.match(line)
                    if member:
                        # A protocol requirement and its default implementation
                        # are the same name twice by design, and a stored
                        # property can coexist with a method of the same base
                        # name. Record enough to tell those apart from a real
                        # redeclaration.
                        members[(owner, member.group(1))].append(
                            (f"{rel}:{number}",
                             "func" in line.split(member.group(1))[0],
                             kind == "protocol"))
                        owners[member.group(1)].add(owner)
                    enum_case = CASE_RE.match(line)
                    if enum_case:
                        for name in enum_case.group(1).split(","):
                            name = name.split("(")[0].split("=")[0].strip()
                            if name.isidentifier():
                                owners[name].add(owner)

                depth += line.count("{") - line.count("}")
                while stack and depth <= stack[-1][0]:
                    stack.pop()

    return members, owners, types


def main() -> int:
    members, owners, types = index_sources()
    problems = []

    # 1. Duplicate declarations. Overloads legitimately share a name, so only
    #    report when the duplicates are NOT functions.
    for (owner, member), entries in sorted(members.items()):
        if len(entries) < 2:
            continue
        # Any function in the group makes the names distinguishable — overloads,
        # or a stored property alongside a method of the same base name.
        if any(is_func for _, is_func, _ in entries):
            continue
        # A protocol requirement plus its default implementation is two
        # declarations of one name, on purpose.
        if any(in_protocol for _, _, in_protocol in entries):
            continue
        problems.append(
            f"duplicate declaration of '{owner}.{member}':\n      "
            + "\n      ".join(location for location, _, _ in entries))

    # 2. Two types with one name.
    for name, locations in sorted(types.items()):
        if len(locations) > 1 and len(set(locations)) > 1:
            problems.append(
                f"two types named '{name}':\n      " + "\n      ".join(locations))

    # 3. Static access to a member the named type does not declare.
    short_names = {name.split(".")[-1] for name in types}
    for directory in SOURCE_DIRS:
        base = ROOT / directory
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.swift")):
            text = path.read_text(encoding="utf-8")
            text = re.sub(r'//.*', '', text)
            text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
            rel = path.relative_to(ROOT)
            for receiver, member in sorted(set(re.findall(r'\b([A-Z]\w+)\.(\w+)\b', text))):
                if receiver in IGNORED_RECEIVERS or receiver not in short_names:
                    continue
                if member not in owners:
                    continue
                # Owners are stored qualified; call sites write the short name.
                if any(o.split(".")[-1] == receiver for o in owners[member]):
                    continue
                problems.append(
                    f"{rel}: '{receiver}.{member}' — '{member}' is declared on "
                    f"{sorted(owners[member])}, not on '{receiver}'")

    if problems:
        print(f"check-symbols: FAIL — {len(problems)} finding(s)\n")
        for problem in problems:
            print(f"  · {problem}")
        print("\nEach of these is a compile error the macOS runner would find "
              "in four minutes.")
        return 1

    print(f"check-symbols: PASS — {len(types)} types, {len(members)} members indexed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
