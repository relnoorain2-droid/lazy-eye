# 14 — REVIEW COMPLAINTS MATRIX

Every complaint and question found in the reference app's App Store reviews (`id1483770938`, 4.1★,
37 ratings), mapped to a specific product decision, with the phase that implements it.
**Acceptance criterion for Phase 13: every row here has a shipped implementation.**

---

| # | Verbatim complaint / question | Root cause | Our fix | Where | Phase |
|---|---|---|---|---|---|
| R1 | *"Opened app and turned 'music off.' Went back to main screen and every choice was accompanied by an annoying — wait, make that an extremely annoying, sound. In fact, so annoying I could not even get past it."* (3★) | Two separate audio systems; "music" toggle didn't cover UI SFX; no master mute | **All audio OFF by default.** Three independent toggles: Music / Sound effects / Voice guidance. A master mute in the nav bar of every exercise, always visible, one tap. Toggle state persists and applies immediately, no restart. Respects the hardware silent switch (`AVAudioSession` `.ambient` category). | `05-DESIGN-SYSTEM.md` §Audio, `SettingsStore` | P3 |
| R2 | *"Just downloaded and can't find any way to turn off the noise. Turn off the noise !!!!!"* (1★) | Same as R1, plus discoverability | Same as R1, plus: **first launch shows a Sound choice card** ("Sounds are off. Turn them on?") so the user never has to hunt. | Onboarding step 6 | P3 |
| R3 | *"Being in a dark room doing this, doesn't it damage ur eyes? Just a question since I'm insecure abt my eye and don't want it to get worse by using this."* (4★) | App instructs "Dark room" — bad advice, creates fear | **We instruct normal, evenly-lit room lighting** and explicitly say a dark room is not required and not recommended. In-app "Is this safe?" article answers the damage question directly. Auto-brightness guidance + optional ambient-light check via `UIScreen.brightness`. | `08-COMPLIANCE-LEGAL.md` §6, Safety article | P3 |
| R4 | *"Will this align my eyes also whenever i'm on my 2nd exercise my eye starts getting tired does this mean it is working?"* — Developer answered: *"Eye fatigue indicates a beneficial effect. Continue the exercises."* | **Unsafe advice.** Fatigue is a stop signal, not a progress signal. Also conflates amblyopia with strabismus. | Two fixes: (a) **Fatigue handling** — any "my eyes feel tired" tap ends the session, starts a rest timer, and shows the 20-20-20 rule. The app never tells anyone to push through eye strain. (b) **"Lazy eye vs crossed eye" explainer** in onboarding, stating plainly that training targets how the brain uses the weak eye and does **not** straighten a misaligned eye — that needs an eye doctor. | Session runner `FatigueSheet`, Learn article `amblyopia-vs-strabismus` | P5, P3 |
| R5 | *"Does it work?"* (4★, headline of the review) | No evidence shown, no measurement, no progress | (a) **Evidence tier badge** on every exercise (A/B/C) with a one-tap "why this exercise" sheet citing the study type. (b) **Weekly assessment battery** so the user has their own data. (c) **Progress charts** + exportable PDF for their eye doctor. | `03-EXERCISE-CATALOG.md`, `06-AI-ENGINE-SPEC.md` | P6, P9 |
| R6 | *"I am blinked in my left eye from Macular Degeneration and was told that my non-sided I would not follow… I am using this exercise to prolong the coordination of my eyes so I won't have to wear an eye patch"* (5★) | An adult with an unrelated retinal disease self-prescribing an amblyopia app | **"Is this for me?" screen** in onboarding listing who it is for (amblyopia, anisometropia, mild strabismus, post-patching maintenance, adults) and who it is **not** for (macular degeneration, glaucoma, retinal disease, recent eye surgery, active double vision, acute vision loss) with a "see your eye doctor" CTA. | Onboarding step 2 | P3 |
| R7 | *"I am gonna try to do this every night thx"* (5★) — no retention mechanism existed | No streaks, reminders, or plan | **Daily plan + streak + smart reminder** (local notification, user-chosen time, respects Focus). Adherence % is the headline metric, per the literature. | `06-AI-ENGINE-SPEC.md` §Adherence | P9 |
| R8 | Implicit: 4.1★ from only **37 ratings** in ~7 years | No review prompt, low retention | `SKStoreReviewController` triggered only after a **positive milestone** (7-day streak or a measured improvement), never on launch, max per Apple's 3×/year cap. | `AppReviewPrompter` | P9 |
| R9 | Implicit: exercises are black-and-white dot fields and spirals with a coloured dot — Tier D, visually hostile | 2019 Unity build with no design system | Full SwiftUI design system, light/dark, kid and adult skins, Dynamic Type, VoiceOver, Reduce Motion. See `05-DESIGN-SYSTEM.md`. | | P3 |
| R10 | Implicit: "Perform the exercise for 5 minutes" — fixed timer regardless of ability | No adaptivity | **3-down/1-up staircase** per exercise per eye; sessions end on convergence or time, whichever first; difficulty is measured, not guessed. | `06-AI-ENGINE-SPEC.md` §2 | P9 |
| R11 | Implicit: instructions say "cover your healthy eye" with no warning | Occlusion amblyopia risk if reversed | **Eye-assignment confirmation step** with a plain-language warning: never cover the weaker eye, never patch a child without professional guidance. Repeated on first session of each week. | Onboarding step 4 | P3 |
| R12 | Implicit: no accessibility at all | — | VoiceOver labels on every control, Dynamic Type to AX5, Reduce Motion honoured, colour-blind detection during anaglyph calibration with a graceful route to the monocular track, minimum 44×44pt targets. | `05-DESIGN-SYSTEM.md` §Accessibility | P3 |
| R13 | Implicit: 81.4 MB for 20 simple exercises | Unity runtime overhead | Native SwiftUI + Metal; all stimuli generated procedurally, no bitmap assets for exercises. **Target < 25 MB download.** | `04-ARCHITECTURE.md` §Rendering | P5 |
| R14 | Implicit: no iPad-specific layout despite "iPhone, iPad, Mac" support | Scaled-up phone UI | iPad-first. Size classes, split view, Stage Manager, correct physical-size calibration so angular stimulus size is real. | `05-DESIGN-SYSTEM.md` §Layout | P3 |

---

## Verification checklist (Phase 13)

- [ ] Fresh install → no sound is emitted anywhere until the user opts in (R1, R2)
- [ ] Silent switch on → app is silent even with sounds enabled (R1)
- [ ] No screen anywhere says "dark room" (R3)
- [ ] No copy anywhere frames eye fatigue as positive (R4)
- [ ] Fatigue button reachable in ≤1 tap from any active exercise (R4)
- [ ] Every exercise card shows an evidence tier badge (R5)
- [ ] "Is this for me?" contraindication list is in onboarding and re-reachable from Settings (R6)
- [ ] Occlusion warning appears before the first monocular session (R11)
- [ ] Full VoiceOver pass on onboarding, paywall, and one exercise of each type (R12)
- [ ] Download size < 25 MB (R13)
- [ ] iPad layout audited on 11" and 13", portrait and landscape, Stage Manager on (R14)
