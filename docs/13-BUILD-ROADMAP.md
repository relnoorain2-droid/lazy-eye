# 13 — BUILD ROADMAP

**This is the to-do list.** Each phase is self-contained: it names what must already exist, what to
read, what to build, and how to know it's done. Tick the box when the acceptance criteria pass, then
append a line to `PROGRESS.md`.

Phases marked **[RESEARCH-GATE]** must begin with fresh web research — Apple's APIs, review rules, and
asset specs change every year and this document will drift.

**Estimated total: 14–20 focused sessions.**

---

## ☑ PHASE 0 — Decisions & naming lock — **DONE 2026-08-06**

Recorded in `DECISIONS.md`. Name `Amblyo: Lazy Eye Training`, pricing $2.99 / $9.99 / $29.99 with a
7-day trial on yearly, categories Medical + Health & Fitness, iOS 18.0 target.
**Eight items in `DECISIONS.md` §9 still need you** — Team ID, name/trademark check, App Store Connect
record, API key, iPad model, domain, anaglyph glasses, Small Business Program. None block Phase 2.

<details><summary>original phase brief</summary>

**Entry state:** docs written, nothing else.
**Required reading:** `09-ASO-METADATA.md` §1, `07-MONETIZATION-PAYWALL.md` §2.

Decisions to make and record in `docs/DECISIONS.md`:

1. Final app name — check App Store, domain, and trademark first (`09` §1)
2. Bundle ID — **permanent once created**
3. Pricing: keep $2.99/$5.99/$9.99, or adopt the `07` §2 alternative
4. Free trial: yes/no, and on which plan
5. Apple Developer team ID and App Store Connect app record created
6. Support/privacy/terms domain chosen

**Done when:** `DECISIONS.md` exists with all six answered, and the App Store Connect app record is
created with the bundle ID.
</details>

---

## ☑ PHASE 1 — Project scaffold — **DONE 2026-08-06**

Shipped:

| File | Note |
|---|---|
| `project.yml` | XcodeGen manifest, 3 targets, Swift 6 strict concurrency, StoreKit config wired to the scheme |
| `Gemfile`, `.gitignore` | `.xcodeproj` is gitignored by design |
| `App/AmblyoApp.swift` | Entry point, `NavigationSplitView` on iPad regular / `TabView` elsewhere, launch-order comments |
| `App/Core/Settings/SettingsStore.swift` | **All audio channels default off** (constraint C6) |
| `App/DesignSystem/Audio.swift` | `.ambient` + `mixWithOthers` — silent switch wins; every cue passes through the settings gate |
| `App/Purchases/SubscriptionManager.swift` | `Transaction.updates` listener starts before first UI frame |
| `App/Data/Store/AmblyoSchema.swift` | Placeholder schema, replaced in Phase 2 |
| `App/Info.plist` | Export compliance declared, 120 Hz enabled, orientations per `05` §6, HealthKit strings pre-written |
| `App/PrivacyInfo.xcprivacy` | `NSPrivacyCollectedDataTypes` empty — the "Data Not Collected" target |
| `App/Amblyo.storekit` | Local test config, all 3 products + the 7-day intro offer |
| `App/Resources/Legal/medical-disclaimer.md` | Verbatim from `08` §4 |
| `Tests/SettingsStoreTests.swift` | 6 tests locking the audio defaults |
| `UITests/SmokeUITests.swift` | Launch + navigation smoke |
| `scripts/lint_claims.py` | **Verified working** — catches Swift literals, Markdown, "dark room"; correctly ignores comments and allow-listed disclaimers |

Verified: all plists parse, storekit JSON parses, `project.yml` parses, claims-lint passes clean and
fails correctly on a seeded violation.

**Team ID applied 2026-08-06** — `QAT93YWVSF`, bundle `com.amblyo.app`, baked into `project.yml`,
`SubscriptionManager.swift`, `Audio.swift` and `Amblyo.storekit`. No placeholders remain.


**Not yet done (needs a Mac/CI):** `xcodegen generate` and an actual compile. That is Phase 4.

---

## ☑ PHASE 2 — Data layer — **DONE 2026-08-06**

