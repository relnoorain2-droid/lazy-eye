# DECISIONS — Phase 0

Locked decisions. Changing anything here means revisiting the docs that depend on it.
Anything marked **⬜ NEEDS YOU** requires an action only you can take.

Last updated: 2026-08-06

---

## 1. NAME

| | |
|---|---|
| **App Store name** | `Amblyo: Lazy Eye Training` (25 / 30 chars) |
| **Subtitle** | `Amblyopia Eye Exercises Daily` (29 / 30) |
| **Internal / product name** | Amblyo |
| **Xcode target & scheme** | `Amblyo` |
| **Mascot (kids mode)** | "Otto" — placeholder, confirm in Phase 11 |

**⬜ NEEDS YOU — verify before creating the App Store Connect record:**

1. Search the App Store for `Amblyo` and for the full name. A near-identical existing name = 5.2.1 rejection.
2. Check `amblyo.app` / `amblyo.com` availability.
3. Search your trademark registry for "Amblyo" in classes 9 and 44.
4. If `Amblyo` is taken, fall back in order: `EyeBalance: Lazy Eye Trainer` → `VisionUp: Lazy Eye Training`.

---

## 2. IDENTIFIERS

| | |
|---|---|
| **Team ID** | **`QAT93YWVSF`** ✅ |
| **Bundle ID** | **`com.amblyo.app`** — **permanent once the App Store Connect record is created** |
| **Subscription group** | `amblyo_pro` |
| **Product IDs** | `com.amblyo.app.pro.weekly` · `.monthly` · `.yearly` |
| **App Group** (v1.1 Watch) | `group.com.amblyo.app` |

Baked into `project.yml`, `SubscriptionManager.swift`, `Audio.swift`, `Amblyo.storekit` and the CI docs
as of 2026-08-06. No placeholders remain.

### ✅ REGISTERED — App ID confirmed 2026-08-06

```
App ID Prefix   QAT93YWVSF  (Team ID)
Bundle ID       com.amblyo.app  (explicit)
```

The identifier is claimed and matches the codebase exactly — no changes were needed. All derived
identifiers are final:

| | |
|---|---|
| Bundle ID | `com.amblyo.app` |
| Tests / UI tests | `com.amblyo.app.tests` · `com.amblyo.app.uitests` |
| Products | `com.amblyo.app.pro.weekly` · `.monthly` · `.yearly` |
| App Group (v1.1) | `group.com.amblyo.app` |
| Log subsystem | `com.amblyo.app` |
| Provisioning profiles | `match Development com.amblyo.app` · `match AppStore com.amblyo.app` |

**This is now permanent.** Once the App Store Connect record is created against this App ID, changing
it means a new listing with zero ratings.

**Note on capabilities:** only In-App Purchase should be enabled on the App ID for now. HealthKit is
v1.1 — enabling it early forces every provisioning profile to carry an entitlement the app doesn't
use, which is a common cause of Phase 4 signing failures.

---

## 3. PRICING — **FINAL**

| Plan | Price | Per week | vs weekly | Trial |
|---|---|---|---|---|
| Weekly | $2.99 | $2.99 | — | none |
| Monthly | $9.99 | ≈$2.31 | 23% off | none |
| **Yearly** | **$29.99** | **≈$0.58** | **81% off** | **7 days free** |

- Yearly is preselected on the paywall and badged **SAVE 81%**.
- Trial is on the yearly plan only, configured as an App Store Connect introductory offer.
- Net per yearly subscriber: **$21.00** standard, **$25.49** on the Small Business Program.

**⬜ NEEDS YOU:** apply to the **App Store Small Business Program** (App Store Connect → Business).
15% commission instead of 30% while under $1M/year. Not automatic — you must apply, and it takes
effect the month after approval. Worth $4.49 per yearly subscriber.

---

## 4. CATEGORIES & RATING

| | |
|---|---|
| Primary category | **Medical** |
| Secondary category | **Health & Fitness** |
| Age rating | **4+** |
| Kids Category | **No** in v1.0 (Kids mode ≠ Kids Category — see `08` §1) |
| Family Sharing | **On** — parents with two affected children |

---

## 5. TECHNICAL

