#!/usr/bin/env python3
"""
Bans multi-hop optional relationship traversal inside a SwiftData #Predicate.

WHY THIS SCRIPT EXISTS
----------------------
One line reached TestFlight and killed the app on every launch that had data:

    $0.session?.profile?.id == profileID

Core Data cannot build SQL for two chained optional relationship hops. It does
not fail politely — it throws an Objective-C exception from inside
NSSQLFetchRequestContext _createStatement, which is an uncaught exception, which
is SIGABRT. The screen that used it was the app's home screen.

The Swift compiler accepts it, because #Predicate type-checks as ordinary Swift.
The failure only appears when Core Data compiles the expression a SECOND time,
at runtime, into SQL. So a static check has to stand in for a compiler that is
not looking.

Eight CI runs were spent finding this instance. The check costs milliseconds and
runs on the free Linux runner, before any macOS minutes are spent.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# Two optional hops in a row: `?.something?.`
CHAINED = re.compile(r"\$\d[\w\.\?]*\?\.\w+\?\.")


def predicate_bodies(source: str):
    """Yield (line_number, body) for every #Predicate closure in the file."""
    for match in re.finditer(r"#Predicate", source):
        brace = source.find("{", match.end())
        if brace < 0:
            continue
        depth, index = 0, brace
        while index < len(source):
            if source[index] == "{":
                depth += 1
            elif source[index] == "}":
                depth -= 1
                if depth == 0:
                    break
            index += 1
        line = source[: match.start()].count("\n") + 1
        yield line, source[brace : index + 1]


def main() -> int:
    findings = []
    files = sorted((ROOT / "App").rglob("*.swift"))
    for path in files:
        source = path.read_text(encoding="utf-8", errors="replace")
        for line, body in predicate_bodies(source):
            for hop in set(CHAINED.findall(body)):
                findings.append((path.relative_to(ROOT), line, hop))

    if findings:
        print("check-predicates: FAIL")
        for path, line, hop in findings:
            print(f"  {path}:{line}: chained optional traversal `{hop}` in a #Predicate.")
        print()
        print("  Core Data cannot translate two optional relationship hops into SQL.")
        print("  It throws an ObjC exception at fetch time, which crashes the app.")
        print("  Split the query: fetch across ONE hop, then filter in memory.")
        print("  See SessionRepository.trials(for:exerciseID:limit:) for the pattern.")
        return 1

    print(f"check-predicates: PASS — {len(files)} file(s) scanned.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
