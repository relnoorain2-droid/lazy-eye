# 16 — EXERCISE STAGE

How every exercise screen looks, and the one rule that constrains all of it.

Written after the first real device test. The verdict was "very bad visuals, none of them
perfect, unprofessional", and it was correct. This document exists so the fix is a system
rather than 32 separate touch-ups.

---

## 1. THE CONSTRAINT THAT COMES FIRST

**The stimulus field must stay mid-grey, and the stimulus must stay angularly sized.**

This is not a style position and it is not negotiable for aesthetics.

A Gabor patch modulates luminance *symmetrically above and below the background*. On a dark
or coloured background the negative half of the sinusoid has nowhere to go, it clips, and the
contrast presented is not the contrast requested. Every threshold measured that way is
measuring the display rather than the person. The same argument applies to contrast
detection, Vernier offsets, crowded letters and the whole monocular track.

So the temptation — deep navy backdrop, gradient, glow behind the stimulus, all the things
that would make a screenshot look expensive — is off the table *for the area the stimulus
occupies*.

The reference app fills the screen with a rotating high-contrast spiral. It looks alive. It
is also the reason its numbers mean nothing: nothing about that presentation is controlled.
Beating it on looks while keeping the measurement honest is the actual design problem, and
"make it darker and add a glow" is not a solution to it.

**What that leaves, and it is plenty:** everything that is not the stimulus field. The stage
around it, the countdown, the answer bar, the transitions, the feedback, the sound, the
haptics, the ready and summary screens. That is where the app currently looks like a
prototype, and none of it is load-bearing for measurement.

---

## 2. THE DIAGNOSIS, SPECIFICALLY

From the device screenshots, what is actually wrong:

| Symptom | Cause | Fixable without touching the measurement? |
|---|---|---|
| Flat grey screen edge to edge | `Color.stimulusNeutral.ignoresSafeArea()` fills everything | Yes — confine grey to a defined stage |
| Stimulus looks lost and small | It is angularly correct, but has no frame giving it scale | Yes — the frame is what is missing, not the size |
| Timer nearly invisible top-left | Plain small text, low contrast on grey | Yes |
| Answer buttons are plain white rectangles | No icon, no depth, no press state | Yes |
| Nothing happens on answer | No sound, no haptic, feedback mark only | Yes |
| Check-in shows numbered buttons over blank space | Stimulus views were deferred | Yes — wire the real views |

Five of the six are chrome. **The stimulus itself was never the problem**, which is worth
stating plainly because the instinct after "the visuals are bad" is to change the thing in
the middle of the screen, and that is the one thing that is right.

---

## 3. THE STAGE

One container, `ExerciseStage`, that every exercise renders inside. Adopting it changes all
32 screens at once; that is the entire point of building it rather than editing 32 files.

```
┌─────────────────────────────────────┐
│  ◷ 4:58        Stripe Tilt      ⏸   │  ← chrome bar: countdown ring, title, pause
│                                     │     on app surface, NOT on the stimulus field
├─────────────────────────────────────┤
│                                     │
│                                     │
│         ┌───────────────┐           │
│         │               │           │  ← STIMULUS FIELD
│         │   [stimulus]  │           │     mid-grey, exact, unstyled
│         │               │           │     rounded corners + soft outer shadow
│         └───────────────┘           │     so it reads as a deliberate surface
│                                     │
│                                     │
├─────────────────────────────────────┤
│    ┌──────────┐   ┌──────────┐      │
│    │    ←     │   │    →     │      │  ← answer bar: large, iconed, haptic
│    │   Left   │   │  Right   │      │     56 pt tall, full-width pair
│    └──────────┘   └──────────┘      │
│         🔊    ⏸    👁               │  ← session controls
└─────────────────────────────────────┘
```

### The stimulus field

- Mid-grey `stimulusNeutral`, unchanged, no gradient, no tint, no overlay.
- Corner radius 28, soft outer shadow. The shadow is *outside* the field, so it never falls
  on stimulus pixels.
- Sized to the largest square the layout allows, so the same field appears on every device
  and the stimulus inside it keeps its own angular size regardless.
- **The field never scales its contents.** No `scaledToFit`, no `aspectRatio` on the
  stimulus image, no frame that could resize it. A test enforces this.

### The countdown

A ring, not a number in a corner. 44 pt, stroked, depleting anticlockwise, with the remaining
time inside it. Visible at a glance without competing with the stimulus for attention — which
is why it sits in the chrome bar on app surface rather than floating over the grey.

### The answer bar

- Minimum 56 pt tall, which is above Apple's 44 pt floor and comfortable for a child.
- Icon plus label. The icon carries the meaning at speed; the label removes ambiguity.
- Press state: scale 0.97, immediate. Nothing to think about, just confirmation that the tap
  registered.
- Disabled during feedback so a double-tap cannot answer the next trial.

### Feedback

- 260 ms. Long enough to read, short enough not to slow a 40-trial run.
- Correct: brief tick, soft rising tone, light haptic.
- Incorrect: brief mark, soft falling tone, light haptic. **Not** a buzz, not red-flash,
  nothing punitive — a staircase is *designed* to produce wrong answers about one time in
  five, so punishing them punishes the user for the method working.

---

## 4. SOUND

Currently `AudioEngine.play()` ends at `// Phase 3: actual playback` and the project contains
zero audio files. Four toggles in Settings control nothing. That is the honest starting point.

**Tones are generated, not bundled.** A short sine with an envelope, synthesised at runtime.
No asset licensing, no file size, no attribution, and every cue stays consistent with the
others by construction. Bundled effects would be quicker to a first sound and worse at every
point after that.

| Cue | Sound | Channel |
|---|---|---|
| Correct | 880 Hz, 90 ms, soft attack | effect |
| Incorrect | 320 Hz, 120 ms | effect |
| Session start | two-tone rise | effect |
| Session end | three-tone resolve | effect |
| Break start / end | single soft tone | effect |
| Spoken guidance | `AVSpeechSynthesizer`, on-device | voice |

The `.ambient` category stays. The hardware silent switch must silence this app — the
reference app ignores it and has the one-star reviews to show for it.

---

## 5. HAPTICS

- Answer registered: light impact.
- Correct: success notification.
- Incorrect: warning notification, at the lightest available weight.
- Session complete: success notification.

Gated on the existing haptics setting, which currently gates nothing.

---

## 6. WHAT SUCCESS LOOKS LIKE

Not "it looks nicer". Three checkable things:

1. A screenshot of any exercise is something you would put on the App Store page without
   editing it.
2. Every stimulus dimension in `StimulusFitTests` and `RenderLimitTests` is byte-identical
   before and after. The overhaul must not move a single measured value.
3. Answering a trial produces a sound and a haptic that a user notices without being told to
   look for them.
