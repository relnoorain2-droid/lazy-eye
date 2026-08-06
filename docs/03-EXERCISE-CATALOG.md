# 03 — EXERCISE CATALOG

32 exercises across three packs. Every entry is a build spec: read the row, build the screen.

**Evidence tiers** (shown as a badge in-app, defined in `01-RESEARCH-BRIEF.md` §2):
**A** = RCT evidence in amblyopia · **B** = perceptual-learning evidence · **C** = standard orthoptic
practice, weaker evidence for amblyopia specifically. **No Tier D content ships.**

**Shared parameter vocabulary** (all exercises implement `ExerciseParameters`):

```swift
struct ExerciseParameters {
    var stimulusAngularSize: Double      // degrees, derived from calibration
    var contrastAmblyopic: Double        // 0…1, always 1.0 unless explicitly reduced
    var contrastFellow: Double           // 0…1, the dichoptic rebalance knob
    var spatialFrequency: Double         // cycles/degree
    var temporalRate: Double             // Hz, hard-capped ≤ 3.0 (photosensitivity)
    var eccentricity: Double             // degrees from fixation
    var targetCount: Int
    var speed: Double                    // deg/second
    var noiseLevel: Double               // 0…1 external noise
    var responseWindow: TimeInterval
    var durationSeconds: Int             // default 300, user-adjustable 120…600
}
```

**Every exercise must implement:**
`ExerciseProtocol` → `id`, `title`, `pack`, `evidenceTier`, `targetFunction`, `defaultParameters`,
`makeView(session:)`, `difficultyDimension` (the single scalar the staircase moves),
`scoreTrial(_:) -> Bool`, `requiresAnaglyph: Bool`, `minimumAge: Int`.

---

## PACK 1 — MONOCULAR (14) · no accessory, weaker eye working alone with the fellow eye occluded

> Occlusion warning is shown before the first monocular session of each week (`14` R11).

| # | ID | Title | Tier | Targets | Mechanic | Staircase dimension |
|---|---|---|---|---|---|---|
| M1 | `m.gaborOrientation` | Gabor Orientation | **B** | Acuity, orientation discrimination | A Gabor patch appears; user swipes/taps which way the stripes lean (2AFC ±Δ°). The single best-evidenced perceptual-learning task. | Orientation difference Δ° (start 20°, floor 1°) |
| M2 | `m.contrastDetection` | Contrast Hunt | **B** | Contrast sensitivity | Grating appears in one of 4 quadrants at low contrast; tap the quadrant. | Michelson contrast (start 0.5, floor 0.005) |
| M3 | `m.flankedGabor` | Crowded Gabor | **B** | Contrast sensitivity, lateral interaction | Central Gabor flanked by two high-contrast Gabors at variable separation; detect the centre. Replicates the lateral-masking training literature. | Flanker separation in λ |
| M4 | `m.vernier` | Vernier Line-Up | **B** | Hyperacuity, positional precision | Two line segments; is the top offset left or right? Hyperacuity thresholds improve markedly with training. | Offset in arc-seconds |
| M5 | `m.landoltC` | Landolt Rings | **B** | Acuity | Ring with a gap; tap the gap direction (8AFC). | Ring size (logMAR steps) |
| M6 | `m.crowdedLetters` | Crowded Letters | **B** | Acuity under crowding | Target Sloan letter surrounded by flankers; identify it. Crowding is disproportionately severe in amblyopia — a real, specific deficit. | Flanker spacing + letter size |
| M7 | `m.globalMotion` | Motion Field | **B** | Global motion (dorsal stream) | Random-dot kinematogram; which way is the coherent flow? | Motion coherence % (start 90%, floor 3%) |
| M8 | `m.globalForm` | Glass Pattern | **B** | Global form (ventral stream) | Concentric vs radial Glass pattern in noise; pick the type. | Signal-dot % |
| M9 | `m.pursuits` | Smooth Pursuit | **C** | Oculomotor pursuit | Follow a target on a smooth path (Lissajous/figure-8); tap when it changes colour. Colour changes are the compliance check — proves the user is actually tracking. | Speed + path complexity |
| M10 | `m.saccades` | Jump Targets | **C** | Saccadic accuracy | Targets appear at pseudo-random eccentricities; tap as fast and accurately as possible. | Eccentricity + response window |
| M11 | `m.hartChart` | Hart Chart | **C** | Accommodative facility, acuity stamina | Grid of letters; call/tap them in a prompted order, near then far. Digital version of the classic clinic chart. | Grid density + pace |
| M12 | `m.visualSearch` | Find It | **C** | Visual search, attention | Find N targets among distractors under time pressure. Engagement workhorse for kids. | Set size + similarity |
| M13 | `m.tracing` | Path Tracer | **C** | Eye-hand coordination | Trace a winding path with a finger or Apple Pencil without leaving the corridor. | Corridor width + path curvature |
| M14 | `m.readingRate` | Reading Ladder | **B** | Functional acuity | Timed short-passage reading at decreasing print size; comprehension check at the end. The most functionally meaningful monocular measure. | Print size (logMAR) |

---

## PACK 2 — DICHOPTIC (10) · requires red-cyan glasses · **this is the differentiator**

> Every exercise here is **impossible to complete monocularly.** That forcing function is the therapy.
> All are driven by the same `contrastFellow` ramp (see `01` §4). Global tier **A** by modality —
> the specific tasks vary, so per-exercise tiers are marked honestly.