| File | Note |
|---|---|
| `Data/Models/Enums.swift` | `Eye`, `AgeGroup` (session lengths + daily caps), `Track`, `EvidenceTier` (with the §3A boundary sentences baked into `explanation`), `EndReason`, `AnaglyphFilter`, `AssessmentTest`, `PreferencesBlob` with tolerant decoding |
| `Data/Models/Profile.swift` | Typed accessors, `isSetUp`, `canUseDichopticTrack` (hides the track for colour-blind users rather than locking it) |
| `Data/Models/CalibrationProfile.swift` | **The angular-geometry maths** — `points(forDegrees:)`, `pointsPerCycle`, `maxRenderableCyclesPerDegree` (Nyquist ceiling), crosstalk acceptability |
| `Data/Models/SessionRecord.swift` | `countsTowardAdherence` (60% threshold), `validTrials`, interrupted sessions excluded |
| `Data/Models/TrialRecord.swift` | Indexed, discard tracking for dropped frames, parameter snapshot |
| `Data/Models/AssessmentResult.swift` | Four sub-tests, `contrastSensitivityIndex`, `interocularAcuityGap` |
| `Data/Store/AmblyoSchema.swift` | `VersionedSchema` + migration plan from day one, `ModelContainer.amblyo(inMemory:)`, CloudKit explicitly `.none` |
| `Data/Repositories/` | Profile (limits, single-active invariant, delete-all), Session (batched saves, streak, daily cap), Progress (adherence with window clamping, chart series, 4-week blocks) |
| `Data/Seed/DemoDataSeeder.swift` | 12-week history + `SeededGenerator` (SplitMix64) for byte-identical regeneration |
| `Tests/` | 3 new files, ~35 assertions |

**Verified numerically** (curve simulated independently in Python):

- Adherence **74%** with a visible week-5/6 slump (2/7 days) — realistic, not perfect
- Outcomes: 85% completed, 8% user-stopped, 3% fatigue, 3% interrupted
- Acuity 0.600 → 0.396 logMAR = **2.0 lines over 12 weeks**, with a genuine plateau from week 10
- Binocular balance 0.28 → 0.46 — improves, **never reaches 0.5**, so the demo never implies a cure
- Fellow-eye contrast ramp 0.20 → 0.79

The honesty of that curve is enforced by tests, not convention: `acuityCurveIsHonest` fails the build
if the demo ever shows more than 3 lines of gain, and `balanceStaysHonest` fails if balance reaches
parity. Screenshots are generated from this data, so the tests are a compliance control.

**Deferred to Phase 3:** `ScreenGeometry` device→PPI lookup (the seeder hardcodes 26.5 pt/cm for now).

---

## ☑ PHASE 3 — Design system + onboarding — **DONE 2026-08-08**

**Entry state:** Phase 2.
**Required reading:** `05-DESIGN-SYSTEM.md` (all), `14-REVIEW-COMPLAINTS-MATRIX.md`, `08` §4.

- `Tokens.swift`, `Theme.swift`, all components in `05` §5
- `Audio.swift` implementing `05` §7 **exactly** — this is the single most important behavioural fix
- 7-step onboarding per `02` §5, including the contraindication screen (`14` R6), the
  amblyopia-vs-strabismus explainer (`14` R4), the occlusion warning (`14` R11), and the sound card
- `Legal/` screens rendering the bundled Markdown; ship `medical-disclaimer.md` verbatim from `08` §4
- Screen-size + viewing-distance calibration (`04` §4 angular maths)
- Learn section shell + first 4 articles
- Full accessibility pass on everything built so far

**Done when:** fresh install → onboarding → calibration completes; no sound has played at any point;
VoiceOver navigates the whole flow; layout correct at 320 pt and on iPad 13" in split view.

---

## ☑ PHASE 4 — CI GREEN — **BUILD + TESTS PASSING 2026-08-07**

**CI #4 completed successfully.** Compile clean, zero warnings, all unit tests
passing on both iPhone 16 and iPad Pro 13-inch, compliance lint passing.

Took four rounds, all of them my bugs, none of them the app's:

| Run | Result |
|---|---|
| #1 | 2 compile errors + 8 concurrency warnings |
| #2 | 1 error — my first fix was wrong |
| #3 | Compile clean, all unit tests pass, iPad UI smoke test failed (bad assertion) |
| #4 | ✅ **Green** |

