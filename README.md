# Amblyo — Lazy Eye Training

An iPad-first visual training app for people with amblyopia. Swift 6 · SwiftUI · SwiftData ·
StoreKit 2 · on-device only.

**Start here → [`docs/00-MASTER-PLAN.md`](docs/00-MASTER-PLAN.md)**
**What to do next → [`docs/13-BUILD-ROADMAP.md`](docs/13-BUILD-ROADMAP.md)**

---

## To resume work in a new session, paste this:

> Continue the Amblyo iOS project in `E:\Lazy Eye`. Read `docs/00-MASTER-PLAN.md`, then
> `docs/13-BUILD-ROADMAP.md`, find the first unticked phase, read only the docs that phase lists
> under "Required reading", and execute it. If the phase is marked [RESEARCH-GATE], run fresh web
> research first. When done, tick the box and append to `docs/PROGRESS.md`.

---

## Documents

| | |
|---|---|
| [00 Master Plan](docs/00-MASTER-PLAN.md) | Index, constraints, risk register, resume protocol |
| [01 Research Brief](docs/01-RESEARCH-BRIEF.md) | Clinical evidence, dosing, competitor teardown, sources |
| [02 PRD](docs/02-PRD.md) | Personas, features, IA, flows, success metrics |
| [03 Exercise Catalog](docs/03-EXERCISE-CATALOG.md) | All 32 exercises + the assessment battery |
| [04 Architecture](docs/04-ARCHITECTURE.md) | Modules, data model, rendering, safety, testing |
| [05 Design System](docs/05-DESIGN-SYSTEM.md) | Tokens, components, iPad layout, audio rules, a11y |
| [06 AI Engine](docs/06-AI-ENGINE-SPEC.md) | Staircase, progress analysis, Foundation Models, HealthKit |
| [07 Monetization](docs/07-MONETIZATION-PAYWALL.md) | StoreKit 2, three plans, paywall checklist |
| [08 Compliance & Legal](docs/08-COMPLIANCE-LEGAL.md) | Guidelines, banned language, disclaimers, review notes |
| [09 ASO & Metadata](docs/09-ASO-METADATA.md) | Name, subtitle, keywords, description, localisation |
| [10 App Icon](docs/10-APP-ICON-SPEC.md) | Concept, geometry, generation script |
| [11 Screenshots](docs/11-SCREENSHOTS-SPEC.md) | 8 frames, captions, sizes, no-Mac production |
| [12 CI/CD without a Mac](docs/12-CICD-NO-MAC.md) | GitHub Actions, fastlane, signing, TestFlight |
| [13 Build Roadmap](docs/13-BUILD-ROADMAP.md) | **The to-do list — 14 phases** |
| [14 Review Complaints Matrix](docs/14-REVIEW-COMPLAINTS-MATRIX.md) | Every reference-app complaint → our fix |
| [Progress Log](docs/PROGRESS.md) | Append-only session log |

---

## The three things that make this app different

1. **Dichoptic training** — contrast-rebalanced, different image to each eye via $5 red-cyan glasses.
   The modality behind both FDA-cleared amblyopia devices. Every competitor at this price is monocular.
2. **Real psychophysics** — 3-down/1-up adaptive staircases with true angular-size calibration, so
   difficulty is measured rather than guessed, and progress charts mean something.
3. **Nothing leaves the device** — no account, no server, no analytics, no third-party AI. The
   "AI coach" is Apple's on-device model with a deterministic guardrail filter.

## The one thing to be careful about

This is a **wellness and training** app, not a medical treatment, and every word of copy has to
reflect that. See [`docs/08-COMPLIANCE-LEGAL.md`](docs/08-COMPLIANCE-LEGAL.md) §3 — there is a
CI lint that fails the build on banned medical claims.