| | |
|---|---|
| Deployment target | iOS / iPadOS **17.0** (see §6) |
| Build SDK | latest stable (Xcode 27 at time of writing) |
| Swift | 6, strict concurrency |
| Devices | Universal (iPhone + iPad), iPad-first design |
| Project generation | XcodeGen from `project.yml` — no hand-authored `.xcodeproj` |
| Dependencies | **none** in v1.0 |
| CI/CD | GitHub Actions `macos-15` runners + fastlane + match |
| Repo visibility | **Private** (health app) — budget for macOS minutes, see `12` §4 |

---

## 6. DEVICE CAPABILITY MATRIX — **the governing design rule**

You made the right call: this app is for users who own every kind of device, not for your test rig.
So the rule is **capability tiers, never device checks**. Nothing in the codebase may ask "is this an
iPhone 15 Pro?" — it asks "is this capability available right now?" and degrades cleanly.

### ⬇️ Deployment target lowered to **iOS/iPadOS 17.0** on 2026-08-06

You asked that older iPhone and iPad owners not be shut out. Checked properly, and you were right —
but the win is entirely on iPad:

| | iOS 17 | iOS 18 | Difference |
|---|---|---|---|
| **iPhones** | XS / XR and newer | XS / XR and newer | **None.** Both dropped the iPhone 8 and X. |
| **iPads** | iPad 6th gen+, iPad Pro 10.5"+, iPad Pro 12.9" 2nd gen+ | iPad 7th gen+, iPad Pro 11"/12.9" 3rd gen+ | **iOS 18 drops the iPad 6th gen, iPad Pro 10.5" and iPad Pro 12.9" 2nd gen.** |

The iPad 6th gen (2018) is the classic hand-me-down family iPad — precisely the device a parent gives a
child to do daily eye exercises on. For an iPad-first app that is the wrong device to exclude.

**Cost of moving 18 → 17: almost nothing.** SwiftData, `@Observable`, Swift Charts, StoreKit 2,
`ContentUnavailableView` are all iOS 17. The only casualty was the `#Index` macro on our SwiftData
models (iOS 18+), which is a query optimisation, not a feature — removed. Nothing else changed.

**Why not go lower still?** iOS 16 would add the iPhone 8 / 8 Plus / X (2017 phones) and the iPad 5th
gen, but iOS 16 has **no SwiftData and no `@Observable`** — it would mean Core Data and
`ObservableObject` throughout. As of mid-2026, iOS 26 is on ~79% of iPhones and iOS 18 on ~14%; every
version below 18 is under 4% each. Rewriting the data layer for a shrinking few percent is a bad
trade. **Say the word if you disagree** — it is doable, just expensive, and much cheaper to decide now
than in Phase 9.

---

| Tier | Requirement | Devices | What it enables | If absent |
|---|---|---|---|---|
| **T0 — Baseline** | iOS/iPadOS **17.0** | iPhone XS+, **iPad 6th gen+**, iPad Pro 10.5"+, iPad Air 3+, iPad mini 5+ | **100% of the app.** All 32 exercises, calibration, anaglyph, adaptive staircases, all four assessments, full progress, every paid feature | n/a — this is the floor |
| **T1 — ProMotion** | 120 Hz display | iPhone 13 Pro+, iPad Pro 2017+, iPad Air M-series | 120 Hz stimulus timing; tighter reaction-time resolution | Falls back to 60 Hz. Timing tolerances widen; the staircase is unaffected. |
| **T2 — Apple Intelligence** | A17 Pro / M1 or later, iOS 26+, AI enabled in Settings | iPhone 15 Pro+, iPad M1+, iPad mini A17 Pro | `CoachNarrator` — LLM-phrased weekly summaries | `DeterministicCoach` templated sentences. **No feature is lost, only phrasing.** |
| **T3 — HealthKit** | iOS 16+ and user permission | all | Reads vision prescription, writes mindful minutes | Silently skipped; manual eye selection. |
| **T4 — Anaglyph** | User owns red-cyan glasses + normal colour vision | all | The 10 dichoptic exercises + 8 games in dichoptic mode | Monocular track (14 exercises) is fully usable alone. |

### Enforcement rules (apply to every phase)

0. **No device is a second-class citizen.** A user on a 2018 iPad 6th gen gets **all 32 exercises,
   all four assessment sub-tests, the full progress history, the adaptive engine, and every paid
   feature.** Tiers T1–T4 add polish and phrasing, never content. If you ever find yourself writing
   "this exercise requires a newer device", the design is wrong — make the exercise cheaper instead.
   The old app ran on ancient hardware and that is part of why people found it; we will not regress on
   that.
