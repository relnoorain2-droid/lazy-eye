# 09 — APP NAME, ASO & METADATA

**Character limits (2026):** Name 30 · Subtitle 30 · Keywords 100 · Promotional text 170 ·
Description 4000 · What's New 4000, per localisation.

**The only indexed fields are Name + Subtitle + Keywords = 160 characters total.** The description is
**not** indexed by Apple's search (unlike Google Play). Every one of those 160 characters is precious;
the description exists to convert, not to rank.

---

## 1. APP NAME — SHORTLIST

You asked for a name where the user understands the purpose from the name alone. That means
**brand + descriptor**, with the descriptor carrying the top keyword.

### ✅ Recommended

> ## `Amblyo: Lazy Eye Training`
> **25 characters.**

Why: "Amblyo" is short, ownable, trademark-able, and evokes *amblyopia* to anyone who has been
diagnosed — which is our entire audience. "Lazy Eye Training" tells a stranger exactly what it does and
puts the highest-volume keyword in the highest-weighted field. "Training" (not "Therapy", not
"Treatment") is deliberate — see `08` §3.

### Alternates, in order

| Name | Chars | Note |
|---|---|---|
| `VisionUp: Lazy Eye Training` | 27 | Friendlier, less clinical. "VisionUp" is likely taken — check. |
| `EyeBalance: Lazy Eye Trainer` | 28 | "Balance" nicely signals the binocular/anti-suppression concept, our actual differentiator |
| `Amblyo — Eye Training & Games` | 29 | Use if you want "games" indexed; loses "lazy eye" from the name |
| `Lazy Eye Trainer: Amblyo` | 24 | Descriptor-first. Marginally better raw ranking, weaker brand |

### ⚠️ Before you lock it in (Phase 0)

1. Search the App Store for the exact name **and** for "Amblyo" — a near-identical name gets you a
   5.2.1 rejection.
2. Check `amblyo.com` / `amblyo.app` availability.
3. Search USPTO TESS (and your local registry) for "Amblyo" in class 9 and 44.
4. Do **not** use "AmblyoPlay", "Luminopia", "CureSight", or "Vivid Vision" or any near-miss of them.
5. Once the bundle ID and app record are created, the bundle ID is permanent. The display name can
   change; the bundle ID cannot.

---

## 2. SUBTITLE (30 chars)

> ## `Amblyopia Eye Exercises Daily`
> **29 characters.**

Adds "amblyopia" and "eye exercises" — two high-intent phrases the name doesn't cover — plus "daily",
which signals habit. Do not repeat any word from the name; Apple indexes name and subtitle together and
duplicates waste characters.

Alternates: `Vision Therapy Eye Exercises` (28) — but "therapy" is a banned word for us (`08` §3), so
**no**. `Amblyopia Vision Training Kit` (29). `Binocular Eye Exercise Trainer` (30).

---

## 3. KEYWORDS FIELD (100 chars)

Rules: comma-separated, **no spaces after commas** (a space costs a character), no plurals if the
singular is present (Apple stems), no words already in Name or Subtitle, no competitor names, no
category name ("Medical"/"Health"), no "app"/"free"/"best".

Already covered by Name + Subtitle: `amblyo, lazy, eye, training, amblyopia, exercises, daily`

> ```
> vision,strabismus,squint,orthoptic,patch,binocular,stereo,anaglyph,fusion,acuity,sight,visual,kids
> ```
> **98 characters.** (Verified by count; the limit is 100. "patching" is omitted because Apple stems
> it from "patch" — including both wastes 9 characters.)

Rationale per term:

| Term | Why |
|---|---|
| `vision` | Combines into "vision training", "vision exercises", "vision therapy" via Apple's phrase matching |
| `strabismus`, `squint` | Huge adjacent search volume; users confuse the two conditions (`14` R5). "squint" is the dominant UK/IN/AU term |
| `orthoptic` | Low volume, very high intent — clinicians and informed parents |
| `patch` | The single highest-intent parent search: "alternative to eye patching". Stems to "patching", "patches" |
| `binocular`, `stereo`, `anaglyph`, `fusion` | Our differentiator; almost no competitor ranks here |
| `acuity` | Clinical searchers |
| `sight`, `visual` | Combiner words that unlock many two-word phrases |
| `kids` | "lazy eye kids", "eye exercises kids" |

