# 06 — ADAPTIVE & AI ENGINE

**Hard constraint: no network calls, no third-party AI API, no OpenAI key.** Everything here runs on
the device. That is both the user's requirement and, for a health app, a much stronger privacy story
than any competitor can claim — it goes on the App Store screenshots.

The word "AI" covers three distinct systems here. Keep them separate in your head and in the code:

| System | What it is | Availability |
|---|---|---|
| **1. Adaptive engine** | Classical psychophysics — staircases and threshold estimation. Deterministic maths. | Always, iOS 18+ |
| **2. Progress analyzer** | Statistics over the user's own trial history: trend detection, plateau detection, adherence modelling, plan generation. Deterministic. | Always, iOS 18+ |
| **3. Coach narrator** | Apple **Foundation Models** on-device LLM turning system 2's numbers into plain human sentences. | iOS 26+, Apple-Intelligence-capable device. **Optional.** |

Systems 1 and 2 do all the real work. System 3 only changes the *wording*. If Foundation Models is
unavailable, `DeterministicCoach` emits templated sentences and the user loses nothing functional.
**Never make an app behaviour depend on the LLM.**

---

## 1. WHY THIS IS REAL AI AND NOT MARKETING

Worth being clear-eyed, because you'll be tempted to overclaim in the App Store description and that
is exactly what gets health apps rejected. What we actually have:

- **Genuine adaptive personalisation** — every trial changes the next trial's parameters, per exercise,
  per eye, per user. That is a real closed loop, and no competitor at this price does it.
- **Genuine on-device inference** — Apple's ~3B-parameter model runs on the Neural Engine, offline.
- What we do **not** have: a model trained on clinical outcomes, or any ability to predict a medical
  result. The App Store copy says *"adapts to you"* and *"on-device intelligence"*, never
  *"AI predicts your vision improvement"*.

---

## 2. ADAPTIVE ENGINE — STAIRCASE

**Method: 3-down / 1-up transformed staircase**, converging on the 79.4% correct point. Standard,
well-validated, no training data required.

```swift
struct Staircase {
    var value: Double                 // current difficulty on the exercise's dimension
    let floor: Double, ceiling: Double
    var stepSize: Double              // multiplicative
    let minStep: Double
    private var consecutiveCorrect = 0
    private(set) var reversals: [Double] = []
    private var lastDirection: Direction?

    mutating func record(correct: Bool) {
        if correct {
            consecutiveCorrect += 1
            guard consecutiveCorrect >= 3 else { return }
            consecutiveCorrect = 0
            step(.harder)
        } else {
            consecutiveCorrect = 0
            step(.easier)
        }
    }

    private mutating func step(_ dir: Direction) {
        if let last = lastDirection, last != dir {
            reversals.append(value)
            stepSize = max(minStep, stepSize * 0.7)   // shrink after each reversal
        }
        lastDirection = dir
        value = (dir == .harder ? value / (1 + stepSize) : value * (1 + stepSize))
        value = min(max(value, floor), ceiling)
    }

    /// Threshold = mean of the last 6 reversals (or all, if fewer).
    var threshold: Double? {
        guard reversals.count >= 4 else { return nil }
        return reversals.suffix(6).reduce(0, +) / Double(reversals.suffix(6).count)
    }

    var hasConverged: Bool { reversals.count >= 8 }
}
```

**Rules:**

- One `Staircase` per (`profileID`, `exerciseID`, `eye`), persisted between sessions. A user resumes
  where their ability actually is, not at level 1.
- Sessions end on **whichever comes first**: convergence (8 reversals), the time budget, or a user
  stop. The reference app's flat 5-minute timer is replaced by a measurement.
- Start value on first exposure = the exercise's `defaultParameters`, adjusted by age group.
- **Anti-frustration guard:** if accuracy over the last 12 trials < 40%, force `value` two steps
  easier and log a `frustrationEvent`. Children abandon apps at exactly this point.
- **Anti-ceiling guard:** if `value` sits at `floor` (maximum difficulty) for 20 trials, mark the
  exercise "mastered" and let the plan generator retire it in favour of a harder sibling.
- Discard any trial whose frame timing shows a dropped frame (see `04` §5).

**Contrast rebalance ramp (dichoptic only)** is a second, slower loop on top: after each session where
the user completed ≥ 80% of trials at the current `contrastFellow`, raise it by 0.05 toward 1.0.
On a session with < 50% completion, drop it by 0.10. This ramp is the therapeutic variable in the
literature — treat it as the headline number, not the game score.

---

## 3. PROGRESS ANALYZER

Runs after every session and after every weekly assessment. Pure Swift, no ML.

```swift
struct ProgressAnalysis {
    let adherence7d: Double            // sessions completed / sessions planned
    let adherence28d: Double
    let currentStreak: Int
    let thresholdTrends: [String: Trend]   // exerciseID → slope, CI, direction
    let balanceTrend: Trend?               // binocular balance ratio — the key metric
    let acuityTrend: Trend?
    let plateauDetected: Bool
    let blocksWithoutImprovement: Int
    let bestTimeOfDay: DateComponents?     // when this user actually completes sessions
    let recommendedNextSession: SessionPlan
    let escalateToProfessional: Bool
}
```

