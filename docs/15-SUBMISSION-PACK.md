# 15 — SUBMISSION PACK

Everything to paste into App Store Connect, written against what the app **actually does now**
rather than what was planned. `09-ASO-METADATA.md` holds the strategy and the reasoning; this file
holds the final strings.

Nothing here is aspirational. If a sentence describes a feature, that feature is built, registered
and covered by tests — checked against `ExerciseRegistry` at 32 exercises.

---

## 1. THE FIELDS

| Field | Value | Chars |
|---|---|---|
| **Name** | `Amblyo: Lazy Eye Training` | 25 / 30 |
| **Subtitle** | `Amblyopia Eye Exercises Daily` | 29 / 30 |
| **Bundle ID** | `com.amblyo.app` | — |
| **SKU** | `amblyo-ios-001` | — |
| **Primary category** | Medical | — |
| **Secondary category** | Health & Fitness | — |
| **Age rating** | 4+ | — |
| **Price** | Free with subscriptions | — |

### Keywords (100 chars, comma-separated, no spaces after commas)

```
vision,binocular,stereo,depth,anaglyph,orthoptic,squint,strabismus,patching,fusion,sight,vergence
```

97 characters. Excludes every word already in the name or subtitle — Apple indexes name, subtitle
and keywords together, so "amblyopia", "eye", "lazy", "training" and "exercises" would all be
wasted characters here.

**The first draft of this list failed its own rule**, repeating "amblyopia" and "eye" from the
subtitle. A checker over the fields caught it; a human reading the list would probably not have,
because the rule and the list sit in different sections.

**"therapy", "treatment" and "cure" are absent on purpose.** They are the words the claims linter
bans in-app (`08-COMPLIANCE-LEGAL.md` §3), and using them in metadata while avoiding them in the app
would be the kind of inconsistency a 1.4.1 reviewer notices.

---

## 2. PROMOTIONAL TEXT (170 chars, editable without a new build)

```
32 exercises for lazy eye, including two-eye games that need red-cyan glasses. Progress tracking that says "no clear change" when that is the truth.
```

148 characters, counted as one line — **newlines count against the limit**, and the first draft came
to 173 because it was written across three lines and measured as if they were free.

---

## 3. DESCRIPTION

```
Amblyo is a daily eye-training app for amblyopia — the condition usually called
lazy eye, where one eye's vision stays blurred because the brain has learned to
lean on the other one.

It is an exercise app, not a replacement for eye care. It doesn't replace an eye
examination, glasses, patching, or anything an optometrist or ophthalmologist
recommends.

WHAT'S IN IT

32 exercises across three groups:

• 14 single-eye exercises that need nothing but your screen — spotting faint
  patterns, reading tiny gaps in rings, judging which line is offset, following
  a moving dot, reading progressively smaller print.

• 10 two-eye exercises that need a cheap pair of red-cyan glasses. These are the
  ones that can't be done with one eye at all: a shape hidden in speckle that
  only appears when both eyes fuse, a game where one eye sees the ball and the
  other sees the paddle, a search where each eye carries half the clue.

• 8 games built on the same mechanics, for children who won't sit through the
  plain versions.

DIFFICULTY THAT FOLLOWS YOU

Every exercise runs a staircase: three right answers make it harder, one wrong
answer steps back. Within a couple of minutes it settles where you're right
about four times in five — uncomfortable, and the level where the visual system
actually adapts.

MEASURED IN REAL SIZES

The app asks you to measure your screen once and set your viewing distance. Every
stimulus is then specified as an angle rather than a number of pixels, so a
difficulty level means the same thing on a phone and on an iPad. A few exercises
can't show their hardest levels on a small screen, and the app says so rather
than pretending.

PROGRESS YOU CAN TRUST

The Progress screen won't draw a line until there's enough data to support one.
It needs at least eight practice days of an exercise before claiming a direction,
and it says "no clear change yet" when the numbers don't separate from noise.
That's less encouraging than a rising graph, and it's the only version worth
having.

If two four-week blocks pass with no measurable change, the app says so and
suggests seeing an eye care professional — even though that's against its own
retention interest.

SAFETY

• Sessions are capped, and shorter for younger age groups.
• Breaks are offered part-way through; "my eyes feel tired" ends a session
  immediately without losing progress.
• Nothing flickers faster than 3 Hz and no exercise inverts the whole screen's
  brightness, for anyone photosensitive.

PRIVACY

Everything stays on your device. There is no account, no server, and nothing is
uploaded. Delete All Data in Profile removes every profile, session and
measurement, and there is no cloud copy to restore from.

WHAT IT DOESN'T CLAIM

No exercise in this app has been shown to restore normal vision, and no app can
promise that. Getting better at a trained task is a real result, and it is not
the same as no longer having amblyopia. The evidence badge on every exercise
says how well supported that specific exercise is, including the ones where the
honest answer is "limited".

SUBSCRIPTION

Free: one exercise and the Balance check-in.
Full access: $2.99/week, $9.99/month, or $29.99/year, covering up to 5 people.
```

---

## 4. APP REVIEW NOTES — THE IMPORTANT ONE

