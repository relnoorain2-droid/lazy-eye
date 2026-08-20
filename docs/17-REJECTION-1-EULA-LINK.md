# 17 — REJECTION 1: EULA LINK MISSING FROM THE DESCRIPTION

**Status: metadata fix. No new build, no new binary, no code change.**

---

## What Apple said

> The submission offers auto-renewable subscriptions but does not include a
> functional link to the Terms of Use (EULA) in the app metadata that appears on
> the app's App Store product page.

## What it actually means

The app already links to Apple's standard EULA **inside** the app — it is on the
paywall next to Privacy and Manage, and in Profile → About → Subscription Terms
(`LegalDocumentView.swift:280`).

That is not what this rule asks for. For auto-renewable subscriptions, the Terms
of Use link must appear in the **App Store product page metadata** — the text a
customer reads *before* downloading, so they can see the terms without
installing anything. In-app links do not satisfy it, which is why an otherwise
compliant app got caught.

This is an automated pre-review check. It never reached a human reviewer, which
is also why nothing else was flagged: the review did not proceed far enough to
look at anything.

---

## The fix — two fields, five minutes

### 1. App Store Connect → your app → **App Information** → **Description**

Append these two lines to the very end of the existing description:

```
Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: https://YOUR-DOMAIN/privacy-policy
```

Rules that matter:

- It must be the **full URL including `https://`**. A bare
  `apple.com/legal/...` is not a functional link and fails the same check.
- Put it at the END. It does not need to be prominent, only present.
- The description has a 4000-character limit and the current text is 3217, so
  there is room. `docs/15-SUBMISSION-PACK.md` holds the description; add the
  lines there too so the two do not drift.

### 2. App Store Connect → **App Privacy** → **Privacy Policy URL**

Must be filled and must resolve. This is a separate required field from the
description line above.

---

## Then

**Resubmit the existing build.** Nothing about the binary changed, so there is no
need to upload a new one — App Store Connect lets you edit metadata and submit
again against the same build.

---

## Why this was missed

`docs/15-SUBMISSION-PACK.md` listed the EULA under the paywall requirements and
under App Review notes, and both were satisfied. It did not list it as a
DESCRIPTION requirement, because the rule is about where the link appears rather
than whether it exists — and the pack was written around "does the app comply",
not "does the product page comply".

The submission checklist in section 7 of that document has been corrected.