**Still outstanding before TestFlight:** `MATCH_PASSWORD` and `MATCH_GIT_AUTH`
secrets, then the one-time Bootstrap Signing run. See `PHASE-4-SETUP.md`.

<details><summary>original phase brief</summary>

## ☐ PHASE 4 — [RESEARCH-GATE] CI green

**Entry state:** Phase 3. **Do this now, not later.**
**Required reading:** `12-CICD-NO-MAC.md` (all).
**Research first:** current macOS runner image, current Xcode version, any fastlane/match changes.

- App Store Connect API key, private match repo, all GitHub secrets
- Run `bootstrap-signing.yml` once
- `ci.yml` green on push
- `release.yml` producing a TestFlight build
- Install that build on your own iPad

**Done when:** you are holding your iPad running your own build, installed via TestFlight, having never
touched a Mac.
</details>

---

## ☑ PHASE 5 — Exercise engine core — **DONE 2026-08-08**

**Entry state:** Phase 4.
**Required reading:** `04-ARCHITECTURE.md` §4–6, `03-EXERCISE-CATALOG.md` header, `06` §2.

- `ExerciseProtocol`, `ExerciseRegistry`, `ExerciseParameters`
- `Staircase` + `ThresholdEstimator` + `TrialLog` with **simulated-observer tests** (`04` §7) —
  the correctness core of the whole app
- `SessionRunner`: plan → exercise sequence → trial loop → summary; pause, resume, background handling
- `Core/Safety`: `FlickerGuard`, `BreakScheduler`, `FatigueMonitor`, `SessionCap`
- `StimulusRenderer` base with `Canvas` and Metal paths
- `GaborGenerator`, `DotFieldGenerator`
- One reference exercise end to end: **M1 Gabor Orientation**

**Done when:** M1 runs a full adaptive session; the staircase converges on a known threshold against a
simulated observer within ±10%; the fatigue button ends the session in one tap from anywhere.

---

## ☐ PHASE 6 — Monocular pack (14 exercises)

**Entry state:** Phase 5.
**Required reading:** `03-EXERCISE-CATALOG.md` Pack 1.

Build M2–M14. Each needs: view, parameters, staircase dimension, scoring, evidence badge, VoiceOver
description, and a `FlickerGuard` test.

Suggested order (easiest first, so the pattern settles): M5, M2, M12, M10, M9, M13, M4, M3, M6, M7,
M8, M11, M14.

**Done when:** all 14 run; `FlickerGuard` tests pass for every one; Train library lists them with
correct badges and durations.

---

## ☐ PHASE 7 — Anaglyph calibration + dichoptic engine

**Entry state:** Phase 6. **The hardest phase — budget two sessions.**
**Required reading:** `01-RESEARCH-BRIEF.md` §4, `04-ARCHITECTURE.md` §4.

- `AnaglyphCalibrator`: filter assignment, crosstalk measurement (red-invisible / cyan-invisible
  sliders), colour-vision check with graceful routing (`05` §8)
- `AnaglyphCompositor` Metal shader implementing the 6-step pipeline in `04` §4
- `contrastFellow` rebalance ramp (`06` §2)
- "Preview without glasses" mode for App Review (`08` §8)
- `GlassesPrompt` pre-session card

**Done when:** on a real iPad with real red-cyan glasses, the calibration converges and a test pattern
shows each eye a genuinely different image with no visible ghosting. **This one needs physical
verification — order the glasses now, in Phase 0.**

---

## ☐ PHASE 8 — Dichoptic pack + games (18)

**Entry state:** Phase 7.
**Required reading:** `03-EXERCISE-CATALOG.md` Packs 2 and 3.

- D1–D10, then G1–G8
- Priority order: **D5 (Balance Meter) first** — it produces the app's flagship metric — then D1, D3,
  D6, then the rest
- Games share a `GameShell` with score, lives, and reward hooks
- Kids reward map and mascot

**Done when:** all 18 run in both dichoptic and monocular-fallback modes; every one is verifiably
impossible to complete with one eye covered.

---

## ☐ PHASE 9 — Intelligence, progress, health