**Trend method:** ordinary least squares over the last 8 data points with a bootstrap 95% CI.
A trend is only reported as "improving" if the CI excludes zero. **If it does not, the app says
"no clear change yet" — it does not invent progress.** This is both statistically honest and the thing
that separates us from every app that shows a cheerful up-and-to-the-right chart regardless of data.

**Plateau detection:** no significant improvement in the primary metric across two consecutive 4-week
blocks → `escalateToProfessional = true` → non-dismissible referral card (`04` §6 `EscalationRule`).

**Plan generation** (`PlanGenerator`) — deterministic, weighted:

```
weight(exercise) =
      1.4  if evidence tier A
    + 1.0  if targets the user's weakest measured function
    + 0.6  if not practised in the last 3 days   (spacing effect)
    + 0.5  if the user's completion rate on it is high  (adherence protection)
    - 0.8  if marked mastered
    - 1.2  if it triggered a frustrationEvent in the last 2 sessions
```

Then: pick until the time budget is filled, always leading with one dichoptic exercise, always ending
with a game for under-13, and never scheduling the same exercise twice in one session.

---

## 4. COACH NARRATOR — APPLE FOUNDATION MODELS

Introduced in iOS 26; exposes the on-device model behind Apple Intelligence via a Swift API. Runs on
Apple silicon (CPU/GPU/Neural Engine), offline, free, no key.

```swift
import FoundationModels

@Observable @MainActor
final class CoachNarrator {
    enum Backend { case onDevice, deterministic }

    static func resolveBackend() -> Backend {
        guard #available(iOS 26.0, *) else { return .deterministic }
        switch SystemLanguageModel.default.availability {
        case .available: return .onDevice
        default:         return .deterministic       // never surface an error to the user
        }
    }

    func weeklySummary(_ a: ProgressAnalysis) async -> String {
        guard case .onDevice = Self.resolveBackend(),
              #available(iOS 26.0, *) else { return DeterministicCoach.weeklySummary(a) }
        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await session.respond(to: Self.prompt(from: a))
            return Guardrails.validate(response.content) ?? DeterministicCoach.weeklySummary(a)
        } catch {
            return DeterministicCoach.weeklySummary(a)
        }
    }
}
```

**System instructions (locked — change only with a compliance review):**

```
You are a training coach inside a visual-training app. You will be given
numeric results from a user's own practice sessions.

Write 2 to 4 short sentences summarising what changed and what to do next week.

Absolute rules:
- Never diagnose. Never mention any medical condition by name.
- Never claim the user's eyesight, vision, or eye health has improved. You may
  only describe changes in TRAINING SCORES.
- Never give medical advice or suggest changing any treatment.
- Never promise future results.
- If the data shows no clear change, say so plainly. Do not manufacture optimism.
- Plain, warm, second person. No emoji. No exclamation marks. No hype.
- Under 60 words.
```

**`Guardrails.validate`** is a deterministic post-filter — **the LLM's output is never shown raw.**
Reject and fall back if the output contains any of:

```
cure, cured, treat, treatment, therapy, diagnos*, disease, heal, fix your,
vision improved, eyesight improved, medical, doctor recommends, prescription,
amblyopia, lazy eye, strabismus, guarantee, will improve, %, mg, dose
```

…or exceeds 60 words, or contains a URL, or contains an emoji. This filter is unit-tested with a
corpus of adversarial outputs. Every rejection increments a counter shown in Settings → Diagnostics
so you can see in TestFlight how often the model misbehaves.

**Where the coach appears (only three places):**

1. Session summary — one sentence.
2. Weekly assessment result — 2–4 sentences.
3. "Why this plan?" sheet on the Today screen — 2–3 sentences.

Never in the paywall (a generated sentence next to a price is a 3.1.2 risk), never in Learn articles.

**Other Foundation Models uses worth adding in v1.1:** on-device `@Generable` structured extraction to
turn a free-text "how did that feel?" note into structured tags; and rewriting Learn articles at a
child's reading level. Both are nice-to-have and both must degrade silently.

---

## 5. HEALTHKIT (v1.1, `F22`)

Read-only where possible; write the minimum.

| Direction | Type | Use |
|---|---|---|
| Read | `HKVisionPrescription` (`HKGlassesPrescription` / `HKContactsPrescription`, iOS 16+) | Detect which eye has the higher refractive error and pre-fill "which eye is weaker" — a genuinely delightful onboarding moment. Also detect `HKVisionPrism` (eye-alignment prescription) and surface the strabismus explainer. |
| Write | `HKCategoryTypeIdentifier.mindfulSession` | Session duration lands in the Health app's Mindfulness ring. The closest correct type — **do not** invent a vision-outcome sample. |
| Write | `HKWorkoutType`? | **No.** Training sessions are not workouts. |

Rules: HealthKit is fully optional, requested contextually (never at launch), with a clear
`NSHealthShareUsageDescription`. We never write anything that could be mistaken for a clinical
measurement. Denial of permission must be invisible to the rest of the app.

---

## 6. ON-DEVICE PRIVACY POSTURE (put this on a screenshot)

- No account. No sign-in. No email required.
- No network requests at all in v1.0 except Apple's own StoreKit traffic.
- No analytics SDK, no crash SDK beyond Apple's own opt-in diagnostics.
- All data in a local SwiftData store; export as JSON/PDF; one-tap delete-everything.
- App Privacy nutrition label target: **"Data Not Collected."** Very few health apps can say that, and
  it is a legitimate marketing asset.