| # | ID | Title | Tier | Targets | Mechanic | Staircase dimension |
|---|---|---|---|---|---|---|
| D1 | `d.balancedViewing` | Balanced Viewing | **A** | Suppression, binocular fusion | Any user-chosen video (Photos library or bundled clips) rendered with contrast rebalanced between the eyes. The closest legal analogue to the contrast-rebalanced-movie RCTs. Passive, high-adherence, the flagship. | `contrastFellow` (start 0.2 → 1.0) |
| D2 | `d.dichopticMatch` | Split Match | **A** | Anti-suppression | Card-matching where half of each card's features go to one eye and half to the other. Cannot be solved with one eye. | `contrastFellow` + card count |
| D3 | `d.fallingBlocks` | Stack Drop | **A** | Anti-suppression, sustained fusion | Tetris-style: **falling piece → amblyopic eye, the stack → fellow eye.** The canonical dichoptic game from the literature. | `contrastFellow` + drop speed |
| D4 | `d.breakout` | Bounce | **A** | Anti-suppression | Ball to the amblyopic eye, paddle + bricks to the fellow eye. | `contrastFellow` + ball speed |
| D5 | `d.suppressionCheck` | Balance Meter | **A** | Suppression measurement | Not a game — the **measurement**. Signal-in-noise: signal dots to one eye, noise dots to the other; find the balance point where both contribute equally. Yields a single "binocular balance ratio" number, tracked weekly. This is the app's most defensible metric. | Interocular contrast ratio |
| D6 | `d.randomDotStereo` | Depth Pop | **A** | Stereopsis | Random-dot stereogram: which shape floats forward? Pure stereo, invisible monocularly. | Disparity in arc-minutes |
| D7 | `d.vergenceJump` | Depth Steps | **C** | Vergence range | Fusible target steps in disparity, base-out then base-in; user reports when it doubles. Digital jump-vergence. | Disparity step size |
| D8 | `d.brockDigital` | Bead Line | **C** | Convergence awareness, suppression feedback | Digital Brock string: beads at simulated depths; user reports how many strings they see at each bead (2 = fusing, 1 = suppressing). Feedback on suppression, in real time. | Bead depth spacing |
| D9 | `d.dichopticSearch` | Hidden Half | **B** | Anti-suppression, search | Targets defined only by the conjunction of a red-eye feature and a cyan-eye feature. | `contrastFellow` + distractor count |
| D10 | `d.fusionLock` | Hold the Fusion | **B** | Fusion stamina | A fusible pattern with a peripheral fusion lock; user holds a button while fused, releases the instant it breaks. Measures fusion duration — a stamina metric, not an accuracy one. | Fusion-lock strength + duration target |

---

## PACK 3 — GAMES (8) · dichoptic-by-default, monocular fallback, engagement-first

Same rendering engine as Pack 2 but with reward loops, characters and score. Tier **A** when run in
dichoptic mode (they are dichoptic training wearing a game costume), **C** in monocular fallback.
Kids mode surfaces these first.

| # | ID | Title | Loop | Kid appeal |
|---|---|---|---|---|
| G1 | `g.balloonPop` | Balloon Pop | Balloons rise; pop before they escape | 3–7 |
| G2 | `g.skyCatch` | Sky Catch | Move a basket to catch falling fruit | 3–7 |
| G3 | `g.whackMole` | Peekaboo | Creatures pop from burrows | 3–7 |
| G4 | `g.mazeRunner` | Maze Runner | Walls to one eye, runner to the other | 5–12 |
| G5 | `g.starTracer` | Star Tracer | Connect constellations along a moving path | 5–12 |
| G6 | `g.colorSort` | Color Sort | Sort items by a feature only visible binocularly | 5–12 |
| G7 | `g.rhythmTap` | Rhythm Tap | Timing game; **visual-only mode is the default** (sound is opt-in, see `14` R1) | 8+ |
| G8 | `g.spaceDodge` | Space Dodge | Ship to one eye, obstacles to the other | 8+ |

---

## ASSESSMENT BATTERY (4 sub-tests, ~6 min, weekly)

Not in the 32. These produce the numbers on the Progress screen.

| ID | Test | Method | Output | Guardrail |
|---|---|---|---|---|
| `a.acuity` | Acuity Check | Landolt-C staircase at calibrated distance, per eye | logMAR-**style** score | Labelled **"training score, not a clinical measurement"** everywhere it appears — required by Guideline 1.4.1 |
| `a.contrast` | Contrast Check | Sine-grating contrast threshold at 4 spatial frequencies | Contrast-sensitivity curve | Same label |
| `a.balance` | Balance Check | `d.suppressionCheck` procedure | Binocular balance ratio 0…1 | The app's most trustworthy metric |
| `a.stereo` | Depth Check | Random-dot stereogram staircase | Disparity threshold, arc-min | Screening only, never diagnostic |

---

## DIFFICULTY CURVE, GLOBALLY

Every exercise runs a **3-down / 1-up transformed staircase**, converging on ~79.4% correct — hard
enough to drive learning, not so hard it demoralises. Details and code sketch in `06-AI-ENGINE-SPEC.md`
§2. Levels 1–20 are cosmetic labels mapped onto the measured threshold; the staircase is the truth.

---

## AGE GROUPS

Replaces the reference app's "Under 5 / 5–12 / Above 12" with a functional mapping:

| Group | Default pack order | Session length | Notes |
|---|---|---|---|
| Under 5 | Games → Dichoptic → Monocular | 10 min, hard cap 20 | Big targets, no reading, no timers on screen, parent starts every session |
| 5–12 | Games → Dichoptic → Monocular | 20 min, hard cap 20 | Reward map, streaks, parent gate on settings and paywall |
| 13+ | Dichoptic → Monocular → Games | 25–30 min | Full charts, evidence sheets, adult skin |
