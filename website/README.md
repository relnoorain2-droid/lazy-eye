# Website pages

The four public pages App Store Connect needs, plus what to do with each.

**Site:** `https://sites.google.com/view/amblyolazyeyetraining/`

---

## Status

| Page | URL | Source | Status |
|---|---|---|---|
| Privacy Policy | [`/privacy-policy`](https://sites.google.com/view/amblyolazyeyetraining/privacy-policy) | `App/Resources/Legal/privacy-policy.md` | ✅ **Live, verified 2026-08-06** |
| Evidence and Methods | [`/evidence-and-methods`](https://sites.google.com/view/amblyolazyeyetraining/evidence-and-methods) | `App/Resources/Legal/evidence-and-methods.md` | ✅ **Live** |
| Support | [`/support`](https://sites.google.com/view/amblyolazyeyetraining/support) | `website/support.md` | ✅ **Live, verified 2026-08-06** |
| Terms of Use (EULA) | Apple's standard EULA | — | ✅ Nothing to publish, see below |

**All three pages fetched and confirmed returning content on 2026-08-06.**
Dead metadata links are an instant rejection, so re-check them the week you
submit — Google Sites pages can be unpublished by accident.

---

## Contact email

**`ksbpstech@gmail.com`** — taken from the live site and now matching everywhere
in the app.

The app originally said `support@amblyo.app`, which did not exist. That kind of
mismatch matters more than it looks: a reviewer who emails the address in your
privacy policy and gets a bounce has a concrete reason to reject, and a user who
does the same leaves a one-star review. Aligned in:

- `App/Features/Legal/LegalDocumentView.swift` (`ExternalLinks.supportEmail`)
- `App/Resources/Legal/privacy-policy.md`
- `App/Resources/Legal/subscription-terms.md`
- `website/support.md`

**If you later set up `support@amblyo.app`, change it in all four places at once**
— and on the Google Site.

---

## Terms of Use — nothing to write

**Use Apple's Standard EULA.** Leave the "License Agreement" field in App Store
Connect on the default, and it applies automatically.

Why not a custom one:

- Apple's Standard EULA already applies to every app by default.
- A custom EULA must be **at least as protective of the user** as Apple's. If it
  is not, App Review rejects it. So writing your own adds risk and buys nothing.
- Where the app needs a Terms of Use link — on the paywall, per Guideline
  3.1.2 — it points at Apple's published URL:
  `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`

**But note the gap.** Apple's Standard EULA says nothing about auto-renewal, and
Apple separately requires that disclosure in two places: the app description and
the paywall. That is handled by
`App/Resources/Legal/subscription-terms.md`, which is an in-app disclosure
screen, not a licence agreement. Do not confuse the two — the auto-renew text is
a common 3.1.2 rejection cause and Apple's EULA does not cover it for you.

---

## Keep the copies identical

The in-app screens and the public pages must say the same thing. A reviewer who
compares them and finds a discrepancy treats it as a red flag on a medical-category
app.

| In-app screen | Public page |
|---|---|
| `App/Resources/Legal/privacy-policy.md` | `/privacy-policy` |
| `App/Resources/Legal/evidence-and-methods.md` | `/evidence-and-methods` |
| `App/Resources/Legal/medical-disclaimer.md` | included inside `/support` |
| `App/Resources/Legal/subscription-terms.md` | in-app only (also in the App Store description) |

When you edit one, edit both. Both sides are covered by `scripts/lint_claims.py`
for banned medical language.

---

## App Store Connect fields

Paste these into App Store Connect in Phase 12.

| Field | Value |
|---|---|
| Privacy Policy URL | `https://sites.google.com/view/amblyolazyeyetraining/privacy-policy` |
| Support URL | `https://sites.google.com/view/amblyolazyeyetraining/support` |
| Marketing URL | **Leave blank** |
| License Agreement | **Leave as Apple's Standard EULA** |
| Contact email | `ksbpstech@gmail.com` |

**Why Marketing URL is blank:** your site has no home page — the site title links
to `/privacy-policy`. A "marketing URL" that lands on a privacy policy looks
broken. The field is optional, so leave it empty rather than pointing it
somewhere odd. If you build a proper landing page later, add it then.

All URLs must return 200 before submission.

---

## Later — worth doing, not required

`09-ASO-METADATA.md` §9 suggests publishing the 12 Learn articles as public
pages under `/learn/...`. They rank for long-tail searches like "lazy eye
exercises for adults", give App Review a credible-looking site, and each one can
end with an App Store link. One article a week, written from
`01-RESEARCH-BRIEF.md`, all subject to the `08` §3 language rules —
**including the URL slugs.**
