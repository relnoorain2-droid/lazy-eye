# 00 — MASTER PLAN

**Project:** Amblyo — Lazy Eye Training (working name, see `09-ASO-METADATA.md`)
**Platform:** iOS 18+ / iPadOS 18+ (iPad-first), Swift 6 + SwiftUI
**Owner:** noorul ain
**Repo root:** `E:\Lazy Eye`
**Created:** 2026-08-06

---

## 0. HOW TO USE THIS PLAN (read this first, every session)

This project is split into **self-contained phases**. Each phase can be started cold. If a session ends
mid-way, the next session opens `13-BUILD-ROADMAP.md`, finds the first phase whose checkbox is
unticked, reads that phase's "Entry state" block, and continues.

**Rules for every session:**

1. Read `00-MASTER-PLAN.md` (this file) → then `13-BUILD-ROADMAP.md` → find current phase.
2. Read the 2–3 spec docs that phase names in its "Required reading" list. Do not read all docs.
3. Do the work. Write real files under `App/`.
4. Tick the phase checkbox in `13-BUILD-ROADMAP.md` and append a line to `PROGRESS.md`.
5. Phases marked **[RESEARCH-GATE]** must run fresh web research before coding — the underlying
   Apple APIs, App Review rules and screenshot specs change every year.

---

## 1. WHAT WE ARE BUILDING, IN ONE PARAGRAPH

A premium, iPad-first vision-training app for amblyopia (lazy eye). It ships two training tracks:
a **monocular track** (classic patched-eye exercises — no accessory needed) and a **dichoptic track**
(contrast-rebalanced, different image to each eye, using cheap red-cyan anaglyph glasses) which is the
approach with the strongest published evidence. On top of the exercises sits an **on-device adaptive
engine** — staircase psychophysics plus Apple's on-device Foundation Models for plain-language
coaching — that personalises difficulty and writes a weekly plan, with zero network calls and zero
third-party AI API. Monetised with weekly / monthly / yearly auto-renewing subscriptions via StoreKit 2,
no RevenueCat. Positioned as **vision training and wellness**, not as a medical treatment.

---

## 2. NON-NEGOTIABLE CONSTRAINTS (decided, do not revisit)

| # | Constraint | Why |
|---|---|---|
| C1 | **Wellness positioning, never "treats amblyopia"** | Guideline 1.4.1 / 5.1.1. Real amblyopia treatment (Luminopia, CureSight) is FDA-cleared and prescription-only. Claiming treatment gets us rejected and is not honest to parents. |
| C2 | **iPad-first layout, iPhone fully supported** | User's primary audience. Larger display = larger effective visual angle = better exercise quality. |
| C3 | **StoreKit 2 direct, no RevenueCat** | User decision. On-device receipt verification via `Transaction.currentEntitlements`. |
| C4 | **Privacy policy + EULA rendered as in-app screens** from bundled Markdown, no external links in the paywall | User decision. External copies still needed in App Store Connect metadata. |
| C5 | **No third-party AI API.** All "AI" is on-device: Apple Foundation Models framework + our own Bayesian/staircase adaptive engine | User has no OpenAI key; also far better for a health app's privacy story. |
| C6 | **Every sound is opt-out and OFF by default** | The #1 complaint on the reference app (see `14-REVIEW-COMPLAINTS-MATRIX.md`). |
| C7 | **Build and ship from GitHub Actions macOS runners** | User has no Mac. |
| C8 | **Prices: $2.99/wk, $9.99/mo, $29.99/yr, 7-day trial on yearly** | Locked 2026-08-06 in `DECISIONS.md`. Yearly is 5.2× cheaper than weekly — a defensible "save 81%" ladder. |
| C9 | **Every medical-adjacent statement carries a citation** | Guideline 1.4.1 demands disclosed methodology. See `08-COMPLIANCE-LEGAL.md` §3A — but note carefully what citations do **not** license. |

---

## 3. DOCUMENT MAP

| File | What it contains | When you need it |
|---|---|---|
| `00-MASTER-PLAN.md` | This file. Index, constraints, resume protocol. | Every session |
| `01-RESEARCH-BRIEF.md` | Clinical evidence, dosing, competitor teardown, cited sources | Before writing any exercise or marketing copy |
| `02-PRD.md` | Personas, user stories, feature list with MoSCoW, success metrics | Phases 1–3 |
| `03-EXERCISE-CATALOG.md` | All 32 exercises: mechanic, parameters, evidence tier, difficulty curve | Phases 5–8 |
| `04-ARCHITECTURE.md` | Module map, SwiftData model, folder structure, rendering strategy | Phase 2 onward |
| `05-DESIGN-SYSTEM.md` | Colour tokens, type scale, components, iPad/iPhone layout rules, kid vs adult modes | Phase 3 onward |
| `06-AI-ENGINE-SPEC.md` | Adaptive staircase, progress analysis, Foundation Models prompts, HealthKit | Phase 9 |
| `07-MONETIZATION-PAYWALL.md` | StoreKit 2 code plan, 3 products, paywall spec, trial, restore, EULA | Phase 10 |
| `08-COMPLIANCE-LEGAL.md` | Guideline-by-guideline checklist, disclaimer copy, privacy policy text, EULA text, App Privacy answers | Phases 10–13 |
| `09-ASO-METADATA.md` | App name shortlist, subtitle, 100-char keyword field, 4000-char description, promo text, localisation plan | Phase 12 |
| `10-APP-ICON-SPEC.md` | Icon concept, geometry, colour, deliverable sizes, generation script | Phase 11 |
| `11-SCREENSHOTS-SPEC.md` | Exact frames, caption copy, sizes, how to render without a Mac | Phase 12 |
| `12-CICD-NO-MAC.md` | GitHub Actions workflow, fastlane, signing, TestFlight | Phase 4 (early!) and Phase 13 |
| `13-BUILD-ROADMAP.md` | **The actual to-do list.** 14 phases with entry state + acceptance criteria | Every session |
| `14-REVIEW-COMPLAINTS-MATRIX.md` | Every complaint from the reference app → our specific fix → where it's implemented | Phases 3, 6, 10 |
| `PROGRESS.md` | Append-only session log | Every session |