Deliberately excluded: `therapy`/`treatment` (banned by `08` §3 — do **not** put them here even though
they have volume; the keyword field is metadata and is scanned in a 1.4.1 review),
`glasses` (wrong intent — people searching for eyewear), `test` (implies diagnosis).

**Localisation trick:** the `en-GB`, `en-AU`, and `en-CA` localisations get their **own** 100-char
keyword field. Use them for regional terms (`squint`, `lazyeye`) and to double your indexed surface.
`es-MX` and `es-ES` likewise for `ojo vago`, `ambliopía`, `ojo perezoso`.

---

## 4. PROMOTIONAL TEXT (170 chars, editable without a new build)

> ```
> New: contrast-balanced binocular exercises you can do with $5 red-cyan glasses,
> plus weekly progress tracking that runs entirely on your device. No account needed.
> ```
> 160 characters.

Change this monthly. It's the only metadata you can edit without submitting a build, so use it for
seasonal messaging, new-exercise announcements, and A/B-ish testing of your hook.

---

## 5. DESCRIPTION (4000 chars)

Not indexed by search — its job is conversion. Only the **first ~3 lines** are visible before "more",
so front-load. Every claim here is checked against `08` §3.

```
Guided eye exercises for people with amblyopia — lazy eye — built for iPad and
designed to be done at home, a few minutes a day.

Amblyo is a visual training app. Most lazy-eye apps show you a moving dot and a
five-minute timer. Amblyo does something different: it uses contrast-balanced
binocular exercises, where each eye sees a different part of the task, so the
task can only be completed when both eyes work together. This approach comes
from published research into binocular visual training, and it is what makes
Amblyo different from the eye-exercise apps you have already tried.

WHAT'S INSIDE

• 32 exercises across three tracks
  – 14 monocular exercises, done with your stronger eye covered
  – 10 binocular exercises using inexpensive red-cyan glasses
  – 8 training games for children, built on the same binocular principle
• A weekly check-in that measures four things: acuity, contrast sensitivity,
  binocular balance and depth
• Progress charts that show what has actually changed — and say "no clear
  change yet" when that's the honest answer
• A daily plan that adapts to you after every single trial

BUILT AROUND THE RESEARCH

Every exercise carries an evidence badge. Tap it and you'll see what kind of
research supports that type of exercise, in plain English. We label our
strongest exercises and our weakest ones with the same honesty. There is no
exercise in Amblyo that we can't point to a reason for.

ADAPTS TO YOU, ON YOUR DEVICE

Amblyo uses a psychophysical staircase — the same method used in vision
laboratories — to find the exact difficulty where you are working hard but
succeeding about four times in five. It adjusts after every response, for every
exercise, for each eye. On supported devices, Apple's on-device intelligence
turns your results into a short plain-language summary each week. Nothing is
sent anywhere. There is no server.

MADE FOR iPAD

Amblyo is designed for the large screen first. It asks how far you sit from the
display and uses your device's real screen dimensions, so a stimulus that is
supposed to be one degree wide actually is. Split View, Stage Manager, hardware
keyboard and Apple Pencil are all supported. It works beautifully on iPhone too.

FOR CHILDREN

Kids mode brings a reward map, larger targets, a 20-minute daily cap and a
parent gate on settings and purchases. No loot boxes, no currency, no
streak-loss pressure. Sound is off until you turn it on — all of it, every
channel, one tap.

PRIVATE BY DEFAULT

No account. No sign-in. No email. No analytics. No advertising. Amblyo makes no
network requests at all beyond the App Store. Everything you do stays on your
device, and you can export or delete all of it at any time.

IMPORTANT

Amblyo is a training app. It is not a medical device and it is not a medical
treatment. It does not diagnose, treat, cure or prevent any condition, and it is
not a substitute for care from a qualified eye care professional. The scores in
Amblyo are training scores, not clinical measurements. Please see an optometrist
or ophthalmologist for an eye examination, wear any correction you have been
prescribed, and follow any plan your eye doctor has given you. Do not cover a
child's eye without professional guidance.

Amblyo is not suitable for people with macular degeneration, glaucoma, retinal
or optic nerve disease, recent eye surgery, new double vision, sudden vision
loss, or photosensitive epilepsy.

SUBSCRIPTION

Amblyo Pro unlocks all 32 exercises, the full weekly assessment, complete
progress history, the on-device coach and up to five profiles.

• Yearly — $29.99 per year, after a 7-day free trial (about $0.58 a week)
• Monthly — $9.99 per month
• Weekly — $2.99 per week

The free trial is available on the yearly plan only. If you don't cancel before
the trial ends, your Apple Account is charged $29.99 and the subscription begins.

Payment is charged to your Apple Account at confirmation of purchase.
Subscriptions renew automatically unless auto-renew is turned off at least 24
hours before the end of the current period. Your account is charged for renewal
within 24 hours before the end of the current period. You can manage and cancel
your subscriptions in your Apple Account settings after purchase. Any unused
portion of a free trial is forfeited when you buy a subscription. Four
exercises and the core features are free, with no time limit and no ads.

Terms of Use: Apple Standard EULA (see website/README.md)
Privacy Policy: https://sites.google.com/view/amblyolazyeyetraining/privacy-policy
Support: https://sites.google.com/view/amblyolazyeyetraining/support
```