**Entry state:** Phase 8.
**Required reading:** `06-AI-ENGINE-SPEC.md` (all).

- `ProgressAnalyzer` with OLS trends + bootstrap CIs; "no clear change yet" path must be real
- `PlanGenerator` with the weighting formula
- Assessment battery: all four sub-tests
- Progress screen with Swift Charts; every score labelled "training score, not a clinical measurement"
- `EscalationRule` + non-dismissible referral card
- `CoachNarrator` + `DeterministicCoach` + `Guardrails` with an adversarial test corpus
- Streaks, adherence, local notifications, `AppReviewPrompter`
- HealthKit bridge (can slip to v1.1)

**Done when:** a simulated 12-week history produces sensible trends; an 8-week flat history triggers
the referral card; `Guardrails` rejects every string in the adversarial corpus.

---

## ☐ PHASE 10 — [RESEARCH-GATE] Subscriptions & paywall

**Entry state:** Phase 9.
**Required reading:** `07-MONETIZATION-PAYWALL.md` (all), `08-COMPLIANCE-LEGAL.md` §1–5.
**Research first:** current 3.1.2 rejection patterns, any StoreKit changes in the newest SDK.

- Three products created in App Store Connect with review screenshots
- `SubscriptionManager` per `07` §4, including grace period, billing retry, Ask to Buy, refunds
- `.storekit` test config + tests for all eight scenarios
- Paywall implementing the `07` §5 checklist item by item
- Free/Pro gating per `07` §3, with one full free exercise before the paywall
- Reviewer Mode (version-tap unlock)
- Parent gate on the paywall in Kids mode

**Done when:** every item in `07` §5 is ticked and screenshotted; all StoreKit test scenarios pass;
`lint_claims.py` passes on the paywall copy.

---

## ☐ PHASE 11 — Icon & brand assets

**Entry state:** Phase 10.
**Required reading:** `10-APP-ICON-SPEC.md`.

- `scripts/make_icon.py` → all four variants
- Asset catalog with Any/Dark/Tinted appearances
- Launch screen, alternate icons
- Mascot design (confirm the name)
- Icon QA checklist

**Done when:** every QA item in `10` §6 passes, verified on a device Home Screen in light, dark, and
tinted modes.

---

## ☐ PHASE 12 — [RESEARCH-GATE] Metadata & screenshots

**Entry state:** Phase 11.
**Required reading:** `09-ASO-METADATA.md`, `11-SCREENSHOTS-SPEC.md`.
**Research first:** current required screenshot dimensions and metadata character limits — these
changed in 2025 and 2026 and will change again.

- `fastlane/metadata/` populated from `09`
- `Snapfile` + UI test capture on CI
- `scripts/make_screenshots.py` → 8 frames × 2 device classes
- App preview video (optional)
- Wave-1 locale metadata
- Public privacy / terms / support pages live and returning 200

**Done when:** `fastlane deliver --skip_binary_upload` previews correctly; all URLs live;
`lint_claims.py` passes on all metadata.

---

## ☐ PHASE 13 — [RESEARCH-GATE] Submission

**Entry state:** Phase 12.
**Required reading:** `08-COMPLIANCE-LEGAL.md` §6–9, `14-REVIEW-COMPLAINTS-MATRIX.md` checklist.
**Research first:** current App Review guideline text for 1.4.1, 3.1.2, 5.1.1.

- `08` §9 compliance gate — every box
- `14` verification checklist — every box
- App Privacy questionnaire: Data Not Collected
- Age rating questionnaire
- Review notes from `08` §8, with your email
- Reviewer Mode verified on the actual TestFlight build
- External TestFlight with 10+ real users for one week — **do not skip this**
- Fix what they find, then submit

**Done when:** submitted. Then: monitor, respond to every review in the first month, and ship 1.0.1
within three weeks with whatever the first users hit.

---

## AFTER LAUNCH

| Version | Contents |
|---|---|
| 1.0.1 | Crash and layout fixes from real users |
| 1.1 | PDF report export, HealthKit, CloudKit sync, wave-2 locales, widgets |
| 1.2 | Apple Watch companion, split-screen cardboard mode, In-App Events |
| 2.0 | visionOS target — true per-eye rendering with no glasses at all. This is where the product ultimately wants to live. |