1. **Never gate a paid feature behind a hardware tier.** A user on an iPhone 12 pays $29.99 and must
   get full value. T2 changes wording, not capability. This is both an ethics point and a refund-rate
   point.
2. **Never surface an error when a tier is unavailable.** No "your device doesn't support this."
   `CoachNarrator` silently returns the deterministic string.
3. **Runtime checks only**, never model-name lookups: `SystemLanguageModel.default.availability`,
   `UIScreen.maximumFramesPerSecond`, `HKHealthStore.isHealthDataAvailable()`.
4. **The one exception is physical screen geometry.** `ScreenGeometry` needs a device-model → PPI
   table because iOS exposes no physical-size API. That table must cover **every** iPhone and iPad
   back to the iOS 18 floor, with a safe fallback plus a user-verifiable "hold a credit card to the
   screen and drag to match" calibration for unknown or future models. Built in Phase 3.
5. **CI runs the test suite on both a small iPhone and a 13" iPad simulator** so layout regressions
   surface without you owning either.

### Your own test devices

| Device | Tiers covered | Note |
|---|---|---|
| iPhone 14 Pro (A16) | T0, T1, T3, T4 | **Not T2.** You will always see the deterministic coach on it. That is correct behaviour, not a bug — don't debug it. |
| Your iPad | T0, T4, and likely T1/T2 | Whatever it is, it's fine for normal testing. |

Practical consequence: **you cannot personally verify the T2 LLM path** unless your iPad is M1+. Cover
it three other ways — a Settings → Diagnostics row showing the active backend (build in Phase 9), unit
tests against `Guardrails` with a mocked model, and one TestFlight tester on a recent device.

---

## 7. WEB PRESENCE

| Page | URL | Required for |
|---|---|---|
| Privacy Policy | `https://sites.google.com/view/amblyolazyeyetraining/privacy-policy` | App Store Connect metadata — **must return 200 before submission** |
| Terms of Use (EULA) | `Apple Standard EULA` | App Store Connect metadata — same |
| Support | `https://sites.google.com/view/amblyolazyeyetraining/support` | App Store Connect metadata — same |
| Evidence & Methods | `https://sites.google.com/view/amblyolazyeyetraining/evidence-and-methods` | 1.4.1 methodology disclosure (`08` §3A) |
| Learn articles | `https://sites.google.com/view/amblyolazyeyetraining/learn/...` | Web SEO (`09` §9) |

**⬜ NEEDS YOU:** pick the host (Google Sites is fine, as you planned) and the domain. Apply the
`08` §3 banned-word rules to the site too — **including URL slugs.**

---

## 8. PHYSICAL MATERIALS TO ORDER NOW

**⬜ NEEDS YOU: order red-cyan anaglyph glasses today.** Phase 7 cannot be verified without them, and
shipping is usually the long pole. Get **at least 3 pairs** — cardboard, red-left/cyan-right,
"3D movie glasses", ~$5 for a 5-pack on Amazon. Buy from two different sellers: filter spectra vary
between manufacturers, and you need to know your crosstalk calibration works across cheap variants,
not just the one pair you happened to buy.

---

## 9. OPEN ITEMS BLOCKING LATER PHASES

| Item | Blocks | Status |
|---|---|---|
| ~~Team ID~~ | — | ✅ `QAT93YWVSF`, baked in |
| ~~Exact iPad model~~ | — | ✅ Not needed — replaced by the §6 capability matrix; `ScreenGeometry` will cover all models |
| Name/trademark verification | Creating the app record | ⬜ You |
| Bundle ID confirmation (`com.amblyo.app`) | Creating the app record | ⬜ You — permanent once created |
| App Store Connect app record | Phase 4 (TestFlight) | ⬜ You |
| App Store Connect API key + private match repo | Phase 4 | ⬜ You |
| Anaglyph glasses (3+ pairs, 2 sellers) | Phase 7 verification | ⬜ You — **order now, shipping is the long pole** |
| Support domain + 4 public pages | Phase 12 | ⬜ You |
| Small Business Program application | Phase 10 | ⬜ You — **deferred to the end, per your call.** Note it applies from the month after approval, so apply before your first revenue month, not after. |

**Nothing blocks Phases 2, 3, 5, 6, 8 or 9.** Only Phase 4 (CI) and Phase 7 (anaglyph verification)
need you.