**The subscription paragraph is mandatory** — Apple requires auto-renew terms in the description as
well as in the app (`07` §5).

---

## 6. CATEGORY & SEARCH STRATEGY

| Field | Value |
|---|---|
| Primary category | **Medical** |
| Secondary category | **Health & Fitness** |

Medical is a much less crowded category than Health & Fitness, so a Medical "Top Charts" placement is
achievable at far lower download volume. It does attract slightly more review scrutiny — which is why
`08` exists.

**Ranking priorities, in order:** `lazy eye` › `amblyopia` › `eye patching alternative` ›
`eye exercises` › `vision training` › `squint exercises` › `binocular vision`.

**Realistic 6-month goal:** top 5 for "amblyopia" and "lazy eye" in US/UK/IN. The incumbent has
37 ratings in seven years — a well-executed app with 200+ ratings will outrank it.

---

## 7. IN-APP EVENTS & CUSTOM PRODUCT PAGES

Both are free ASO surface most indie developers ignore.

- **Custom Product Pages** (up to 35): make one for parents ("Make patching time less of a fight") and
  one for adults ("They told you it was too late after age 8"). Different screenshots, different first
  line. Use them as landing pages for any paid or social traffic.
- **In-App Events:** "New: Binocular Games Pack", "12-Week Training Challenge". These appear in App
  Store search results and get their own card.
- **Product Page Optimization:** A/B test icon and first screenshot once you have traffic.

---

## 8. LOCALISATION PRIORITY

| Wave | Locales | Reason |
|---|---|---|
| 1 (launch) | `en-US`, `en-GB`, `en-AU`, `en-CA` | Free extra keyword fields; "squint" is the dominant non-US term |
| 2 | `es-MX`, `es-ES`, `pt-BR` | Large populations, low competition, high amblyopia awareness |
| 3 | `de-DE`, `fr-FR`, `it-IT` | High ARPU |
| 4 | `hi-IN`, `ar-SA`, `id-ID` | Enormous volume, very low competition; India especially — "squint" and "lazy eye" are common searches and the incumbent doesn't localise |

Even before you translate the app, **localise the metadata** — the extra keyword fields alone are worth
it, and Apple allows metadata-only localisation.

---

## 9. THE "SEO" QUESTION (web, not App Store)

You mentioned SEO. Two different things:

- **ASO** = everything above. This is what drives App Store installs.
- **Web SEO** = your support/privacy site. Worth doing lightly: publish the 12 Learn articles as public
  web pages on the same domain (`/learn/what-is-amblyopia`, `/learn/patching-alternatives`,
  `/learn/adult-lazy-eye-exercises`). They rank for long-tail informational queries, they give App
  Review a credible-looking home page, and every article ends with an App Store badge. This is the
  highest-ROI marketing work outside the app itself — one article per week, written from
  `01-RESEARCH-BRIEF.md`, all subject to the `08` §3 language rules.

  **Apply the `08` §3 language rules to the website too, including URL slugs.** A reviewer
  investigating 1.4.1 will open your support site. A page at `/lazy-eye-treatment` undermines
  everything the app copy is careful about.
