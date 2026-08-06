# 02 — PRODUCT REQUIREMENTS

---

## 1. POSITIONING STATEMENT

> For people living with amblyopia — and the parents of children who have it — **Amblyo** is an
> iPad-first visual training app that runs contrast-balanced binocular exercises with cheap red-cyan
> glasses, measures your progress every week, and adapts itself to you. Unlike the dot-and-spiral
> "eye exercise" apps, Amblyo is built on the same binocular principle used by the clinically studied
> systems, and it is honest about what it is: **training and practice support, not a medical treatment
> and not a substitute for your eye doctor.**

---

## 2. PERSONAS

**P1 — Parent of a 6-year-old (primary, ~50% of installs)**
Child is in glasses and doing 2 h/day patching. Patching is a daily fight. Wants something the child
will actually do, on the iPad they already own. Buys on trust; churns instantly on anything that feels
scammy or unsafe. **Needs:** parent gate, session caps, reward loop the child likes, printable report
for the next optometrist visit, unambiguous safety language.

**P2 — Adult, 25–45, diagnosed as a child (primary, ~35%)**
"They told me it was too late after age 8." Curious, motivated, skeptical, will read the evidence
section. Self-directed. **Needs:** credible evidence framing, real measurement, no baby-talk UI,
progress charts, dark mode, a track that works in 15 min before bed.

**P3 — Adult recently diagnosed / post-surgery maintenance (~10%)**
Under active optometric care, told to "do vision exercises at home". **Needs:** exercise types their
clinician named (anti-suppression, vergence, stereopsis), exportable adherence log, no conflict with
their prescribed plan.

**P4 — Optometrist / vision therapist (influencer, ~5% but high leverage)**
Might recommend the app. **Needs:** transparent methodology, evidence tiers, the ability to see that we
are not overclaiming, patient-report export.

**Explicitly not our user:** macular degeneration, glaucoma, retinal disease, recent eye surgery,
active/new double vision, acute vision loss. Screened out in onboarding (see `14` R6).

---

## 3. FEATURE LIST — MoSCoW

### MUST (v1.0)

| ID | Feature | Notes |
|---|---|---|
| F01 | Onboarding: who it's for, contraindications, amblyopia vs strabismus explainer, eye assignment, safety, sound choice | 7 steps, skippable after first run |
| F02 | Physical-size + viewing-distance calibration | Makes angular stimulus size real; uses known device screen PPI |
| F03 | Anaglyph calibration (crosstalk cancellation, eye-filter assignment, colour-vision check) | Gate to the dichoptic track |
| F04 | **Monocular exercise pack — 14 exercises** | Works with no accessory |
| F05 | **Dichoptic exercise pack — 10 exercises** | Requires red-cyan glasses |
| F06 | **Binocular games — 8** | Dichoptic game shells: falling blocks, breakout, whack-a-mole, match pairs, maze, sky-catch, balloon pop, star tracer |
| F07 | Adaptive difficulty (3-down/1-up staircase per exercise per eye) | See `06` |
| F08 | Weekly assessment battery: acuity, contrast sensitivity, suppression balance, stereo screen | ~6 min |
| F09 | Daily plan generator + streaks + adherence % | Primary retention loop |
| F10 | Progress dashboard with Swift Charts | Per-metric trend, 4-week blocks |
| F11 | On-device AI coach (Foundation Models, with deterministic fallback) | Never network |
| F12 | Kids mode: reward map, characters, parent gate, 20-min cap | Toggle in profile |
| F13 | Multi-profile (up to 5) | Families with two affected children; also parent + child |
| F14 | StoreKit 2 subscriptions: weekly / monthly / yearly | `07` |
| F15 | Paywall with full 3.1.2-compliant disclosure, in-app EULA + Privacy screens | `07`, `08` |
| F16 | Settings: audio (3 toggles + master mute), motion, haptics, notifications, theme, units, data export/delete | |
| F17 | Local notifications with user-chosen reminder time | |
| F18 | Full accessibility pass | VoiceOver, Dynamic Type→AX5, Reduce Motion, colour-blind path |
| F19 | Safety systems: fatigue stop, 20-20-20 break, flicker cap, session cap, no-improvement escalation | `01` §7 |
| F20 | Learn section: 12 short evidence-based articles, bundled Markdown, offline | Also serves ASO via keyword-rich in-app content |

### SHOULD (v1.1)

