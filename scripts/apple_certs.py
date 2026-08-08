#!/usr/bin/env python3
"""
apple_certs.py - inspect (and optionally revoke) Apple signing certificates.

WHY THIS IS TWO COMMANDS, NOT ONE
Revoking a distribution certificate breaks code signing for EVERY app that was
signed with it. You have a dozen apps in App Store Connect, several already
distributed and one in review. An "auto-revoke the oldest" script could take out
the certificate an app in review depends on, and revocation cannot be undone -
you would re-sign and resubmit everything affected.

So this script defaults to LIST, which is read-only and safe. Revoking requires
you to name a specific certificate id AND type a confirmation. That is
deliberate friction on an irreversible action.

SETUP (once)
    pip install pyjwt cryptography --break-system-packages

USAGE
    # Safe. Shows every certificate, its type, expiry, and days remaining.
    python scripts/apple_certs.py list

    # Irreversible. Only after you have decided which one.
    python scripts/apple_certs.py revoke --id ABC123XYZ --confirm REVOKE

ENVIRONMENT
    ASC_KEY_ID     e.g. A648X8UC93
    ASC_ISSUER_ID  e.g. 8bbf6004-0e8e-4ec0-8475-4020300bd459
    ASC_KEY_PATH   path to AuthKey_A648X8UC93.p8   (or ASC_KEY_P8 with contents)
"""

from __future__ import annotations
import argparse
import datetime as dt
import json
import os
import sys
import time
import urllib.request
import urllib.error

API = "https://api.appstoreconnect.apple.com/v1"

# Apple's documented limits. Distribution is the one that bites.
LIMITS = {
    "DISTRIBUTION": 3,
    "IOS_DISTRIBUTION": 3,
    "DEVELOPMENT": 2,
    "IOS_DEVELOPMENT": 2,
}


def fail(message: str) -> None:
    print(f"\nERROR: {message}\n", file=sys.stderr)
    sys.exit(1)


def load_key() -> tuple[str, str, str]:
    key_id = os.environ.get("ASC_KEY_ID", "").strip()
    issuer = os.environ.get("ASC_ISSUER_ID", "").strip()
    if not key_id or not issuer:
        fail("Set ASC_KEY_ID and ASC_ISSUER_ID first. See the header of this file.")

    contents = os.environ.get("ASC_KEY_P8", "")
    if not contents:
        path = os.environ.get("ASC_KEY_PATH", "").strip().strip('"')
        if not path:
            fail("Set ASC_KEY_PATH to your AuthKey_*.p8 file, or ASC_KEY_P8 to its contents.")
        if not os.path.isfile(path):
            fail(f"No file at: {path}")
        with open(path, "r", encoding="utf-8") as handle:
            contents = handle.read()

    if "BEGIN PRIVATE KEY" not in contents:
        fail("That does not look like a .p8 private key (no BEGIN PRIVATE KEY line).")
    return key_id, issuer, contents