---

## 4. THE 14 PHASES AT A GLANCE

Full detail in `13-BUILD-ROADMAP.md`.

```
P0  Decisions & naming lock            ← docs only
P1  Xcode project scaffold + SPM       ← project.yml / XcodeGen, no Mac needed to author
P2  Data layer (SwiftData) + settings
P3  Design system + onboarding flow
P4  [RESEARCH-GATE] CI green on GitHub Actions  ← do this EARLY, before lots of code
P5  Exercise engine core (render loop, session runner, timer, pause)
P6  Monocular exercise pack (14 exercises)
P7  Anaglyph calibration + dichoptic engine
P8  Dichoptic exercise pack (10 exercises) + 8 binocular games
P9  Adaptive engine, progress analytics, Foundation Models coach, HealthKit
P10 [RESEARCH-GATE] StoreKit 2 + paywall + legal screens
P11 App icon + brand assets
P12 [RESEARCH-GATE] ASO metadata + screenshots + preview video
P13 [RESEARCH-GATE] Submission: App Privacy, age rating, review notes, TestFlight → release
```

---

## 5. WHAT MAKES THIS "100× BETTER" THAN THE REFERENCE APP

The reference app (`id1483770938`, 4.1★, 37 ratings) is a 2019 Unity build with 20 exercises, a
single flat black-and-white aesthetic, an annoying unmuteable UI sound, no progress tracking, no
adaptivity, and no binocular work at all. Our nine structural advantages:

1. **Dichoptic track.** The reference app is 100% monocular. Contrast-rebalanced dichoptic viewing is
   the modality behind both FDA-cleared products and multiple RCTs. This alone is the category jump.
2. **Adaptive difficulty.** Staircase procedures (3-down/1-up) that converge on ~79% correct, per
   exercise, per eye — instead of a fixed 5-minute timer.
3. **Measurement, not just exercise.** Built-in logMAR-style acuity check, contrast-sensitivity probe,
   and suppression-balance check, run weekly, charted over time.
4. **Real progress tracking** with streaks, adherence %, and an exportable PDF report for the user's
   eye doctor. Adherence is the single biggest predictor of outcome in the literature.
5. **Sound and motion fully controllable**, everything off by default, plus Reduce Motion and
   photosensitivity safeguards the reference app has none of.
6. **iPad-native layout** with proper size classes, Stage Manager, keyboard/pencil support, and
   correct physical-size calibration so a "5° stimulus" is actually 5°.
7. **Kids mode** — reward map, characters, parent gate, session caps, no dark patterns.
8. **Apple Health integration** — reads the user's vision prescription, writes mindful-minutes for
   session time.
9. **On-device AI coach** that writes the weekly plan in plain language and flags "no improvement in
   6 weeks → go see your optometrist", which is both a genuine feature and a safety behaviour.

---

## 6. HONEST RISK REGISTER

| Risk | Severity | Mitigation |
|---|---|---|
| App Review flags us as medical (1.4.1) despite wellness framing | High | `08-COMPLIANCE-LEGAL.md` §3 — scrub every "treat/cure/therapy/improve your vision" claim, ship the disclaimer gate, write review notes that pre-empt it |
| Guideline 3.1.2 paywall rejection | High | `07-MONETIZATION-PAYWALL.md` §5 — literal checklist of everything that must be visible on the paywall |
| Trial disclosure rejection (the 2026 hotspot — toggle-based trial UIs) | High | `07` §5 — trial length, post-trial price and billing date as plain body text on the paywall, no toggle |
| Weekly plans on a health app attract refund/chargeback and 1★ "scam" reviews | Medium | Trial + clear cancel path + no auto-opt-in toggles |
| Anaglyph glasses dependency hurts conversion | Medium | Monocular track is fully usable without them; ship an in-app "where to buy" card; dichoptic is presented as an upgrade, not a wall |
| Photosensitive epilepsy — high-contrast flicker stimuli | High | Cap all flicker < 3 Hz, no full-field luminance inversion, explicit warning screen, `08` §6 |
| No Mac → signing/debugging friction | Medium | `12-CICD-NO-MAC.md`; get CI green in Phase 4 before the codebase is large |

---

## 7. RESUME PROTOCOL (copy-paste this into a new session)

> Continue the Amblyo iOS project in `E:\Lazy Eye`. Read `docs/00-MASTER-PLAN.md`, then
> `docs/13-BUILD-ROADMAP.md`, find the first unticked phase, read only the docs that phase lists
> under "Required reading", and execute it. If the phase is marked [RESEARCH-GATE], run fresh web
> research first. When done, tick the box and append to `docs/PROGRESS.md`.