| F21 | PDF report export for the eye doctor |
| F22 | HealthKit: read `HKVisionPrescription`, write mindful minutes |
| F23 | iCloud sync via SwiftData + CloudKit |
| F24 | Apple Watch companion: session timer + break haptics |
| F25 | Localisation: ES, PT-BR, DE, FR, HI, AR |
| F26 | Widgets + Live Activity for session in progress |

### COULD (v1.2+)

| F27 | Split-screen cardboard-viewer mode (alternative to anaglyph) |
| F28 | visionOS target — true per-eye rendering, no glasses |
| F29 | Clinician portal / shared code linking a patient to their therapist |
| F30 | Front-camera gaze estimation for viewing-distance auto-check (ARKit face tracking, on-device only) |

### WON'T (ever)

- Any claim to diagnose, treat, cure, or prevent amblyopia
- Any measurement presented as a clinical acuity result
- Ads, third-party analytics SDKs, or data sale
- Cloud AI / third-party LLM APIs
- Bates method, palming, eye yoga, colour therapy, or any Tier-D content

---

## 4. INFORMATION ARCHITECTURE

```
Root (TabView, iPad: NavigationSplitView)
├── Today            Daily plan card, streak, start session, break reminder
├── Train            Library: Monocular / Dichoptic / Games, filter by evidence tier & duration
├── Progress         Charts, weekly assessment history, adherence, report export
├── Learn            12 articles, FAQ, "Is this for me?", safety, glasses buying guide
└── Profile          Profiles, calibration, subscription, settings, legal, support
```

Modal flows: Onboarding · Calibration · Session runner (full-screen, immersive) · Assessment · Paywall
· Parent gate.

---

## 5. KEY USER FLOWS

**First run (target < 3 min to first exercise)**
Splash → Welcome → "Is this for me?" (contraindication check) → "Lazy eye vs crossed eye" explainer →
Eye assignment (which eye is weaker? + occlusion warning) → Age group (Under 5 / 5–12 / 13+) →
Sound preference card → Screen-size + distance calibration → **Free sample exercise (no paywall)** →
Paywall → Today.

The free sample before the paywall is deliberate: Guideline 3.1.2 rejections frequently cite "reviewer
cannot see the value before paying." Letting review (and users) experience one real exercise first
removes that risk and lifts conversion.

**Daily session**
Today → Start → Setup check (glasses on? / patch on? correct eye?) → Exercise 1..N with 20-20-20
break inserted at 20 min → Session summary (what changed, one AI sentence) → Streak update.

**Weekly assessment (day 7)**
Today shows an Assessment card → 4 sub-tests, ~6 min → Results vs last week → AI plan update for the
coming week → If two consecutive blocks show no improvement → non-dismissible "see an eye care
professional" card.

---

## 6. SUCCESS METRICS

| Metric | Target v1.0 | Why |
|---|---|---|
| D1 retention | ≥ 55% | Health apps live or die on day 1 |
| D7 retention | ≥ 30% | |
| D30 retention | ≥ 15% | |
| Trial → paid conversion | ≥ 8% | |
| Median sessions/week among subscribers | ≥ 4 | Adherence is the therapeutic variable |
| App Store rating | ≥ 4.6 with ≥ 200 ratings in 6 months | Beat the reference app's 4.1/37 decisively |
| Crash-free sessions | ≥ 99.8% | |
| Download size | < 25 MB | Reference app is 81.4 MB |
| Cold launch → interactive | < 1.2 s on iPad (9th gen) | Support old hardware; families keep iPads a long time |

---

## 7. DEVICE SUPPORT

- **Minimum: iOS/iPadOS 17.0.** Covers iPhone XS and later, and **iPad 6th gen (2018) and later** —
  the hand-me-down iPads families actually put in a child's hands. iOS 18 would have dropped the
  iPad 6th gen, iPad Pro 10.5" and iPad Pro 12.9" 2nd gen for no benefit on iPhone at all.
  See `DECISIONS.md` §6.
- **No device gets a reduced app.** Every supported device runs all 32 exercises, all four assessment
  sub-tests, and every paid feature. Newer hardware adds 120 Hz timing and LLM-phrased summaries —
  polish, never content.
- **Foundation Models AI coach requires iOS 26+ and an Apple-Intelligence-capable device.** Everything
  works without it via a deterministic rule-based coach; the LLM only rewrites the phrasing. Availability
  must be checked at runtime (`SystemLanguageModel.default.availability`) and must never be a hard
  dependency.
- Build with the latest SDK (Xcode 27 / iOS 27 at time of writing) but deploy back to 17.0.
- Orientation: iPad all four; iPhone portrait + landscape (landscape matters for wide-field stimuli).