Paste this into App Review Information → Notes. **A reviewer without red-cyan glasses cannot
evaluate a third of this app**, and a reviewer who doesn't know that will reasonably conclude the
two-eye exercises are broken.

```
THANK YOU — TWO THINGS THAT WILL SAVE YOU TIME

1. RED-CYAN GLASSES
Ten exercises and eight games separate the two eyes using red-cyan anaglyph
filters. Without the glasses they look like faint or doubled shapes, which is
correct behaviour rather than a fault.

Every one of those screens has a "Show without glasses" toggle that renders both
layers plainly so you can evaluate the exercise. It is labelled on-screen as not
being how the exercise really looks. Profile → Red-cyan glasses → "Check they're
working" also gives a ten-second self-check with the same toggle.

You do not need to buy glasses to review this app.

2. THE MEDICAL DISCLAIMER IS A HARD GATE
Onboarding will not continue past the disclaimer step without an explicit tap.
Scrolling is not treated as consent.

WHERE TO FIND THINGS

• Medical disclaimer: shown in onboarding, and Profile → About → Medical
  disclaimer.
• Privacy policy: Profile → About → Privacy Policy (in-app, no web view), and at
  the Privacy Policy URL.
• Subscription terms with auto-renew disclosure: Profile → About → Subscription
  Terms, and on the paywall itself.
• Restore Purchases: Profile → Subscription → Restore Purchases. Deliberately
  reachable WITHOUT going through the paywall.
• Delete All Data: Profile → Data → Delete all data. It genuinely deletes and
  returns the app to onboarding.

ON GUIDELINE 1.4.1

This app makes no diagnostic or treatment claim. Scores are labelled "Training
score — not a clinical measurement" everywhere they appear. Each exercise carries
an evidence badge stating what kind of research supports it, including a tier
that says the published evidence in amblyopia specifically is limited. The
Progress screen refuses to state a direction of change until a bootstrap
confidence interval on the trend excludes zero, and after two four-week blocks
without measurable change it recommends seeing an eye care professional.

Source references are in Profile → About → Evidence and Methods. Citing research
about a class of exercise is not a claim that this app was studied, and the app
says so in those words.

ON KIDS

Age rating is 4+ and under-13 profiles get a parent gate (arithmetic, not a date
wheel) in front of any purchase. There is no third-party analytics, no
advertising, and no data collection of any kind — the PrivacyInfo manifest
declares no collected data types because none are collected.

DEMO ACCOUNT
Not required — there is no account system.
```

---

## 5. PRIVACY NUTRITION LABEL

Answer **"No, we do not collect data from this app"**, and it is true rather than convenient:

| Question | Answer |
|---|---|
| Contact info | Not collected |
| Health & Fitness | Not collected — training data never leaves the device |
| User content | Not collected |
| Identifiers | Not collected |
| Usage data | Not collected — no analytics SDK is linked |
| Diagnostics | Not collected — no crash reporter is linked |
| Tracking | No |

This must stay consistent with `App/PrivacyInfo.xcprivacy`. If an analytics or crash SDK is ever
added, **both** have to change, and the privacy policy with them.

---

## 6. SUBSCRIPTION PRODUCTS

Create these three in App Store Connect before the first paid build. The IDs are compiled into
`ProductID` and a mismatch means the paywall loads nothing — which reads to a reviewer as a broken
purchase flow.

| Product ID | Type | Duration | Price | Display name |
|---|---|---|---|---|
| `com.amblyo.app.pro.weekly` | Auto-renewable | 1 week | $2.99 | Amblyo Full Access — Weekly |
| `com.amblyo.app.pro.monthly` | Auto-renewable | 1 month | $9.99 | Amblyo Full Access — Monthly |
| `com.amblyo.app.pro.yearly` | Auto-renewable | 1 year | $29.99 | Amblyo Full Access — Yearly |

All three in one subscription group named **Amblyo Full Access**, so a user can move between them
without holding two subscriptions.

Optional: a 7-day free trial as an introductory offer on the yearly plan only. The paywall already
reads `introductoryOffer` and will show "7 days free, then $29.99" automatically — no build needed.

**Review description for each** (App Store Connect requires one):

```
Unlocks all 32 eye-training exercises including the two-eye exercises that use
red-cyan glasses, the full progress history, and up to 5 family profiles.
```

---

## 7. WHAT IS STILL OUTSTANDING BEFORE SUBMITTING

- [ ] Create the three subscription products above.
- [ ] Screenshots — `11-SCREENSHOTS-SPEC.md`. 6.9" and 13" are the required sizes.
- [ ] Confirm the Support URL and Privacy Policy URL resolve (both were verified live in Phase 4;
      re-check before submitting).
- [ ] Delete the three unused `MATCH_*` secrets from GitHub.
- [ ] Apply to the Apple Small Business Program — 15% instead of 30% under $1M, and it applies from
      the start of the month you're approved in.
- [ ] External TestFlight round with real red-cyan glasses. **The anaglyph compositor's arithmetic is
      verified and its behaviour through real glasses on a real panel is not** — that is a physical
      fact nobody on this project has checked, and it should be checked before the store rather
      than after.