def make_token(key_id: str, issuer: str, private_key: str) -> str:
    try:
        import jwt  # PyJWT
    except ImportError:
        fail("Missing dependency. Run:  pip install pyjwt cryptography --break-system-packages")

    now = int(time.time())
    return jwt.encode(
        {"iss": issuer, "iat": now, "exp": now + 19 * 60, "aud": "appstoreconnect-v1"},
        private_key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def call(token: str, path: str, method: str = "GET") -> dict:
    request = urllib.request.Request(
        f"{API}{path}",
        method=method,
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = response.read().decode()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode()
        fail(f"Apple returned {error.code}\n{detail}")
    except urllib.error.URLError as error:
        fail(f"Network problem: {error}")
    return {}


def cmd_list(token: str) -> None:
    data = call(token, "/certificates?limit=200").get("data", [])
    if not data:
        print("No certificates found on this account.")
        return

    rows = []
    for item in data:
        attributes = item.get("attributes", {})
        expires_raw = attributes.get("expirationDate", "")
        try:
            expires = dt.datetime.fromisoformat(expires_raw.replace("Z", "+00:00"))
            days = (expires - dt.datetime.now(dt.timezone.utc)).days
            expiry = expires.strftime("%Y-%m-%d")
        except Exception:
            days, expiry = None, expires_raw[:10] or "?"
        rows.append({
            "id": item.get("id", "?"),
            "type": attributes.get("certificateType", "?"),
            "name": (attributes.get("displayName") or attributes.get("name") or "")[:38],
            "expiry": expiry,
            "days": days,
        })

    rows.sort(key=lambda r: (r["type"], r["expiry"]))

    print(f"\n{len(rows)} certificate(s) on this account\n")
    print(f"{'ID':<12} {'TYPE':<26} {'EXPIRES':<12} {'DAYS':>6}  NAME")
    print("-" * 100)
    for row in rows:
        days = "expired" if row["days"] is not None and row["days"] < 0 else (
            str(row["days"]) if row["days"] is not None else "?")
        flag = "  <-- EXPIRED, safe to revoke" if (row["days"] or 0) < 0 else ""
        print(f"{row['id']:<12} {row['type']:<26} {row['expiry']:<12} {days:>6}  {row['name']}{flag}")

    print("\nCounts by type, against Apple's limits:")
    counts: dict[str, int] = {}
    for row in rows:
        counts[row["type"]] = counts.get(row["type"], 0) + 1

    blocked = False
    for cert_type, count in sorted(counts.items()):
        limit = LIMITS.get(cert_type)
        if limit and count >= limit:
            print(f"  {cert_type:<26} {count} / {limit}   AT LIMIT - this is why match cannot create one")
            blocked = True
        elif limit:
            print(f"  {cert_type:<26} {count} / {limit}   room available")
        else:
            print(f"  {cert_type:<26} {count}")

    print()
    if not blocked:
        print("You are NOT at the distribution limit. The build failure is something else -")
        print("send me the error text from the failing step instead of revoking anything.")
    else:
        expired = [r for r in rows if (r["days"] or 0) < 0]
        if expired:
            print("Revoke an EXPIRED one first - those are already useless:")
            for row in expired:
                print(f"    python scripts/apple_certs.py revoke --id {row['id']} --confirm REVOKE")
        else:
            print("Nothing is expired, so any revoke will break a working app.")
            print("Before choosing, check which of your apps still needs each certificate.")
            print("Certificates created by Expo or rork belong to those build services -")
            print("revoking one means that app can no longer be rebuilt until it makes a new one.")
    print()


def cmd_revoke(token: str, cert_id: str, confirm: str) -> None:
    if confirm != "REVOKE":
        fail("Refusing. Pass --confirm REVOKE to acknowledge this cannot be undone.")

    data = call(token, "/certificates?limit=200").get("data", [])
    target = next((c for c in data if c.get("id") == cert_id), None)
    if not target:
        fail(f"No certificate with id {cert_id} on this account. Run 'list' first.")

    attributes = target.get("attributes", {})
    print("\nAbout to permanently revoke:")
    print(f"  ID      : {cert_id}")
    print(f"  Type    : {attributes.get('certificateType')}")
    print(f"  Name    : {attributes.get('displayName') or attributes.get('name')}")
    print(f"  Expires : {attributes.get('expirationDate', '?')[:10]}")
    print("\nEvery app signed with this certificate will need re-signing.\n")

    call(token, f"/certificates/{cert_id}", method="DELETE")
    print(f"Revoked {cert_id}.")
    print("Now re-run: Actions -> Release to TestFlight -> Run workflow\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list", help="Show all certificates (read-only, safe)")
    revoke = sub.add_parser("revoke", help="Permanently revoke one certificate")
    revoke.add_argument("--id", required=True, help="Certificate id from 'list'")
    revoke.add_argument("--confirm", default="", help="Must be exactly: REVOKE")
    args = parser.parse_args()

    key_id, issuer, private_key = load_key()
    token = make_token(key_id, issuer, private_key)

    if args.command == "list":
        cmd_list(token)
    else:
        cmd_revoke(token, args.id, args.confirm)


if __name__ == "__main__":
    main()
